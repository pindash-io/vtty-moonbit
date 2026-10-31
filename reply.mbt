// Query/response reply formatting (DECRQSS / DECRQM / XTGETTCAP and the
// `$`-family DCS reports).

///|
/// Hex-encode a string (used by XTGETTCAP).
fn hex_encode(s : String) -> String {
  @hex.encode(@utf8.encode(s))
}

///|
/// Namespace for VT query reply builders. Each associated function returns
/// the finished reply as a `String`; the screen accumulates a burst of
/// replies by concatenating them in dispatch order.
pub struct Reply {}

///|
/// Build a DECRQSS answer: `DCS {valid} $ r {value} ST`.
pub fn Reply::decrqss(valid : Bool, value : String) -> String {
  (if valid { "\u{1b}P1$r" } else { "\u{1b}P0$r" }) + value + "\u{1b}\\"
}

///|
/// Append an XTGETTCAP answer: `DCS {ok} + r {hex key}[={hex value}] ST`.
fn xtgettcap(ok : Bool, key : String, value : Option[String]) -> String {
  let buf = StringBuilder()
  buf.write_string(if ok { "\u{1b}P1+r" } else { "\u{1b}P0+r" })
  buf.write_string(hex_encode(key))
  match value {
    Some(v) => {
      buf.write_string("=")
      buf.write_string(hex_encode(v))
    }
    None => ()
  }
  buf.write_string("\u{1b}\\")
  buf.to_string()
}

///|
/// Build an XTGETTCAP answer: `DCS 1 + r {hex key}={hex value} ST`.
pub fn Reply::xtgettcap_reply(key : String, value : String) -> String {
  xtgettcap(true, key, Some(value))
}

///|
/// Build an XTGETTCAP boolean answer: `DCS 1 + r {hex key} ST`.
pub fn Reply::xtgettcap_reply_bool(key : String) -> String {
  xtgettcap(true, key, None)
}

///|
/// Build an XTGETTCAP failure: `DCS 0 + r {hex msg} ST`.
pub fn Reply::xtgettcap_error(msg : String) -> String {
  xtgettcap(false, msg, None)
}

///|
/// Build an XTGETTCAP answer with a decimal integer value, hex-encoding the
/// digits directly.
pub fn Reply::xtgettcap_num(key : String, n : Int) -> String {
  xtgettcap(true, key, Some(n.to_string()))
}

///|
/// Build an SGR reply (`m…`) from a pen's palette ids + style flags.
/// Starts with `0` (reset-all), like vte. `palette` resolves RGB ids.
pub fn Reply::sgr(
  fg : ColorId,
  bg : ColorId,
  flags : Int,
  palette : ArrayView[Int],
) -> String {
  let buf = StringBuilder()
  buf.write_string("0")
  if sgr_flags_has(flags, SGR_BOLD) {
    buf.write_string(";1")
  }
  if sgr_flags_has(flags, SGR_ITALIC) {
    buf.write_string(";3")
  }
  if sgr_flags_has(flags, SGR_UNDERLINE) {
    buf.write_string(";4")
  }
  if sgr_flags_has(flags, SGR_INVERSE) {
    buf.write_string(";7")
  }
  push_sgr_color(buf, 3, fg, default_fg_id(), palette)
  push_sgr_color(buf, 4, bg, default_bg_id(), palette)
  buf.to_string()
}

///|
/// Build an OSC color reply `ESC]CODE;rgb:RRRR/GGGG/BBBB ESC\` from a
/// 0xRRGGBB value (8-bit channels repeated to 4 hex digits, the xterm
/// convention).
pub fn Reply::osc_color(code : Int, rgb : Int) -> String {
  format_osc_color_reply(code, rgb)
}

///|
/// Build an `OSC 4` palette-entry reply
/// `ESC]4;N;rgb:RRRR/GGGG/BBBB ESC\`.
pub fn Reply::osc_palette(index : Int, rgb : Int) -> String {
  format_osc_palette_reply(index, rgb)
}

///|
/// Build a DECRQM answer: `CSI {?}{param};{state}$y`. `state` is the Pm
/// value: 0 = not recognized, 1 = set, 2 = reset. `private` includes the `?`
/// for `CSI ?Ps$p` queries.
pub fn Reply::decrqm(param : Int, private : Bool, state : Int) -> String {
  let buf = StringBuilder()
  buf.write_string("\u{1b}[")
  if private {
    buf.write_string("?")
  }
  buf.write_string(param.to_string())
  buf.write_string(";")
  buf.write_string(state.to_string())
  buf.write_string("$y")
  buf.to_string()
}

///|
/// Append an SGR color to `s`: `;{base}9` (default), `;{base}8;5;n`
/// (indexed), or `;{base}8;2;r;g;b` (RGB, resolved from the palette).
/// `base` is 3 for fg, 4 for bg; `default_id` is the matching default color.
fn push_sgr_color(
  s : StringBuilder,
  base : Int,
  id : ColorId,
  default_id : ColorId,
  palette : ArrayView[Int],
) -> Unit {
  if id != default_id {
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
        return
      }
      None => ()
    }
  }
  s.write_string(";")
  s.write_string(base.to_string())
  s.write_string("9")
}
