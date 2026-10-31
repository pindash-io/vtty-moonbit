// The owned event API: `Event` + `Recording`.

///|
/// A parsed escape-sequence event — the dispatch as data, instead of a
/// `Perform` callback. For differential testing and simple consumers.
pub(all) enum Event {
  /// A single printable code point (UTF-8 decoded).
  Print(Char)
  /// A contiguous run of printable ASCII (`0x20..=0x7e`) — the bulk hot
  /// path, preserved as one event (not per-byte `Print`).
  PrintBytes(Array[Int])
  /// A C0/C1 control byte.
  Execute(Int)
  /// A CSI sequence: `ESC [ <params> <intermediates> <final>`.
  /// Fields are `(params, sep, intermediates, final_byte)`.
  CsiDispatch(Array[Int], Int, Array[Int], Int)
  /// An escape sequence: `ESC <intermediates> <byte>`.
  EscDispatch(Array[Int], Int)
  /// A DCS header: `ESC P <params> <intermediates> <final>`.
  DcsHook(Array[Int], Array[Int], Int)
  /// A DCS payload byte.
  DcsPut(Int)
  /// The DCS string ended.
  DcsUnhook
  /// An OSC command ended: `ESC ] <params split on ';'> (BEL | ST)`.
  OscDispatch(Array[Array[Int]], Bool)
} derive(Eq, Debug)

///|
pub extend Event with Eq::{equal, not_equal}

///|
pub extend Event with @debug.Debug::{to_repr}

///|
/// Append the canonical escape-sequence bytes to `out` — the textual inverse
/// of the parser, so re-parsing the appended bytes reproduces the event
/// (modulo the `-1` empty-param sentinel).
pub fn Event::write_bytes(self : Event, out : Array[Int]) -> Unit {
  match self {
    Event::Print(c) => append_utf8(out, c.to_string())
    Event::PrintBytes(s) =>
      for b in s {
        out.push(b)
      }
    Event::Execute(b) => out.push(b)
    Event::CsiDispatch(params, sep, intermediates, final_byte) => {
      append_utf8(out, "\u{1b}[")
      let (prefix, suffix) = split_intermediates(intermediates)
      for b in prefix {
        out.push(b)
      }
      append_params(out, params[:], sep)
      for b in suffix {
        out.push(b)
      }
      out.push(final_byte)
    }
    Event::EscDispatch(intermediates, byte) => {
      out.push(0x1b)
      for b in intermediates {
        out.push(b)
      }
      out.push(byte)
    }
    Event::DcsHook(params, intermediates, final_byte) => {
      append_utf8(out, "\u{1b}P")
      let (prefix, suffix) = split_intermediates(intermediates)
      for b in prefix {
        out.push(b)
      }
      append_params(out, params[:], 0)
      for b in suffix {
        out.push(b)
      }
      out.push(final_byte)
    }
    Event::DcsPut(b) => out.push(b)
    Event::DcsUnhook => append_utf8(out, "\u{1b}\\")
    Event::OscDispatch(params, bell_terminated) => {
      append_utf8(out, "\u{1b}]")
      for i = 0; i < params.length(); i = i + 1 {
        if i > 0 {
          out.push(0x3b)
        }
        for b in params[i] {
          out.push(b)
        }
      }
      if bell_terminated {
        out.push(0x07)
      } else {
        append_utf8(out, "\u{1b}\\")
      }
    }
  }
}

///|
/// Split CSI/DCS intermediates into the prefix markers (`? > = <`, emitted
/// before the params) and the suffix bytes (`0x20..=0x2f`, emitted after).
fn split_intermediates(ints : Array[Int]) -> (Array[Int], Array[Int]) {
  let prefix : Array[Int] = []
  let suffix : Array[Int] = []
  for b in ints {
    if b == 0x3f || b == 0x3e || b == 0x3d || b == 0x3c {
      prefix.push(b)
    } else {
      suffix.push(b)
    }
  }
  (prefix, suffix)
}

///|
/// Append numeric params, `;`- or `:`-joined (`sep` bit `i` = param `i`
/// followed by a colon).
fn append_params(out : Array[Int], params : ArrayView[Int], sep : Int) -> Unit {
  for i = 0; i < params.length(); i = i + 1 {
    if i > 0 {
      let colon = i - 1 < 16 && (sep & (1 << (i - 1))) != 0
      out.push(if colon { 0x3a } else { 0x3b })
    }
    append_decimal(out, params[i])
  }
}

///|
/// Append the decimal digits of `n` to `out`.
fn append_decimal(out : Array[Int], n : Int) -> Unit {
  if n == 0 {
    out.push(0x30)
    return
  }
  if n < 0 {
    out.push(0x2d)
    append_decimal(out, -n)
    return
  }
  let digits : Array[Int] = []
  let mut m = n
  while m > 0 {
    digits.push(0x30 + m % 10)
    m = m / 10
  }
  let mut k = digits.length() - 1
  while k >= 0 {
    out.push(digits[k])
    k = k - 1
  }
}

///|
/// Append a `String`'s UTF-8 bytes to `out`.
fn append_utf8(out : Array[Int], s : String) -> Unit {
  for b in @utf8.encode(s).iter() {
    out.push(b.to_int())
  }
}

///|
/// Records parser events into an `Array[Event]`.
///
/// Allocates one `Event` per dispatch — for tests and tooling.
pub struct Recording {
  events : Array[Event]
}

///|
/// Create an empty recording.
pub fn Recording::new() -> Recording {
  { events: [], }
}

///|
/// The recorded events, in dispatch order.
pub fn Recording::events(self : Recording) -> Array[Event] {
  self.events
}

///|
/// Append one event.
pub fn Recording::push(self : Recording, event : Event) -> Unit {
  self.events.push(event)
}

///|
/// Whether no events were recorded.
pub fn Recording::is_empty(self : Recording) -> Bool {
  self.events.length() == 0
}

///|
/// The number of recorded events.
pub fn Recording::len(self : Recording) -> Int {
  self.events.length()
}

///|
/// Record a single printable code point.
pub fn Recording::print_char(self : Recording, c : Char) -> Unit {
  self.events.push(Event::Print(c))
}

///|
/// Record a printable ASCII run (the `print_bytes` bulk hot path).
pub fn Recording::print_ascii(self : Recording, s : ArrayView[Int]) -> Unit {
  self.events.push(Event::PrintBytes(s.to_owned()))
}

///|
/// Record a C0 control byte.
pub fn Recording::control(self : Recording, byte : Int) -> Unit {
  self.events.push(Event::Execute(byte))
}

///|
/// Record a raw CSI sequence.
pub fn Recording::csi(
  self : Recording,
  params : ArrayView[Int],
  sep : Int,
  intermediates : ArrayView[Int],
  final_byte : Int,
) -> Unit {
  self.events.push(
    Event::CsiDispatch(params.to_owned(), sep, intermediates.to_owned(), final_byte),
  )
}

///|
/// Record a raw ESC sequence.
pub fn Recording::esc(
  self : Recording,
  intermediates : ArrayView[Int],
  byte : Int,
) -> Unit {
  self.events.push(Event::EscDispatch(intermediates.to_owned(), byte))
}

///|
/// Record a DCS header.
pub fn Recording::dcs_hook(
  self : Recording,
  params : ArrayView[Int],
  intermediates : ArrayView[Int],
  final_byte : Int,
) -> Unit {
  self.events.push(
    Event::DcsHook(params.to_owned(), intermediates.to_owned(), final_byte),
  )
}

///|
/// Record a DCS payload byte.
pub fn Recording::dcs_put(self : Recording, byte : Int) -> Unit {
  self.events.push(Event::DcsPut(byte))
}

///|
/// Record the end of a DCS string.
pub fn Recording::dcs_unhook(self : Recording) -> Unit {
  self.events.push(Event::DcsUnhook)
}

///|
/// Record a raw OSC command.
pub fn Recording::osc(
  self : Recording,
  params : Array[Array[Int]],
  bell_terminated : Bool,
) -> Unit {
  self.events.push(Event::OscDispatch(params, bell_terminated))
}

///|
/// Replay every recorded event onto `target` in order, leaving the log intact
/// so the same recording can be replayed onto multiple sinks.
pub fn[P : Perform] Recording::replay(self : Recording, target : P) -> Unit {
  for event in self.events {
    match event {
      Event::Print(c) => target.print(c)
      Event::PrintBytes(s) => target.print_bytes(s[:])
      Event::Execute(b) => target.execute(b)
      Event::CsiDispatch(params, sep, intermediates, final_byte) =>
        target.csi_dispatch(params[:], sep, intermediates[:], final_byte)
      Event::EscDispatch(intermediates, byte) =>
        target.esc_dispatch(intermediates[:], byte)
      Event::DcsHook(params, intermediates, final_byte) =>
        target.hook(params[:], intermediates[:], final_byte)
      Event::DcsPut(b) => target.put(b)
      Event::DcsUnhook => target.unhook()
      Event::OscDispatch(params, bell_terminated) =>
        target.osc_dispatch(params, bell_terminated)
    }
  }
}

///|
pub impl Perform for Recording with fn print(self, c : Char) {
  self.print_char(c)
}

///|
pub impl Perform for Recording with fn print_bytes(self, s : ArrayView[Int]) {
  self.print_ascii(s)
}

///|
pub impl Perform for Recording with fn print_codepoints(
  self,
  codepoints : ArrayView[Int],
) {
  for cp in codepoints {
    self.events.push(Event::Print(cp_to_char(cp)))
  }
}

///|
pub impl Perform for Recording with fn execute(self, byte : Int) {
  self.control(byte)
}

///|
pub impl Perform for Recording with fn csi_dispatch(
  self,
  params : ArrayView[Int],
  sep : Int,
  intermediates : ArrayView[Int],
  final_byte : Int,
) {
  self.csi(params, sep, intermediates, final_byte)
}

///|
pub impl Perform for Recording with fn esc_dispatch(
  self,
  intermediates : ArrayView[Int],
  byte : Int,
) {
  self.esc(intermediates, byte)
}

///|
pub impl Perform for Recording with fn hook(
  self,
  params : ArrayView[Int],
  intermediates : ArrayView[Int],
  final_byte : Int,
) {
  self.dcs_hook(params, intermediates, final_byte)
}

///|
pub impl Perform for Recording with fn put(self, byte : Int) {
  self.dcs_put(byte)
}

///|
pub impl Perform for Recording with fn put_slice(self, bytes : ArrayView[Int]) {
  for b in bytes {
    self.events.push(Event::DcsPut(b))
  }
}

///|
pub impl Perform for Recording with fn unhook(self) {
  self.dcs_unhook()
}

///|
pub impl Perform for Recording with fn osc_dispatch(
  self,
  params : Array[Array[Int]],
  bell_terminated : Bool,
) {
  self.osc(params, bell_terminated)
}

///|
pub extend Recording with Perform::{
  csi_dispatch,
  esc_dispatch,
  execute,
  hook,
  osc_dispatch,
  print,
  print_bytes,
  print_codepoints,
  print_crlf_line,
  print_line,
  put,
  put_slice,
  unhook,
}
