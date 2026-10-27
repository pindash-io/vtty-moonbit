// Kitty keyboard protocol flags (`CSI > flags u` / `CSI < count u`).

///|
/// Disambiguate escape codes (`CSI u`).
pub const KITTY_DISAMBIGUATE : Int = 1

///|
/// Report event types (key press/repeat/release).
pub const KITTY_REPORT_EVENT_TYPES : Int = 2

///|
/// Report alternate keys (shift+tab, etc.).
pub const KITTY_REPORT_ALTERNATE_KEYS : Int = 4

///|
/// Report all keys as escape sequences.
pub const KITTY_REPORT_ALL_KEYS : Int = 8

///|
/// Report associated text (IME/composing input).
pub const KITTY_REPORT_ASSOCIATED_TEXT : Int = 16

///|
/// Test whether `flags` contains `flag`.
pub fn kitty_flags_has(flags : Int, flag : Int) -> Bool {
  (flags & flag) != 0
}
