// Query/response reply formatting (DECRQSS / DECRQM / XTGETTCAP).
//
// Reference: <https://vt100.net/emu/dec_ansi_parser>.

///|
/// Hex-encode a string (used by XTGETTCAP).
fn hex_encode(s : String) -> String {
  @hex.encode(@utf8.encode(s))
}

///|
/// Accumulates VT query replies in dispatch order, so a burst of queries is
/// answered in order instead of dropping all but the last.
pub struct Reply {
  buf : StringBuilder
  mut empty : Bool
}

///|
/// An empty reply buffer.
pub fn Reply::new() -> Reply {
  { buf: StringBuilder(), empty: true }
}

///|
/// Whether nothing has been appended yet.
pub fn Reply::is_empty(self : Reply) -> Bool {
  self.empty
}

///|
/// Append a DECRQSS answer: `DCS {valid} $ r {value} ST`.
pub fn Reply::decrqss(self : Reply, valid : Bool, value : String) -> Reply {
  self.buf.write_string("\u{1b}P")
  self.buf.write_string(if valid { "1" } else { "0" })
  self.buf.write_string("$r")
  self.buf.write_string(value)
  self.buf.write_string("\u{1b}\\")
  self.empty = false
  self
}

///|
/// Append an XTGETTCAP answer: `DCS {ok} + r {hex key}[={hex value}] ST`.
fn Reply::xtgettcap(
  self : Reply,
  ok : Bool,
  key : String,
  value : Option[String],
) -> Reply {
  self.buf.write_string(if ok { "\u{1b}P1+r" } else { "\u{1b}P0+r" })
  self.buf.write_string(hex_encode(key))
  match value {
    Some(v) => {
      self.buf.write_string("=")
      self.buf.write_string(hex_encode(v))
    }
    None => ()
  }
  self.buf.write_string("\u{1b}\\")
  self.empty = false
  self
}

///|
/// Append an XTGETTCAP answer: `DCS 1 + r {hex key}={hex value} ST`.
pub fn Reply::xtgettcap_reply(self : Reply, key : String, value : String) -> Reply {
  self.xtgettcap(true, key, Some(value))
}

///|
/// Append an XTGETTCAP boolean answer: `DCS 1 + r {hex key} ST`.
pub fn Reply::xtgettcap_reply_bool(self : Reply, key : String) -> Reply {
  self.xtgettcap(true, key, None)
}

///|
/// Append an XTGETTCAP failure: `DCS 0 + r {hex msg} ST`.
pub fn Reply::xtgettcap_error(self : Reply, msg : String) -> Reply {
  self.xtgettcap(false, msg, None)
}

///|
/// Append an XTGETTCAP answer with a decimal integer value, hex-encoding the
/// digits directly.
pub fn Reply::xtgettcap_num(self : Reply, key : String, n : Int) -> Reply {
  self.buf.write_string("\u{1b}P1+r")
  self.buf.write_string(hex_encode(key))
  self.buf.write_string("=")
  self.buf.write_string(hex_encode(n.to_string()))
  self.buf.write_string("\u{1b}\\")
  self.empty = false
  self
}

///|
/// Append an SGR reply (`m…`) from a pen's palette ids + style flags.
/// Starts with `0` (reset-all), like vte. `palette` resolves RGB ids.
pub fn Reply::sgr(
  self : Reply,
  fg : ColorId,
  bg : ColorId,
  flags : Int,
  palette : ArrayView[Int],
) -> Reply {
  self.buf.write_string("0")
  if sgr_flags_has(flags, SGR_BOLD) {
    self.buf.write_string(";1")
  }
  if sgr_flags_has(flags, SGR_ITALIC) {
    self.buf.write_string(";3")
  }
  if sgr_flags_has(flags, SGR_UNDERLINE) {
    self.buf.write_string(";4")
  }
  if sgr_flags_has(flags, SGR_INVERSE) {
    self.buf.write_string(";7")
  }
  push_sgr_color(self.buf, 3, fg, default_fg_id(), palette)
  push_sgr_color(self.buf, 4, bg, default_bg_id(), palette)
  self.empty = false
  self
}

///|
/// Append a DECRQM answer: `CSI {?}{param};{state}$y`.
pub fn Reply::decrqm(
  self : Reply,
  param : Int,
  private : Bool,
  state : Int,
) -> Reply {
  self.buf.write_string("\u{1b}[")
  if private {
    self.buf.write_string("?")
  }
  self.buf.write_string(param.to_string())
  self.buf.write_string(";")
  self.buf.write_string(state.to_string())
  self.buf.write_string("$y")
  self.empty = false
  self
}

///|
/// Finish and return the accumulated reply.
pub fn Reply::finish(self : Reply) -> String {
  self.buf.to_string()
}

///|
/// Append an SGR color to `s`: `;{base}9` (default), `;{base}8;5;n`
/// (indexed), or `;{base}8;2;r;g;b` (RGB, resolved from the palette).
fn push_sgr_color(
  s : StringBuilder,
  base : Int,
  id : ColorId,
  default_id : ColorId,
  palette : ArrayView[Int],
) -> Unit {
  if id == default_id {
    s.write_string(";")
    s.write_string(base.to_string())
    s.write_string("9")
    return
  }
  if id.index() <= 255 {
    s.write_string(";")
    s.write_string(base.to_string())
    s.write_string("8;5;")
    s.write_string(id.index().to_string())
    return
  }
  match palette.get(id.index()) {
    Some(rgb) => {
      s.write_string(";")
      s.write_string(base.to_string())
      s.write_string("8;2;")
      s.write_string(((rgb >> 16) & 0xff).to_string())
      s.write_string(";")
      s.write_string(((rgb >> 8) & 0xff).to_string())
      s.write_string(";")
      s.write_string((rgb & 0xff).to_string())
    }
    None => {
      s.write_string(";")
      s.write_string(base.to_string())
      s.write_string("9")
    }
  }
}
