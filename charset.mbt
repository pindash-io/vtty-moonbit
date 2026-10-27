// G0/G1 charset designation (`ESC ( 0` line drawing).
//
// Reference: <https://vt100.net/emu/dec_ansi_parser>.

///|
/// DEC Special Graphics translation for `0x5f..=0x7e`, used when G0/G1 is
/// designated to charset `0` (`ESC ( 0` / `ESC ) 0`).
pub fn dec_special_graphics(c : Char) -> Char {
  match c {
    '_' => ' '
    '`' => '◆'
    'a' => '▒'
    'b' => '␉'
    'c' => '␌'
    'd' => '␍'
    'e' => '␊'
    'f' => '°'
    'g' => '±'
    'h' => '␤'
    'i' => '␋'
    'j' => '┘'
    'k' => '┐'
    'l' => '┌'
    'm' => '└'
    'n' => '┼'
    'o' => '⎺'
    'p' => '⎻'
    'q' => '─'
    'r' => '⎼'
    's' => '⎽'
    't' => '├'
    'u' => '┤'
    'v' => '┴'
    'w' => '┬'
    'x' => '│'
    'y' => '≤'
    'z' => '≥'
    '{' => 'π'
    '|' => '≠'
    '}' => '£'
    '~' => '·'
    _ => c
  }
}

///|
/// A designated charset for G0/G1 (`ESC ( 0` = DEC Special Graphics).
pub(all) enum Charset {
  /// US-ASCII (the default).
  Ascii
  /// DEC Special Graphics — maps ASCII `0x5f..=0x7e` to line-drawing and
  /// special glyphs (`─│┌┐└┘` etc.).
  Dec
  /// British (`ESC ( A`) — maps `#` to `£`.
  British
} derive(Eq, Debug)

///|
pub extend Charset with Eq::{equal, not_equal}

///|
pub extend Charset with @debug.Debug::{to_repr}

///|
/// Translate a char through the designated charset.
pub fn Charset::map(self : Charset, c : Char) -> Char {
  match self {
    Charset::Ascii => c
    Charset::Dec =>
      if c >= '\u{5f}' && c <= '\u{7e}' {
        dec_special_graphics(c)
      } else {
        c
      }
    Charset::British => if c == '#' { '£' } else { c }
  }
}

///|
/// The four ISO 2022 designated character sets (G0, G1, G2, G3), selected by
/// the `ESC ( / ) / * / +` designation sequences and the SO/SI/SS2/SS3 shift
/// controls. A terminal carries these as one unit: DECSC/DECRC save and
/// restore all four together.
pub struct Charsets {
  slots : Array[Charset]
}

///|
/// All slots designated to US-ASCII (the power-on state).
pub fn Charsets::ascii() -> Charsets {
  { slots: [Charset::Ascii, Charset::Ascii, Charset::Ascii, Charset::Ascii] }
}

///|
/// Designate slot `g` to `charset`; a code past the last slot clamps to G3
/// (the last slot).
pub fn Charsets::designate(self : Charsets, g : Int, charset : Charset) -> Unit {
  let idx = if g < 3 { g } else { 3 }
  self.slots[idx] = charset
}

///|
/// Read slot `g`.
pub fn Charsets::get(self : Charsets, g : Int) -> Charset {
  if g < 4 {
    self.slots[g]
  } else {
    self.slots[3]
  }
}

///|
/// The G0 set (the default, and SI `0x0F` target).
pub fn Charsets::g0(self : Charsets) -> Charset {
  self.slots[0]
}

///|
/// The G1 set (SO `0x0E` shift target).
pub fn Charsets::g1(self : Charsets) -> Charset {
  self.slots[1]
}

///|
/// The G2 set (SS2 `0x8E` single-shift target).
pub fn Charsets::g2(self : Charsets) -> Charset {
  self.slots[2]
}

///|
/// The G3 set (SS3 `0x8F` single-shift target).
pub fn Charsets::g3(self : Charsets) -> Charset {
  self.slots[3]
}
