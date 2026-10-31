// Minimal byte-cursor state (the O(bytes) floor).

///|
/// UTF-8 byte length of a `Char`.
fn utf8_len(c : Char) -> Int {
  let cp = c.to_int()
  if cp < 0x80 {
    1
  } else if cp < 0x800 {
    2
  } else if cp < 0x10000 {
    3
  } else {
    4
  }
}

///|
/// UTF-8 byte length of a `String`.
fn string_byte_len(s : String) -> Int {
  let mut total = 0
  for c in s {
    total = total + utf8_len(c)
  }
  total
}

///|
/// Char index of the first char at or after UTF-8 byte offset `byte_off`.
fn byte_to_char_index(s : String, byte_off : Int) -> Int {
  let mut total = 0
  let mut idx = 0
  for c in s {
    if total >= byte_off {
      return idx
    }
    total = total + utf8_len(c)
    idx = idx + 1
  }
  idx
}

///|
/// Build a `String` from printable-ASCII byte values (the `print_bytes` run).
fn ascii_bytes_to_string(s : ArrayView[Int]) -> String {
  let chars : Array[Char] = []
  for b in s {
    chars.push(Int::to_char(b).unwrap_or('\u{FFFD}'))
  }
  String::from_array(chars[:])
}

///|
/// Minimal byte-cursor state: accumulated text (lines joined by `\n`), the
/// cursor as a UTF-8 BYTE offset, and the byte offset of the current line's
/// start.
pub struct State {
  mut text : String
  mut cursor : Int
  mut line_start : Int
}

///|
/// An empty cursor state.
pub fn State::new() -> State {
  { text: "", cursor: 0, line_start: 0 }
}

///|
/// The accumulated text.
pub fn State::text(self : State) -> String {
  self.text
}

///|
/// The cursor byte offset.
pub fn State::cursor(self : State) -> Int {
  self.cursor
}

///|
/// Number of lines in the text buffer. An empty buffer has 0 lines; each
/// `\n` starts a new line (a trailing `\n` counts as one empty line).
pub fn State::line_count(self : State) -> Int {
  if self.text.length() == 0 {
    return 0
  }
  let mut n = 0
  for c in self.text {
    if c == '\n' {
      n = n + 1
    }
  }
  n + 1
}

///|
/// 0-based row (line index) of the cursor.
pub fn State::cursor_row(self : State) -> Int {
  let len = string_byte_len(self.text)
  let cursor = if self.cursor < len { self.cursor } else { len }
  let mut n = 0
  let mut byte = 0
  for c in self.text {
    if byte >= cursor {
      break
    }
    if c == '\n' {
      n = n + 1
    }
    byte = byte + utf8_len(c)
  }
  n
}

///|
/// 0-based BYTE column of the cursor within its line.
pub fn State::cursor_col(self : State) -> Int {
  let len = string_byte_len(self.text)
  let cursor = if self.cursor < len { self.cursor } else { len }
  cursor - self.line_start
}

///|
/// Byte range `[start, end)` of line `line` (0-based). `end` is exclusive: it
/// points at the line's `\n` byte, or at the buffer end for the last line.
/// Returns `None` when `line` is out of range (or the buffer is empty).
pub fn State::line_range(self : State, line : Int) -> Option[(Int, Int)] {
  if line < 0 || self.text.length() == 0 {
    return None
  }
  let mut byte = 0
  let nls : Array[Int] = []
  for c in self.text {
    if c == '\n' {
      nls.push(byte)
    }
    byte = byte + utf8_len(c)
  }
  if byte == 0 {
    return None
  }
  let start = if line == 0 {
    0
  } else {
    if line - 1 < nls.length() {
      nls[line - 1] + 1
    } else {
      return None
    }
  }
  let end = if line < nls.length() { nls[line] } else { byte }
  Some((start, end))
}

///|
pub impl Perform for State with fn print(self, c : Char) {
  let s = c.to_string()
  let pos = self.cursor
  let len = string_byte_len(self.text)
  if pos < len {
    let idx = byte_to_char_index(self.text, pos)
    let (before, after) = self.text.split_at(idx)
    self.text = before.to_owned() + s + after.to_owned()
  } else {
    self.text = self.text + s
  }
  self.cursor = pos + utf8_len(c)
}

///|
pub impl Perform for State with fn print_bytes(self, s : ArrayView[Int]) {
  let str = ascii_bytes_to_string(s)
  let pos = self.cursor
  let len = string_byte_len(self.text)
  if pos < len {
    let idx = byte_to_char_index(self.text, pos)
    let (before, after) = self.text.split_at(idx)
    self.text = before.to_owned() + str + after.to_owned()
  } else {
    self.text = self.text + str
  }
  self.cursor = pos + string_byte_len(str)
}

///|
pub impl Perform for State with fn execute(self, b : Int) {
  match b {
    0x0a => {
      self.text = self.text + "\n"
      self.cursor = string_byte_len(self.text)
      self.line_start = self.cursor
    }
    // CR returns to column 0 without advancing a line.
    0x0d => self.cursor = self.line_start
    _ => ()
  }
}

///|
pub extend State with Perform::{
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
