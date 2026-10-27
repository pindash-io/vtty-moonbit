// The owned event API: `Event` + `Recording`.

///|
/// A parsed escape-sequence event — the dispatch as data, instead of a
/// `Perform` callback. For differential testing and simple consumers.
pub(all) enum Event {
  Print(Char)
  Execute(Int)
  CsiDispatch(Array[Int], Array[Int], Int)
  EscDispatch(Array[Int], Int)
  DcsHook(Array[Int], Array[Int], Int)
  DcsPut(Int)
  DcsUnhook
  OscDispatch(Array[Array[Int]], Bool)
} derive(Eq, Debug)

///|
pub extend Event with Eq::{equal, not_equal}

///|
pub extend Event with @debug.Debug::{to_repr}

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
pub impl Perform for Recording with fn print(self, c : Char) {
  self.events.push(Event::Print(c))
}

///|
pub impl Perform for Recording with fn print_bytes(self, s : ArrayView[Int]) {
  for b in s {
    self.events.push(Event::Print(cp_to_char(b)))
  }
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
  self.events.push(Event::Execute(byte))
}

///|
pub impl Perform for Recording with fn csi_dispatch(
  self,
  params : ArrayView[Int],
  _sep : Int,
  intermediates : ArrayView[Int],
  final_byte : Int,
) {
  self.events.push(
    Event::CsiDispatch(params.to_owned(), intermediates.to_owned(), final_byte),
  )
}

///|
pub impl Perform for Recording with fn esc_dispatch(
  self,
  intermediates : ArrayView[Int],
  byte : Int,
) {
  self.events.push(Event::EscDispatch(intermediates.to_owned(), byte))
}

///|
pub impl Perform for Recording with fn hook(
  self,
  params : ArrayView[Int],
  intermediates : ArrayView[Int],
  final_byte : Int,
) {
  self.events.push(
    Event::DcsHook(params.to_owned(), intermediates.to_owned(), final_byte),
  )
}

///|
pub impl Perform for Recording with fn put(self, byte : Int) {
  self.events.push(Event::DcsPut(byte))
}

///|
pub impl Perform for Recording with fn put_slice(self, bytes : ArrayView[Int]) {
  for b in bytes {
    self.events.push(Event::DcsPut(b))
  }
}

///|
pub impl Perform for Recording with fn unhook(self) {
  self.events.push(Event::DcsUnhook)
}

///|
pub impl Perform for Recording with fn osc_dispatch(
  self,
  params : Array[Array[Int]],
  bell_terminated : Bool,
) {
  self.events.push(Event::OscDispatch(params, bell_terminated))
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
  put,
  put_slice,
  unhook,
}
