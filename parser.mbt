// The DEC VT500 byte parser.

// Cap on CSI/DCS parameters (vte/rio-vt = 32).
const MAX_PARAMS : Int = 32

// Max CSI/DCS parameter value: DEC VT500 params are 16-bit (`0..=65535`).
const MAX_PARAM_VALUE : Int = 65535

// Cap on CSI/DCS intermediates before extras are dropped (the DEC spec caps
// these at two).
const MAX_INTERMEDIATES : Int = 2

// Cap on OSC parameters (vte/rio-vt = 16); the remaining payload is dropped.
const MAX_OSC_PARAMS : Int = 16

// Maximum buffered OSC payload. A hostile program can otherwise stream a
// gigabyte into `ESC ] … ST` and OOM the parser; xterm.js caps OSC/DCS at
// `PAYLOAD_LIMIT = 10000000` and aborts the sequence, so we bound here too.
const MAX_OSC_PAYLOAD : Int = 1048576

///|
/// A byte-input DEC VT500 terminal parser.
///
/// Feed bytes with `advance`; the `Perform` sink receives the decoded events.
/// Collect owned events via `parse_events` / `Recording`.
pub struct Parser {
  mut state : ParseState
  /// CSI/DCS parameter currently being accumulated (clamped to
  /// `0..=65535`; `-1` is the empty-param sentinel).
  mut param : Int
  /// True while the current parameter is empty (no digits seen since the
  /// last `;`/`:`).
  mut param_empty : Bool
  /// Collected CSI/DCS parameters, capped at `MAX_PARAMS`.
  mut params : Array[Int]
  mut params_len : Int
  /// Colon separators: bit `i` is set when parameter `i` was followed by `:`
  /// (rather than `;`).
  mut sep : Int
  /// Collected intermediates (private markers + `0x20..=0x2f`), capped at 2.
  mut intermediates : Array[Int]
  mut intermediates_len : Int
  /// OSC payload accumulator.
  mut osc : Array[Int]
  /// Set when an OSC payload exceeds `MAX_OSC_PAYLOAD`; the whole OSC is
  /// then discarded.
  mut osc_overflow : Bool
  /// Start offset of each OSC param in `osc` (or in the input slice while
  /// deferred); `;` separators are not stored. `starts[0]` is always 0.
  mut osc_starts : Array[Int]
  mut osc_num_starts : Int
  /// True while the OSC payload is still entirely within the current
  /// `advance` input slice (no copy into `osc` yet); `osc_base` is its start
  /// index in that slice.
  mut osc_deferring : Bool
  mut osc_base : Int
  /// Partially-decoded UTF-8 code point split across `advance` calls.
  mut partial : Int
  /// Continuation bytes still needed to complete `partial` (0 = none).
  mut partial_need : Int
  /// Runtime SIMD toggle for the printable-run scan.
  mut simd : Bool
}

///|
/// Create a parser in the ground state (scalar decode).
pub fn Parser::new() -> Parser {
  {
    state: ParseState::Ground,
    param: 0,
    param_empty: true,
    params: [],
    params_len: 0,
    sep: 0,
    intermediates: [],
    intermediates_len: 0,
    osc: [],
    osc_overflow: false,
    osc_starts: [],
    osc_num_starts: 0,
    osc_deferring: false,
    osc_base: 0,
    partial: 0,
    partial_need: 0,
    simd: false,
  }
}

///|
/// Create a parser with the SIMD printable-run scan enabled.
pub fn Parser::with_simd() -> Parser {
  let p = Parser::new()
  p.simd = true
  p
}

///|
/// Reset to the ground state, clearing any pending partial code point and
/// buffered OSC payload. The SIMD toggle (a per-parser config) is preserved.
pub fn Parser::reset(self : Parser) -> Unit {
  let simd = self.simd
  self.state = ParseState::Ground
  self.param = 0
  self.param_empty = true
  self.params = []
  self.params_len = 0
  self.sep = 0
  self.intermediates = []
  self.intermediates_len = 0
  self.osc = []
  self.osc_overflow = false
  self.osc_starts = []
  self.osc_num_starts = 0
  self.osc_deferring = false
  self.osc_base = 0
  self.partial = 0
  self.partial_need = 0
  self.simd = simd
}

///|
/// Parse `bytes`, returning the decoded events as an owned `Array[Event]`.
///
/// Allocates one `Event` per dispatch — for tests and tooling. Prefer
/// `advance` with a `Perform` sink on the hot path.
pub fn Parser::parse_events(
  self : Parser,
  bytes : ArrayView[Int],
) -> Array[Event] {
  let rec = Recording::new()
  self.advance(rec, bytes)
  rec.events()
}

///|
/// Parse `bytes`, dispatching each decoded event to the sink `p`.
///
/// This is the hot path (no intermediate `Event`s); see `parse_events` for
/// the owned enum API.
pub fn[P : Perform] Parser::advance(
  self : Parser,
  p : P,
  bytes : ArrayView[Int],
) -> Unit {
  if bytes.length() == 0 {
    return
  }
  let mut i = 0
  // Complete a partially-decoded UTF-8 code point carried from the previous
  // call (accumulate continuation bytes into the code point).
  if self.partial_need > 0 {
    let mut completed = false
    while self.partial_need > 0 && i < bytes.length() {
      let b = bytes[i]
      if b >= 0x80 && b <= 0xbf {
        self.partial = (self.partial << 6) | (b & 0x3f)
        self.partial_need = self.partial_need - 1
        i = i + 1
        completed = self.partial_need == 0
      } else {
        // Not a continuation byte — abort the partial, leave the byte for
        // the main loop.
        self.partial_need = 0
        p.print('\u{FFFD}')
        break
      }
    }
    if completed {
      dispatch_cp(p, self.partial)
    }
  }
  // Detect a trailing partial code point once here, handing the partial-free
  // prefix length to the ground loop.
  let valid_end = match trailing_partial(bytes) {
    Some((v, cp, need)) => {
      self.partial = cp
      self.partial_need = need
      v
    }
    None => bytes.length()
  }
  while i < bytes.length() {
    match self.state {
      ParseState::Ground => i = self.advance_ground(p, bytes, i, valid_end)
      ParseState::OscString => i = self.advance_osc_run(p, bytes, i)
      ParseState::DcsPassthrough => i = self.advance_dcs_run(p, bytes, i)
      ParseState::Escape => i = self.advance_escape_byte(p, bytes, i)
      ParseState::DcsEntry => i = self.advance_dcs_entry_byte(p, bytes, i)
      ParseState::CsiParam | ParseState::DcsParam =>
        i = self.advance_param_run(p, bytes, i)
      _ => i = self.advance_non_ground(p, bytes, i)
    }
  }
  // An OSC payload that reached the end of this input chunk without a
  // terminator is flushed into `osc` so the next `advance` continues it.
  if self.state == ParseState::OscString && self.osc_deferring {
    self.osc_flush(bytes, bytes.length())
  }
}

///|
/// Emit a pending partial UTF-8 code point as `U+FFFD` (W3C substitution) at
/// end-of-stream. Call once after the final `advance`.
pub fn[P : Perform] Parser::flush(self : Parser, p : P) -> Unit {
  if self.partial_need == 0 {
    return
  }
  self.partial_need = 0
  p.print('\u{FFFD}')
}

///|
/// Ground state: scan for the next non-printable byte, bulk-dispatch
/// printable ASCII runs via `print_bytes`, fast-path `ESC [ … final` CSI
/// sequences, and decode multi-byte chars one at a time.
fn[P : Perform] Parser::advance_ground(
  self : Parser,
  p : P,
  bytes : ArrayView[Int],
  i : Int,
  valid_end : Int,
) -> Int {
  let run = bytes[i:]
  // `valid` is the prefix BEFORE the trailing partial; an escape sequence can
  // consume past `valid_end` (raw bytes), so a later ground re-entry clears
  // the stale partial.
  let valid = if i <= valid_end {
    valid_end - i
  } else {
    self.partial_need = 0
    run.length()
  }
  let mut pos = 0
  while pos < valid {
    // Find the leading printable-ASCII run (SIMD when enabled).
    let n = if self.simd {
      first_non_printable(run[pos:valid])
    } else {
      first_non_printable_scalar(run[pos:valid])
    }
    if n > 0 {
      p.print_bytes(run[pos:pos + n])
      pos = pos + n
    }
    if pos >= valid {
      break
    }
    let mut b = run[pos]
    // Bulk CSI fast path: `ESC [ params final` — scan for the final byte and
    // parse params (plus a leading private marker) in one pass. Anything else
    // bails to the state machine.
    if b == 0x1b && run.length() > pos + 1 && run[pos + 1] == 0x5b {
      let seq = run[pos + 2:valid]
      self.params = []
      self.params_len = 0
      self.param = 0
      self.param_empty = true
      self.sep = 0
      self.intermediates = []
      self.intermediates_len = 0
      let mut ok = true
      let mut f = 0
      while f < seq.length() {
        let sb = seq[f]
        if sb >= 0x30 && sb <= 0x39 {
          let v = self.param * 10 + (sb - 0x30)
          self.param = if v > MAX_PARAM_VALUE { MAX_PARAM_VALUE } else { v }
          self.param_empty = false
          f = f + 1
        } else if sb == 0x3a {
          self.push_param(if self.param_empty { -1 } else { self.param })
          if self.params_len < 16 {
            self.sep = self.sep | (1 << (self.params_len - 1))
          }
          self.param = 0
          self.param_empty = true
          f = f + 1
        } else if sb == 0x3b {
          self.push_param(self.param)
          self.param = 0
          self.param_empty = true
          f = f + 1
        } else if sb >= 0x3c && sb <= 0x3f {
          // Private marker (`> = < ?`) — only valid as a CSI prefix, before
          // any param or marker. After params the DEC state machine drops the
          // whole sequence, so bail to the cold path.
          if self.params_len != 0 || !self.param_empty || self.intermediates_len != 0 {
            ok = false
            break
          }
          self.push_intermediate(sb)
          f = f + 1
        } else if sb >= 0x40 && sb <= 0x7e {
          break
        } else {
          ok = false
          break
        }
      }
      if ok && f < seq.length() {
        // A param-less CSI (`CSI H`) dispatches `[]`; a trailing empty param
        // is pushed as `-1`.
        if !self.param_empty || self.params_len != 0 {
          self.push_param(if self.param_empty { -1 } else { self.param })
        }
        p.csi_dispatch(
          self.params[:self.params_len],
          self.sep,
          self.intermediates[:self.intermediates_len],
          seq[f],
        )
        self.clear_seq_state()
        // Keep scanning in this pass: CSI-dense input (SGR churn) pays a
        // re-entry + a fresh scan per sequence otherwise.
        pos = pos + 2 + f + 1
        continue
      }
    }
    match b {
      0x1b => {
        // ESC → enter the escape state (the byte is consumed).
        self.clear_seq_state()
        self.state = ParseState::Escape
        return i + pos + 1
      }
      0x00..=0x1f | 0x7f => {
        // C0 controls (and DEL) often cluster — `\r\n`, `\t\t`, etc. Execute
        // the whole run without re-scanning printable bytes between them.
        while true {
          p.execute(b)
          pos = pos + 1
          if pos >= valid {
            break
          }
          b = run[pos]
          if b == 0x1b || !(b == 0x7f || b < 0x20) {
            break
          }
        }
      }
      0x80..=0x9f => {
        // Raw 8-bit C1: introducers start their sequence; ST is a no-op;
        // other C1 controls execute.
        let (action, next) = c1_transition(b)
        self.apply(p, action, b)
        if next != ParseState::Ground {
          self.state = next
          return i + pos + 1
        }
        pos = pos + 1
      }
      _ => {
        // Multi-byte UTF-8 lead (>= 0xa0).
        pos = pos + decode_utf8(p, run, valid, pos)
      }
    }
  }
  // Consume the whole run (including any carried-over partial bytes).
  i + run.length()
}

///|
/// Decode one multi-byte UTF-8 code point starting at `bytes[pos]` (a lead
/// byte `>= 0xA0`), following W3C "Substitution of Maximal Subparts".
///
/// Returns the number of bytes consumed (at least 1).
fn[P : Perform] decode_utf8(
  p : P,
  bytes : ArrayView[Int],
  valid : Int,
  pos : Int,
) -> Int {
  let lead = bytes[pos]
  let (expected, lead_cp) = utf8_lead(lead)
  let mut cp = lead_cp
  if expected == 0 {
    // Lone continuation byte (`0xA0..=0xBF`) — invalid lead.
    p.print('\u{FFFD}')
    return 1
  }
  let mut have = 1
  let mut valid_cp = true
  let mut j = pos + 1
  while have < expected && j < valid {
    let b = bytes[j]
    if b >= 0x80 && b <= 0xbf {
      if have == 1 && !utf8_second_byte_valid(lead, b) {
        valid_cp = false
        break
      }
      cp = (cp << 6) | (b & 0x3f)
      have = have + 1
      j = j + 1
    } else {
      break
    }
  }
  if valid_cp && have == expected {
    dispatch_cp(p, cp)
    j - pos
  } else {
    // Truncated / ill-formed maximal subpart → one U+FFFD.
    p.print('\u{FFFD}')
    have
  }
}

///|
/// Escape-state byte dispatch: the sequence introducers, ESC finals,
/// intermediates and C0 controls are handled inline; only the rare bytes
/// fall through to the cold per-byte state machine.
fn[P : Perform] Parser::advance_escape_byte(
  self : Parser,
  p : P,
  bytes : ArrayView[Int],
  i : Int,
) -> Int {
  let b = bytes[i]
  if b == 0x5b {
    self.state = ParseState::CsiEntry
    return i + 1
  }
  if b == 0x5d {
    self.osc = []
    self.osc_overflow = false
    self.osc_starts = [0]
    self.osc_num_starts = 1
    self.osc_deferring = true
    self.osc_base = i + 1
    self.state = ParseState::OscString
    return i + 1
  }
  if b == 0x50 {
    self.state = ParseState::DcsEntry
    return i + 1
  }
  if b == 0x58 || b == 0x5e || b == 0x5f {
    self.state = ParseState::SosPmApcString
    return i + 1
  }
  if b >= 0x20 && b <= 0x2f {
    self.push_intermediate(b)
    self.state = ParseState::EscapeIntermediate
    return i + 1
  }
  // ESC final bytes (esc_dispatch), disjoint from the introducers above.
  if (b >= 0x30 && b <= 0x4f) || (b >= 0x51 && b <= 0x57) || b == 0x59 ||
    b == 0x5a || b == 0x5c || (b >= 0x60 && b <= 0x7e) {
    p.esc_dispatch(self.intermediates[:self.intermediates_len], b)
    self.clear_seq_state()
    self.state = ParseState::Ground
    return i + 1
  }
  // C0 controls that keep the escape state alive.
  if (b >= 0x00 && b <= 0x17) || b == 0x19 || (b >= 0x1c && b <= 0x1f) {
    p.execute(b)
    return i + 1
  }
  // CAN/SUB execute and return to ground.
  if b == 0x18 || b == 0x1a {
    p.execute(b)
    self.state = ParseState::Ground
    return i + 1
  }
  self.advance_non_ground(p, bytes, i)
}

///|
/// `DcsEntry` byte dispatch: the final byte (`0x40..=0x7e`) hooks inline;
/// digits/separators/intermediates fall through to the cold state machine.
fn[P : Perform] Parser::advance_dcs_entry_byte(
  self : Parser,
  p : P,
  bytes : ArrayView[Int],
  i : Int,
) -> Int {
  let b = bytes[i]
  if b >= 0x40 && b <= 0x7e {
    // A param-less DCS hooks with `[]`, not `[0]`.
    if !self.param_empty || self.params_len != 0 {
      self.push_param(self.param)
    }
    p.hook(
      self.params[:self.params_len],
      self.intermediates[:self.intermediates_len],
      b,
    )
    self.clear_seq_state()
    self.state = ParseState::DcsPassthrough
    return i + 1
  }
  self.advance_non_ground(p, bytes, i)
}

///|
/// OSC string bulk run: append the payload prefix in one pass. The copy is
/// deferred while the payload is still entirely within the input slice;
/// boundary bytes fall through.
fn[P : Perform] Parser::advance_osc_run(
  self : Parser,
  p : P,
  bytes : ArrayView[Int],
  i : Int,
) -> Int {
  let run = bytes[i:]
  let n = first_osc_boundary(run)
  if n > 0 {
    if !self.osc_deferring {
      self.osc_extend(run[:n])
    }
    return i + n
  }
  // Boundary byte: dispatch the common OSC terminator/separator bytes inline.
  let b = bytes[i]
  if b == 0x07 {
    self.osc_end(p, true, bytes, i)
    self.state = ParseState::Ground
    return i + 1
  }
  if b == 0x1b {
    self.clear_seq_state()
    self.osc_end(p, false, bytes, i)
    self.state = ParseState::Escape
    return i + 1
  }
  if b == 0x3b {
    // The offset is `;`-free: subtract the separators already seen so the
    // deferred (input) and accumulated (`osc`) modes agree.
    let offset = if self.osc_deferring {
      i - self.osc_base - (self.osc_num_starts - 1)
    } else {
      self.osc.length()
    }
    self.osc_param_boundary(offset)
    return i + 1
  }
  if self.osc_deferring {
    self.osc_flush(bytes, i)
  }
  self.advance_non_ground(p, bytes, i)
}

///|
/// DCS passthrough bulk run: dispatch the payload prefix via one `put_slice`,
/// stopping at CAN/SUB/ESC/DEL or any byte `>= 0x80`.
fn[P : Perform] Parser::advance_dcs_run(
  self : Parser,
  p : P,
  bytes : ArrayView[Int],
  i : Int,
) -> Int {
  let n = first_dcs_boundary(bytes[i:])
  if n > 0 {
    p.put_slice(bytes[i:i + n])
    return i + n
  }
  // Boundary byte: ESC terminates the DCS string inline.
  if bytes[i] == 0x1b {
    self.clear_seq_state()
    p.unhook()
    self.state = ParseState::Escape
    return i + 1
  }
  self.advance_non_ground(p, bytes, i)
}

///|
/// CSI/DCS param run: digits, `;` and `:` never dispatch, so consume the
/// whole run in a tight loop; the boundary byte falls through to the cold
/// state machine.
fn[P : Perform] Parser::advance_param_run(
  self : Parser,
  p : P,
  bytes : ArrayView[Int],
  i : Int,
) -> Int {
  let mut j = i
  while j < bytes.length() {
    let b = bytes[j]
    if b >= 0x30 && b <= 0x39 {
      let v = self.param * 10 + (b - 0x30)
      self.param = if v > MAX_PARAM_VALUE { MAX_PARAM_VALUE } else { v }
      self.param_empty = false
      j = j + 1
    } else if b == 0x3a {
      self.push_param(if self.param_empty { -1 } else { self.param })
      if self.params_len < 16 {
        self.sep = self.sep | (1 << (self.params_len - 1))
      }
      self.param = 0
      self.param_empty = true
      j = j + 1
    } else if b == 0x3b {
      self.push_param(self.param)
      self.param = 0
      self.param_empty = true
      j = j + 1
    } else {
      break
    }
  }
  if j > i {
    return j
  }
  self.advance_non_ground(p, bytes, i)
}

///|
/// Non-ground dispatch: the cold transition-table path plus param and
/// intermediate accumulation. Rare bytes, kept out of the hot loop.
fn[P : Perform] Parser::advance_non_ground(
  self : Parser,
  p : P,
  bytes : ArrayView[Int],
  i : Int,
) -> Int {
  let b = bytes[i]
  let state = self.state
  if b == 0x1b {
    // ESC aborts the current sequence and starts a new one fresh.
    self.clear_seq_state()
  }
  if b >= 0x80 && b <= 0x9f {
    // 8-bit C1: DEC's "anywhere" rule — abort the sequence, execute the
    // control, introducers re-enter their state (ST `0x9c` is a no-op).
    self.clear_seq_state()
    let (action, next) = c1_in_sequence(state, b)
    self.apply(p, action, b)
    self.state = next
    return i + 1
  }
  // CSI final-byte fast path: `0x40..=0x7e` from CsiEntry/CsiParam/
  // CsiIntermediate always dispatches (CSI_DISPATCH → Ground).
  if (state == ParseState::CsiEntry || state == ParseState::CsiParam ||
    state == ParseState::CsiIntermediate) &&
    b >= 0x40 && b <= 0x7e {
    if !self.param_empty || self.params_len != 0 {
      self.push_param(if self.param_empty { -1 } else { self.param })
    }
    p.csi_dispatch(
      self.params[:self.params_len],
      self.sep,
      self.intermediates[:self.intermediates_len],
      b,
    )
    self.clear_seq_state()
    self.state = ParseState::Ground
    return i + 1
  }
  // Parameter / intermediate accumulation for CSI, DCS and ESC states.
  match state {
    ParseState::CsiEntry
    | ParseState::CsiParam
    | ParseState::CsiIntermediate
    | ParseState::DcsEntry
    | ParseState::DcsParam
    | ParseState::DcsIntermediate =>
      if b >= 0x20 && b <= 0x2f {
        self.push_intermediate(b)
      } else if b >= 0x30 && b <= 0x39 {
        let v = self.param * 10 + (b - 0x30)
        self.param = if v > MAX_PARAM_VALUE { MAX_PARAM_VALUE } else { v }
        self.param_empty = false
      } else if b == 0x3a {
        self.push_param(if self.param_empty { -1 } else { self.param })
        if self.params_len < 16 {
          self.sep = self.sep | (1 << (self.params_len - 1))
        }
        self.param = 0
        self.param_empty = true
      } else if b == 0x3b {
        self.push_param(self.param)
        self.param = 0
        self.param_empty = true
      } else if b >= 0x3c && b <= 0x3f {
        self.push_intermediate(b)
      }
    ParseState::Escape | ParseState::EscapeIntermediate =>
      if b >= 0x20 && b <= 0x2f {
        self.push_intermediate(b)
      }
    _ => ()
  }
  let (action, next) = transition(state, b)
  self.apply(p, action, b)
  self.state = next
  i + 1
}

///|
/// Apply a transition's actions to the sink, in DEC order (string
/// terminations before the execute).
fn[P : Perform] Parser::apply(
  self : Parser,
  p : P,
  action : Int,
  byte : Int,
) -> Unit {
  if action == ACTION_NONE {
    return
  }
  if action_has(action, ACTION_PRINT) {
    p.print(cp_to_char(byte))
  }
  if action_has(action, ACTION_CSI_DISPATCH) {
    // A param-less CSI dispatches `[]`; a trailing empty is the `-1`
    // sentinel.
    if !self.param_empty || self.params_len != 0 {
      self.push_param(if self.param_empty { -1 } else { self.param })
    }
    p.csi_dispatch(
      self.params[:self.params_len],
      self.sep,
      self.intermediates[:self.intermediates_len],
      byte,
    )
    self.clear_seq_state()
  }
  if action_has(action, ACTION_ESC_DISPATCH) {
    p.esc_dispatch(self.intermediates[:self.intermediates_len], byte)
    self.clear_seq_state()
  }
  if action_has(action, ACTION_HOOK) {
    if !self.param_empty || self.params_len != 0 {
      self.push_param(self.param)
    }
    p.hook(
      self.params[:self.params_len],
      self.intermediates[:self.intermediates_len],
      byte,
    )
    self.clear_seq_state()
  }
  if action_has(action, ACTION_PUT) {
    p.put(byte)
  }
  if action_has(action, ACTION_UNHOOK) {
    p.unhook()
  }
  if action_has(action, ACTION_OSC_START) {
    self.osc = []
    self.osc_overflow = false
    self.osc_starts = [0]
    self.osc_num_starts = 1
    self.osc_deferring = false
  }
  if action_has(action, ACTION_OSC_PUT) {
    self.osc_push(byte)
  }
  if action_has(action, ACTION_OSC_END) {
    // Cold terminator (C1 ST / CAN / SUB): the deferred payload was already
    // flushed by `advance_osc_run`, so dispatch from `osc`.
    self.osc_end(p, byte == 0x07, self.osc[:0], 0)
  }
  // EXECUTE last: a C0 control that also terminates a string (CAN/SUB in
  // OSC/DCS passthrough) dispatches the string first, then executes.
  if action_has(action, ACTION_EXECUTE) {
    p.execute(byte)
  }
}

///|
/// Reset CSI/DCS/ESC accumulation state.
fn Parser::clear_seq_state(self : Parser) -> Unit {
  self.params = []
  self.params_len = 0
  self.sep = 0
  self.param = 0
  self.param_empty = true
  self.intermediates = []
  self.intermediates_len = 0
}

///|
/// Push an intermediate byte (private marker or `0x20..=0x2f`), capping at
/// two; extras are dropped.
fn Parser::push_intermediate(self : Parser, b : Int) -> Unit {
  if self.intermediates_len < MAX_INTERMEDIATES {
    self.intermediates.push(b)
    self.intermediates_len = self.intermediates_len + 1
  }
}

///|
/// Push a CSI/DCS parameter, capping at `MAX_PARAMS` (params past the cap are
/// dropped).
fn Parser::push_param(self : Parser, value : Int) -> Unit {
  if self.params_len < MAX_PARAMS {
    self.params.push(value)
    self.params_len = self.params_len + 1
  }
}

///|
/// Record the start of the next OSC param. `;` separators are not buffered
/// into `osc`, so consecutive ranges merge at their boundary. Params past the
/// 16th are dropped.
fn Parser::osc_param_boundary(self : Parser, offset : Int) -> Unit {
  if self.osc_num_starts > MAX_OSC_PARAMS {
    return
  }
  self.osc_starts.push(offset)
  self.osc_num_starts = self.osc_num_starts + 1
}

///|
/// Append an OSC payload run, capping at `MAX_OSC_PAYLOAD` and flagging
/// overflow when the run is truncated (or was already overflowed).
fn Parser::osc_extend(self : Parser, run : ArrayView[Int]) -> Unit {
  if self.osc_overflow {
    return
  }
  let room = MAX_OSC_PAYLOAD - self.osc.length()
  let take = if run.length() < room { run.length() } else { room }
  let mut k = 0
  while k < take {
    self.osc.push(run[k])
    k = k + 1
  }
  self.osc_overflow = take < run.length()
}

///|
/// Append one OSC payload byte, discarding (marking overflow) at the cap.
fn Parser::osc_push(self : Parser, b : Int) -> Unit {
  if self.osc_overflow {
    return
  }
  if self.osc.length() < MAX_OSC_PAYLOAD {
    self.osc.push(b)
  } else {
    self.osc_overflow = true
  }
}

///|
/// Dispatch a collected OSC command and reset the OSC state. An oversized
/// payload is discarded wholesale. With `bytes`/`end_pos` the params are
/// sliced straight from the input when deferred; otherwise from `osc`.
fn[P : Perform] Parser::osc_end(
  self : Parser,
  p : P,
  bell : Bool,
  bytes : ArrayView[Int],
  end_pos : Int,
) -> Unit {
  let deferring = self.osc_deferring
  let n = self.osc_num_starts
  // The cap applies to the `;`-free payload bytes; in deferred mode the input
  // still holds the `n - 1` `;` separators, so subtract them.
  let payload_len = if deferring {
    end_pos - self.osc_base - (n - 1)
  } else {
    self.osc.length()
  }
  if !self.osc_overflow && payload_len <= MAX_OSC_PAYLOAD {
    let m = if n < MAX_OSC_PARAMS { n } else { MAX_OSC_PARAMS }
    // Unify the deferred (input-sliced) and accumulated (`osc`-sliced) cases:
    // the input holds the `;` separators, so each `;`-free boundary offset
    // shifts by `k`.
    let base = if deferring { self.osc_base } else { 0 }
    let shift = if deferring { 1 } else { 0 }
    let last_end = if deferring { end_pos } else { self.osc.length() }
    let params : Array[Array[Int]] = []
    for k = 0; k < m; k = k + 1 {
      let start = base + self.osc_starts[k] + k * shift
      let end = if k + 1 < n {
        base + self.osc_starts[k + 1] + k * shift
      } else {
        last_end
      }
      if deferring {
        params.push(bytes[start:end].to_owned())
      } else {
        params.push(self.osc[start:end].to_owned())
      }
    }
    p.osc_dispatch(params, bell)
  }
  self.osc_reset()
}

///|
/// Reset the OSC accumulation/dispatch state.
fn Parser::osc_reset(self : Parser) -> Unit {
  self.osc = []
  self.osc_overflow = false
  self.osc_num_starts = 0
  self.osc_deferring = false
}

///|
/// Flush a deferred OSC payload into `osc` (the string spans `advance` calls
/// or hits a cold terminator). The recorded `osc_starts` offsets stay valid —
/// they become `osc`-relative instead of input-relative.
fn Parser::osc_flush(self : Parser, bytes : ArrayView[Int], end_pos : Int) -> Unit {
  // Bulk-copy the `;`-free segments instead of pushing byte-by-byte.
  let mut start = self.osc_base
  let mut j = self.osc_base
  while j < end_pos {
    if bytes[j] == 0x3b {
      self.osc_extend(bytes[start:j])
      start = j + 1
    }
    j = j + 1
  }
  self.osc_extend(bytes[start:end_pos])
  self.osc_deferring = false
}

///|
/// Emit a decoded code point; the C0/C1 ranges keep `execute` semantics.
fn[P : Perform] dispatch_cp(p : P, cp : Int) -> Unit {
  if cp <= 0x1f || cp == 0x7f || (cp >= 0x80 && cp <= 0x9f) {
    p.execute(cp)
  } else {
    p.print(cp_to_char(cp))
  }
}

///|
/// Index of the first byte that ends an OSC payload run: a C0 byte
/// (`< 0x20`, including BEL/ESC), a raw C1 byte (`0x80..=0x9f`), or the `;`
/// param separator (`0x3b`). The rest are `OSC_PUT` bytes.
pub fn first_osc_boundary(bytes : ArrayView[Int]) -> Int {
  let n = bytes.length()
  let mut i = 0
  while i < n {
    let b = bytes[i]
    if b < 0x20 || (b >= 0x80 && b <= 0x9f) || b == 0x3b {
      return i
    }
    i = i + 1
  }
  n
}

///|
/// Index of the first DCS payload boundary byte (CAN/SUB/ESC/DEL or any byte
/// `>= 0x80`), or the remaining length if every byte is a PUT byte.
pub fn first_dcs_boundary(bytes : ArrayView[Int]) -> Int {
  let n = bytes.length()
  let mut i = 0
  while i < n {
    let b = bytes[i]
    if b >= 0x80 || b == 0x18 || b == 0x1a || b == 0x1b || b == 0x7f {
      return i
    }
    i = i + 1
  }
  n
}

///|
/// Scalar index of the first non-printable byte (`< 0x20` or `>= 0x7f`), or
/// the remaining length if every byte is printable ASCII.
fn first_non_printable_scalar(bytes : ArrayView[Int]) -> Int {
  let n = bytes.length()
  let mut i = 0
  while i < n {
    let b = bytes[i]
    if !(b >= 0x20 && b <= 0x7e) {
      return i
    }
    i = i + 1
  }
  n
}
