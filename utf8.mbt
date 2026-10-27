// Incremental UTF-8 decoding helpers.

///|
/// Expected byte length and initial code-point bits for a UTF-8 lead byte —
/// the two facts the partial decoder needs, from one range dispatch.
///
/// Returns `(expected_len, lead_bits)`; `expected_len` is `0` for invalid
/// (`0x80..=0xc1`, `0xf5..=0xff`) and continuation (`0x80..=0xbf`) bytes.
pub fn utf8_lead(lead : Int) -> (Int, Int) {
  match lead {
    0x00..=0x7f => (1, lead)
    0xc2..=0xdf => (2, lead & 0x1f)
    0xe0..=0xef => (3, lead & 0x0f)
    0xf0..=0xf4 => (4, lead & 0x07)
    _ => (0, 0)
  }
}

///|
/// Whether `second` is a valid second byte for a constrained 3/4-byte `lead`
/// (UTF-8's non-shortest / non-surrogate / non-overlong rules).
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
/// If `s` ends with a partial UTF-8 sequence, return
/// `(valid_prefix_len, partial_codepoint, remaining_continuation_bytes)`;
/// the partial is carried to the next `advance` call.
///
/// A complete ASCII/valid tail, an invalid byte (`0xC0`/`0xC1`/`0xF5..=0xFF`),
/// an over-long run of continuations, and an out-of-range second byte are all
/// `None` — the main loop decodes them as `U+FFFD`.
pub fn trailing_partial(s : ArrayView[Int]) -> Option[(Int, Int, Int)] {
  let len = s.length()
  if len == 0 {
    return None
  }
  let last = s[len - 1]
  if last < 0x80 {
    return None // complete ASCII
  }
  if last >= 0xc2 && last <= 0xf4 {
    // A lead byte at the very end.
    let (expected, cp) = utf8_lead(last)
    return Some((len - 1, cp, expected - 1))
  }
  // `last` is neither ASCII, a valid lead, nor a continuation byte — it is an
  // invalid byte. Not a trailing partial.
  if !(last >= 0x80 && last <= 0xbf) {
    return None
  }
  // Walk back over continuation bytes to the lead byte.
  let mut back = 1
  while back < 3 && len > back {
    let b = s[len - 1 - back]
    if b >= 0x80 && b <= 0xbf {
      back = back + 1
    } else {
      break
    }
  }
  // All continuation bytes and no lead byte → not a partial.
  if back >= len {
    return None
  }
  let lead_idx = len - 1 - back
  let lead = s[lead_idx]
  let (expected, lead_cp) = utf8_lead(lead)
  let have = back + 1
  if expected == 0 || have >= expected {
    return None
  }
  // An out-of-range second byte is invalid UTF-8, not a truncated partial.
  if have >= 2 && !utf8_second_byte_valid(lead, s[lead_idx + 1]) {
    return None
  }
  let mut cp = lead_cp
  let mut j = lead_idx + 1
  while j < len {
    cp = (cp << 6) | (s[j] & 0x3f)
    j = j + 1
  }
  Some((lead_idx, cp, expected - have))
}
