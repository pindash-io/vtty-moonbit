// Incremental UTF-8 decoding helpers.

///|
/// Expected UTF-8 byte length for a lead byte (`0` = invalid/continuation).
pub fn utf8_expected(lead : Int) -> Int {
  match lead {
    0x00..=0x7f => 1
    0xc2..=0xdf => 2
    0xe0..=0xef => 3
    0xf0..=0xf4 => 4
    _ => 0
  }
}

///|
/// Whether `second` is a valid second byte for a constrained 3/4-byte `lead`
/// (non-shortest / non-surrogate / non-overlong rules).
pub fn utf8_second_byte_valid(lead : Int, second : Int) -> Bool {
  match lead {
    0xe0 => second >= 0xa0 && second <= 0xbf
    0xed => second >= 0x80 && second <= 0x9f
    0xf0 => second >= 0x90 && second <= 0xbf
    0xf4 => second >= 0x80 && second <= 0x8f
    _ => true
  }
}

///|
/// Code-point bits contributed by a UTF-8 lead byte.
pub fn utf8_lead_cp(lead : Int) -> Int {
  match lead {
    0x00..=0x7f => lead
    0xc0..=0xdf => lead & 0x1f
    0xe0..=0xef => lead & 0x0f
    0xf0..=0xf7 => lead & 0x07
    _ => 0
  }
}
