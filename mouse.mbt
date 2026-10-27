// Mouse event encoding (X10 / SGR).
//
// Reference: <https://vt100.net/emu/dec_ansi_parser>.

///|
/// Any tracking enabled: DEC 9 (X10), 1000 (press), 1002 (drag), or 1003
/// (any-motion).
pub const MOUSE_ENABLED : Int = 1 << 0

///|
/// DEC 9 — X10 press-only mode: report button presses, but not releases.
pub const MOUSE_X10 : Int = 1 << 1

///|
/// DEC 1006 — SGR protocol (`CSI < b ; x ; y M/m`).
pub const MOUSE_SGR : Int = 1 << 2

///|
/// DEC 1003 — any-motion tracking.
pub const MOUSE_ANY_MOTION : Int = 1 << 3

///|
/// DEC 1016 — SGR-pixel protocol (1-based pixel coordinates).
pub const MOUSE_PIXEL : Int = 1 << 4

///|
/// DEC 1005 — UTF-8 mouse protocol (X10 with UTF-8 coordinates).
pub const MOUSE_UTF8 : Int = 1 << 5

///|
/// All tracking disabled.
pub const MOUSE_DEFAULT : Int = 0

///|
/// Test whether `tracking` contains `flag`.
pub fn mouse_tracking_has(tracking : Int, flag : Int) -> Bool {
  (tracking & flag) != 0
}

///|
/// Mouse button/event codes for X10 and SGR encoding.
pub(all) enum MouseButton {
  /// Left button (button 0).
  Left
  /// Middle button (button 1).
  Middle
  /// Right button (button 2).
  Right
  /// Button release (button code + 3).
  Release
  /// Motion with the left button held (bit 5 | button 0) — a drag.
  Motion
  /// Motion with no button held (bit 5 | button 3) — pure hover.
  MotionNoButton
  /// Wheel scroll up (bit 6 set).
  WheelUp
  /// Wheel scroll down (bit 6 + 1 set).
  WheelDown
  /// Wheel scroll left (bit 6 + 2 set).
  WheelLeft
  /// Wheel scroll right (bit 6 + 3 set).
  WheelRight
} derive(Eq, Debug)

///|
pub extend MouseButton with Eq::{equal, not_equal}

///|
pub extend MouseButton with @debug.Debug::{to_repr}

///|
/// The raw button/event code.
pub fn MouseButton::code(self : MouseButton) -> Int {
  match self {
    MouseButton::Left => 0
    MouseButton::Middle => 1
    MouseButton::Right => 2
    MouseButton::Release => 3
    MouseButton::Motion => 32
    MouseButton::MotionNoButton => 35
    MouseButton::WheelUp => 64
    MouseButton::WheelDown => 65
    MouseButton::WheelLeft => 66
    MouseButton::WheelRight => 67
  }
}

///|
/// Encode this event as an SGR (`CSI < … M/m`) byte sequence. `x`/`y` are
/// 0-based; the emitted protocol is 1-based.
pub fn MouseButton::encode_sgr(
  self : MouseButton,
  x : Int,
  y : Int,
  pressed : Bool,
) -> Array[Int] {
  let out : Array[Int] = [0x1b, 0x5b, 0x3c]
  push_decimal(out, self.code())
  out.push(0x3b)
  push_decimal(out, x + 1)
  out.push(0x3b)
  push_decimal(out, y + 1)
  out.push(if pressed { 0x4d } else { 0x6d })
  out
}

///|
/// Encode this event in X10 style (`CSI M Cb Cx Cy`, single bytes).
pub fn MouseButton::encode_x10(self : MouseButton, x : Int, y : Int) -> Array[Int] {
  [
    0x1b,
    0x5b,
    0x4d,
    self.code() + 32,
    x + 33,
    y + 33,
  ]
}

///|
/// Encode this event in DEC 1005 UTF-8 mouse style — X10's `CSI M Cb` prefix,
/// but `Cx`/`Cy` are UTF-8 encoded instead of truncated single bytes.
pub fn MouseButton::encode_utf8(self : MouseButton, x : Int, y : Int) -> Array[Int] {
  let out : Array[Int] = [0x1b, 0x5b, 0x4d]
  push_utf8_byte(out, self.code() + 32)
  push_utf8_byte(out, x + 33)
  push_utf8_byte(out, y + 33)
  out
}

///|
/// Encode a mouse event under the given tracking configuration, or `None`
/// when tracking is disabled. `x`/`y` are 0-based cell coordinates.
pub fn MouseButton::encode(
  self : MouseButton,
  tracking : Int,
  x : Int,
  y : Int,
  pressed : Bool,
) -> Option[Array[Int]] {
  if !mouse_tracking_has(tracking, MOUSE_ENABLED) {
    return None
  }
  // X10 (DEC 9) reports only button PRESSES, never releases.
  if mouse_tracking_has(tracking, MOUSE_X10) && !pressed {
    return None
  }
  if mouse_tracking_has(tracking, MOUSE_SGR) ||
    mouse_tracking_has(tracking, MOUSE_PIXEL) {
    return Some(self.encode_sgr(x, y, pressed))
  }
  // Drag motion reports only in any-motion (1003) mode.
  if pressed && self == MouseButton::Motion &&
    !mouse_tracking_has(tracking, MOUSE_ANY_MOTION) {
    return None
  }
  let b = if pressed { self } else { MouseButton::Release }
  if mouse_tracking_has(tracking, MOUSE_UTF8) {
    return Some(b.encode_utf8(x, y))
  }
  // X10's single-byte coordinates top out at 222.
  if x > 222 || y > 222 {
    return None
  }
  Some(b.encode_x10(x, y))
}

///|
/// Append the decimal digits of `n` to `out`.
fn push_decimal(out : Array[Int], n : Int) -> Unit {
  if n == 0 {
    out.push(0x30)
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
/// Append `v` (`0..=255`) as its UTF-8 encoding.
fn push_utf8_byte(out : Array[Int], v : Int) -> Unit {
  if v < 0x80 {
    out.push(v)
  } else {
    out.push(0xc0 | (v >> 6))
    out.push(0x80 | (v & 0x3f))
  }
}
