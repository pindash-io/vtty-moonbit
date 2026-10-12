// The callback interface the byte parser dispatches to.

///| Sink for the byte parser's decoded output. Every method has a no-op

///|
/// default, so a terminal screen only overrides the events it cares about.
pub(open) trait Perform {
  /// A single printable non-ASCII code point (UTF-8 decoded).
  fn print(Self, Char) -> Unit = _
  /// A contiguous run of printable ASCII (0x20..=0x7e) — the bulk hot path.
  fn print_bytes(Self, ArrayView[Int]) -> Unit = _
  /// A contiguous run of pre-decoded printable code points (never C0/C1).
  fn print_codepoints(Self, ArrayView[Int]) -> Unit = _
  /// A C0/C1 control byte (e.g. `\n`, `\t`, `0x1b`).
  fn execute(Self, Int) -> Unit = _
  /// A CSI sequence's final byte, with collected parameters and intermediates.
  /// An empty colon parameter is the `-1` sentinel; `sep` bit `i` marks param
  /// `i` as colon-separated.
  fn csi_dispatch(Self, ArrayView[Int], Int, ArrayView[Int], Int) -> Unit = _
  /// An escape sequence's final byte.
  fn esc_dispatch(Self, ArrayView[Int], Int) -> Unit = _
  /// A device-control string header arrived.
  fn hook(Self, ArrayView[Int], ArrayView[Int], Int) -> Unit = _
  /// A device-control string payload byte arrived.
  fn put(Self, Int) -> Unit = _
  /// A contiguous device-control string payload run.
  fn put_slice(Self, ArrayView[Int]) -> Unit = _
  /// The device-control string ended.
  fn unhook(Self) -> Unit = _
  /// An operating-system command ended (params split on `;`).
  fn osc_dispatch(Self, Array[Array[Int]], Bool) -> Unit = _
}

///|
/// Default no-op implementations.
impl Perform with fn print(_self, _c) {

}

///|
impl Perform with fn print_bytes(_self, _s) {

}

///|
impl Perform with fn print_codepoints(self, codepoints) {
  for cp in codepoints {
    self.print(cp_to_char(cp))
  }
}

///|
impl Perform with fn execute(_self, _b) {

}

///|
impl Perform with fn csi_dispatch(
  _self,
  _params,
  _sep,
  _intermediates,
  _final_byte,
) {

}

///|
impl Perform with fn esc_dispatch(_self, _intermediates, _byte) {

}

///|
impl Perform with fn hook(_self, _params, _intermediates, _final_byte) {

}

///|
impl Perform with fn put(_self, _byte) {

}

///|
impl Perform with fn put_slice(self, bytes) {
  for byte in bytes {
    self.put(byte)
  }
}

///|
impl Perform with fn unhook(_self) {

}

///|
impl Perform with fn osc_dispatch(_self, _params, _bell_terminated) {

}

///| Convert a code point to a `Char`, replacing invalid/surrogate values with

///|
/// U+FFFD.
pub fn cp_to_char(cp : Int) -> Char {
  Int::to_char(cp).unwrap_or('\u{FFFD}')
}
