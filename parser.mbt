// The DEC VT500 byte parser.

// Cap on CSI/DCS parameters (vte/rio-vt = 32).
const MAX_PARAMS : Int = 32

// Cap on CSI/DCS intermediates before a sequence is ignored.
const MAX_INTERMEDIATES : Int = 2

// Cap on OSC parameters (`;`-separated).
const MAX_OSC_PARAMS : Int = 16

///|
/// A byte-input DEC VT500 terminal parser.
///
/// Dispatch decoded events to a `Perform` sink via `advance`, or collect
/// owned events via `parse_events` / `Recording`.
pub struct Parser {
  mut state : ParseState
  mut params : Array[Int]
  mut params_len : Int
  mut param : Int
  mut param_empty : Bool
  mut sep : Int
  mut intermediates : Array[Int]
  mut intermediates_len : Int
  mut ignore : Bool
  mut partial : Int
  mut partial_need : Int
  mut osc : Array[Int]
  mut osc_starts : Array[Int]
  mut simd : Bool
}

///|
/// Create a parser in the ground state (scalar decode).
pub fn Parser::new() -> Parser {
  {
    state: ParseState::Ground,
    params: [],
    params_len: 0,
    param: 0,
    param_empty: true,
    sep: 0,
    intermediates: [],
    intermediates_len: 0,
    ignore: false,
    partial: 0,
    partial_need: 0,
    osc: [],
    osc_starts: [],
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
  // call.
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
        // Not a continuation byte — abort the partial.
        self.partial_need = 0
        p.print('\u{FFFD}')
        break
      }
    }
    if completed {
      dispatch_cp(p, self.partial)
      self.partial = 0
    }
  }
  while i < bytes.length() {
    match self.state {
      ParseState::Ground => i = self.advance_ground(p, bytes, i)
      ParseState::DcsPassthrough => i = self.advance_dcs_run(p, bytes, i)
      _ => i = self.advance_non_ground(p, bytes, i)
    }
  }
}

///|
/// Ground-state dispatch: printable runs, C0/C1 controls, ESC, and UTF-8.
fn[P : Perform] Parser::advance_ground(
  self : Parser,
  p : P,
  bytes : ArrayView[Int],
  i : Int,
) -> Int {
  let b = bytes[i]
  if b >= 0x20 && b <= 0x7e {
    if self.simd {
      let n = first_non_printable(bytes[i:])
      p.print_bytes(bytes[i:i + n])
      return i + n
    }
    let mut j = i
    while j < bytes.length() && bytes[j] >= 0x20 && bytes[j] < 0x7f {
      j = j + 1
    }
    p.print_bytes(bytes[i:j])
    j
  } else if b == 0x1b {
    self.clear_seq_state()
    self.state = ParseState::Escape
    i + 1
  } else if b == 0x7f {
    // DEL is a C0 control (destructive backspace), not printable.
    p.execute(0x7f)
    i + 1
  } else if b < 0x20 {
    p.execute(b)
    i + 1
  } else if b <= 0x9f {
    // Raw 8-bit C1 control byte.
    let (action, next) = c1_transition(b)
    self.apply(p, action, b)
    self.state = next
    i + 1
  } else {
    // Multi-byte UTF-8 (lead byte >= 0xA0).
    self.decode_utf8(p, bytes, i)
  }
}

///|
/// Decode one multi-byte UTF-8 code point starting at `bytes[i]` (a lead
/// byte `>= 0xA0`), following W3C "Substitution of Maximal Subparts".
///
/// Returns the number of bytes consumed.
fn[P : Perform] Parser::decode_utf8(
  self : Parser,
  p : P,
  bytes : ArrayView[Int],
  i : Int,
) -> Int {
  let lead = bytes[i]
  let expected = utf8_expected(lead)
  if expected == 0 {
    // Invalid lead (lone continuation 0xA0..=0xBF, C0/C1, or F5..=FF).
    p.print('\u{FFFD}')
    i + 1
  } else {
    let mut have = 1
    let mut cp = utf8_lead_cp(lead)
    let mut j = i + 1
    let mut valid = true
    while have < expected && j < bytes.length() {
      let b = bytes[j]
      if b >= 0x80 && b <= 0xbf {
        if have == 1 && !utf8_second_byte_valid(lead, b) {
          valid = false
          break
        }
        cp = (cp << 6) | (b & 0x3f)
        have = have + 1
        j = j + 1
      } else {
        break
      }
    }
    if valid && have == expected {
      dispatch_cp(p, cp)
      j
    } else if valid && j >= bytes.length() {
      // Trailing partial: carry it to the next `advance` call.
      self.partial = cp
      self.partial_need = expected - have
      j
    } else {
      // Truncated / ill-formed maximal subpart → one U+FFFD.
      p.print('\u{FFFD}')
      i + have
    }
  }
}

///|
/// Non-ground dispatch: the cold transition-table path plus param and
/// intermediate accumulation.
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
    // 8-bit C1: DEC's "anywhere" rule.
    self.clear_seq_state()
    let (action, next) = c1_in_sequence(state, b)
    self.apply(p, action, b)
    self.state = next
    return i + 1
  }
  // Parameter / intermediate accumulation.
  match state {
    ParseState::CsiEntry
    | ParseState::CsiParam
    | ParseState::CsiIntermediate
    | ParseState::DcsEntry
    | ParseState::DcsParam
    | ParseState::DcsIntermediate =>
      match b {
        0x30..=0x39 => {
          let v = self.param * 10 + (b - 0x30)
          self.param = if v > 65535 { 65535 } else { v }
          self.param_empty = false
        }
        0x3b => {
          self.push_param(self.param)
          self.param = 0
          self.param_empty = true
        }
        0x3a => {
          self.push_param(if self.param_empty { -1 } else { self.param })
          if self.params_len > 0 && self.params_len <= 16 {
            self.sep = self.sep | (1 << (self.params_len - 1))
          }
          self.param = 0
          self.param_empty = true
        }
        0x3c..=0x3f | 0x20..=0x2f => self.push_intermediate(b)
        _ => ()
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
    self.osc_reset()
  }
  if action_has(action, ACTION_OSC_PUT) {
    self.osc_push(byte)
  }
  if action_has(action, ACTION_OSC_END) {
    self.osc_end(p, byte == 0x07)
  }
  // EXECUTE last: a string terminator (CAN/SUB) also executes.
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
  self.ignore = false
}

///|
/// Push an intermediate byte (private marker or `0x20..=0x2f`), capping at
/// two.
fn Parser::push_intermediate(self : Parser, b : Int) -> Unit {
  if self.intermediates_len < MAX_INTERMEDIATES {
    self.intermediates.push(b)
    self.intermediates_len = self.intermediates_len + 1
  } else {
    self.ignore = true
  }
}

///|
/// Push a CSI/DCS parameter, capping at `MAX_PARAMS`.
fn Parser::push_param(self : Parser, value : Int) -> Unit {
  if self.params_len < MAX_PARAMS {
    self.params.push(value)
    self.params_len = self.params_len + 1
  }
}

///|
/// Reset the OSC accumulation state.
fn Parser::osc_reset(self : Parser) -> Unit {
  self.osc = []
  self.osc_starts = []
}

///|
/// Append an OSC payload byte, tracking `;` param boundaries (the separator
/// itself is not buffered).
fn Parser::osc_push(self : Parser, b : Int) -> Unit {
  if b == 0x3b {
    if self.osc_starts.length() < MAX_OSC_PARAMS {
      self.osc_starts.push(self.osc.length())
    }
  } else {
    self.osc.push(b)
  }
}

///|
/// Dispatch the accumulated OSC params and reset.
fn[P : Perform] Parser::osc_end(self : Parser, p : P, bell : Bool) -> Unit {
  let n = self.osc_starts.length() + 1
  let params : Array[Array[Int]] = []
  for k = 0; k < n; k = k + 1 {
    let start = if k == 0 { 0 } else { self.osc_starts[k - 1] }
    let end = if k < self.osc_starts.length() {
      self.osc_starts[k]
    } else {
      self.osc.length()
    }
    params.push(self.osc[start:end].to_owned())
  }
  p.osc_dispatch(params, bell)
  self.osc_reset()
}

///|
/// Emit a decoded code point; the C1 range keeps `execute` semantics.
fn[P : Perform] dispatch_cp(p : P, cp : Int) -> Unit {
  if cp >= 0x80 && cp <= 0x9f {
    p.execute(cp)
  } else {
    p.print(cp_to_char(cp))
  }
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
