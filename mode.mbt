// DEC/ANSI terminal mode flags for `CSI Ps h/l` (set/reset) and
// `CSI ? Ps $ p` (DECRQM).
//
// Reference: <https://vt100.net/emu/dec_ansi_parser>.
//
// Flags are `Int64` (33 bits are used); `Int` is 32-bit in MoonBit.

///|
/// No mode.
pub const TERM_NONE : Int64 = 0L

///|
/// IRM (`CSI 4 h/l`) — insert/replace mode.
pub const TERM_INSERT : Int64 = 1L << 0

///|
/// DECOM (`CSI ?6 h/l`) — origin mode.
pub const TERM_ORIGIN : Int64 = 1L << 1

///|
/// DECAWM (`CSI ?7 h/l`) — autowrap.
pub const TERM_WRAPAROUND : Int64 = 1L << 2

///|
/// LNM (`CSI 20 h/l`) — linefeed/newline mode.
pub const TERM_LINEFEED : Int64 = 1L << 3

///|
/// DECTCEM (`CSI ?25 h/l`) — cursor visible.
pub const TERM_CURSOR_VISIBLE : Int64 = 1L << 4

///|
/// XTPUSHKEYS (`CSI ?2004 h/l`) — bracketed paste.
pub const TERM_BRACKETED_PASTE : Int64 = 1L << 5

///|
/// DEC 9 — X10 mouse reporting.
pub const TERM_MOUSE_X10 : Int64 = 1L << 6

///|
/// DEC 1000 — mouse press tracking.
pub const TERM_MOUSE_NORMAL : Int64 = 1L << 7

///|
/// DEC 1002 — mouse drag tracking.
pub const TERM_MOUSE_BUTTON : Int64 = 1L << 8

///|
/// DEC 1003 — mouse any-motion tracking.
pub const TERM_MOUSE_ANY : Int64 = 1L << 9

///|
/// DECCKM (`CSI ?1 h/l`) — application cursor keys (arrows send SS3).
pub const TERM_CURSOR_KEYS : Int64 = 1L << 10

///|
/// DECSCNM (`CSI ?5 h/l`) — reverse video.
pub const TERM_REVERSE : Int64 = 1L << 11

///|
/// DEC 1006 — SGR mouse protocol.
pub const TERM_MOUSE_SGR : Int64 = 1L << 12

///|
/// DECCOLM (`CSI ?3 h/l`) — 132-column mode.
pub const TERM_DECCOLM : Int64 = 1L << 13

///|
/// DEC 47 — alternate screen buffer.
pub const TERM_ALT_SCREEN : Int64 = 1L << 14

///|
/// DEC 1049 — alternate screen that clears on entry and saves/restores the
/// main-screen cursor.
pub const TERM_ALT_SCREEN_1049 : Int64 = 1L << 15

///|
/// DEC 2026 — synchronized output.
pub const TERM_SYNC_OUTPUT : Int64 = 1L << 16

///|
/// XTCOLORMOD (`CSI ?2031 h/l`) — report color-scheme changes.
pub const TERM_COLOR_SCHEME_UPDATES : Int64 = 1L << 17

///|
/// DEC 1004 — focus in/out reporting.
pub const TERM_FOCUS : Int64 = 1L << 18

///|
/// DEC 1005 — UTF-8 mouse reporting.
pub const TERM_UTF8_MOUSE : Int64 = 1L << 19

///|
/// DEC 1007 — alternate scroll (wheel sends arrows).
pub const TERM_ALTERNATE_SCROLL : Int64 = 1L << 20

///|
/// DEC 1046 — alternate screen, save/restore cursor.
pub const TERM_VI : Int64 = 1L << 21

///|
/// DEC 45 — reverse wrap-around.
pub const TERM_REVERSE_WRAP : Int64 = 1L << 22

///|
/// DEC 69 — left/right margin mode (DECLRMM).
pub const TERM_DECLRMM : Int64 = 1L << 23

///|
/// DEC 66 — application keypad mode (DECNKM).
pub const TERM_DECNKM : Int64 = 1L << 24

///|
/// DEC 2027 — Unicode core mode.
pub const TERM_UNICODE_CORE : Int64 = 1L << 25

///|
/// DEC 1016 — SGR-pixel mouse (pixel coordinates).
pub const TERM_MOUSE_PIXEL : Int64 = 1L << 26

///|
/// DEC 80 — Sixel display mode.
pub const TERM_DECSDM : Int64 = 1L << 27

///|
/// DEC 1015 — urxvt mouse protocol.
pub const TERM_MOUSE_URXVT : Int64 = 1L << 28

///|
/// DEC 2048 — in-band window resize.
pub const TERM_IN_BAND_RESIZE : Int64 = 1L << 29

///|
/// DEC 1045 — extended reverse wrap-around.
pub const TERM_REVERSE_WRAP_EXTENDED : Int64 = 1L << 30

///|
/// DEC 1047 — alternate screen that clears on entry.
pub const TERM_ALT_SCREEN_1047 : Int64 = 1L << 31

///|
/// DEC 12 (`CSI ?12 h/l`) — cursor blinking (AT&T 610).
pub const TERM_CURSOR_BLINK : Int64 = 1L << 32

///|
/// Test whether `flags` contains `flag`.
pub fn term_flags_has(flags : Int64, flag : Int64) -> Bool {
  (flags & flag) != 0L
}

///|
/// The DEC private-mode parameter (`? Pm h/l` / DECRQM). `0` for the ANSI
/// mode (insert) and for `TERM_NONE`.
pub fn term_flags_private_param(flags : Int64) -> Int {
  match flags {
    1L => 0 // INSERT (ANSI mode 4)
    2L => 6 // ORIGIN (DECOM)
    4L => 7 // WRAPAROUND (DECAWM)
    8L => 0 // LINEFEED (ANSI LNM 20)
    16L => 25 // CURSOR_VISIBLE (DECTCEM)
    32L => 2004 // BRACKETED_PASTE (XTPUSHKEYS)
    64L => 9 // MOUSE_X10
    128L => 1000 // MOUSE_NORMAL
    256L => 1002 // MOUSE_BUTTON
    512L => 1003 // MOUSE_ANY
    1024L => 1 // CURSOR_KEYS (DECCKM)
    2048L => 5 // REVERSE (DECSCNM)
    4096L => 1006 // MOUSE_SGR
    8192L => 3 // DECCOLM
    16384L => 47 // ALT_SCREEN
    32768L => 1049 // ALT_SCREEN_1049
    65536L => 2026 // SYNC_OUTPUT
    131072L => 2031 // COLOR_SCHEME_UPDATES
    262144L => 1004 // FOCUS
    524288L => 1005 // UTF8_MOUSE
    1048576L => 1007 // ALTERNATE_SCROLL
    2097152L => 1046 // VI
    4194304L => 45 // REVERSE_WRAP
    8388608L => 69 // DECLRMM
    16777216L => 66 // DECNKM
    33554432L => 2027 // UNICODE_CORE
    67108864L => 1016 // MOUSE_PIXEL
    134217728L => 80 // DECSDM
    268435456L => 1015 // MOUSE_URXVT
    536870912L => 2048 // IN_BAND_RESIZE
    1073741824L => 1045 // REVERSE_WRAP_EXTENDED
    2147483648L => 1047 // ALT_SCREEN_1047
    4294967296L => 12 // CURSOR_BLINK
    _ => 0
  }
}

///|
/// Reverse lookup for DECRQM's numeric parameter; unknown → `TERM_NONE`.
pub fn term_flags_from_private_param(param : Int) -> Int64 {
  match param {
    1 => TERM_CURSOR_KEYS
    3 => TERM_DECCOLM
    5 => TERM_REVERSE
    6 => TERM_ORIGIN
    7 => TERM_WRAPAROUND
    9 => TERM_MOUSE_X10
    12 => TERM_CURSOR_BLINK
    25 => TERM_CURSOR_VISIBLE
    45 => TERM_REVERSE_WRAP
    47 => TERM_ALT_SCREEN
    66 => TERM_DECNKM
    69 => TERM_DECLRMM
    80 => TERM_DECSDM
    1000 => TERM_MOUSE_NORMAL
    1002 => TERM_MOUSE_BUTTON
    1003 => TERM_MOUSE_ANY
    1004 => TERM_FOCUS
    1005 => TERM_UTF8_MOUSE
    1006 => TERM_MOUSE_SGR
    1007 => TERM_ALTERNATE_SCROLL
    1015 => TERM_MOUSE_URXVT
    1016 => TERM_MOUSE_PIXEL
    1045 => TERM_REVERSE_WRAP_EXTENDED
    1046 => TERM_VI
    1047 => TERM_ALT_SCREEN_1047
    1049 => TERM_ALT_SCREEN_1049
    2004 => TERM_BRACKETED_PASTE
    2026 => TERM_SYNC_OUTPUT
    2027 => TERM_UNICODE_CORE
    2031 => TERM_COLOR_SCHEME_UPDATES
    2048 => TERM_IN_BAND_RESIZE
    _ => TERM_NONE
  }
}

///|
/// Map an ANSI (`CSI Pm h/l`) or DEC private (`CSI ? Pm h/l`) mode number to
/// its flag. `private` selects the DEC private table; the ANSI table covers
/// IRM (`4`) and LNM (`20`).
pub fn term_flags_from_mode_code(code : Int, private : Bool) -> Int64 {
  if private {
    term_flags_from_private_param(code)
  } else {
    match code {
      4 => TERM_INSERT
      20 => TERM_LINEFEED
      _ => TERM_NONE
    }
  }
}

///|
/// Look up a tracked mode by its numeric code regardless of the ANSI/DEC
/// private split.
pub fn term_flags_from_any_mode_code(code : Int) -> Int64 {
  let ansi = term_flags_from_mode_code(code, false)
  if ansi == TERM_NONE {
    term_flags_from_mode_code(code, true)
  } else {
    ansi
  }
}

///|
/// Mouse-tracking + mouse-protocol modes. Entering the alternate screen
/// resets these so a pager starts clean.
pub const MOUSE_MASK : Int64 = TERM_MOUSE_X10 |
  TERM_MOUSE_NORMAL |
  TERM_MOUSE_BUTTON |
  TERM_MOUSE_ANY |
  TERM_MOUSE_SGR |
  TERM_MOUSE_PIXEL |
  TERM_MOUSE_URXVT |
  TERM_UTF8_MOUSE
