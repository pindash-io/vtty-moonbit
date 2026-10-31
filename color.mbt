// The palette index type used by reply formatting.

///|
/// A palette index: `0..=255` the 256-color table, `256`/`257` default
/// fg/bg, `258+` RGB truecolors inserted on demand.
pub struct ColorId(Int) derive(Eq, @debug.Debug)

///|
pub extend ColorId with Eq::{equal, not_equal}

///|
pub extend ColorId with @debug.Debug::{to_repr}

///|
/// The underlying `Int` index.
pub fn ColorId::index(self : ColorId) -> Int {
  self.0
}

///|
/// Build a `ColorId` from a raw index (no clamping).
pub fn ColorId::from_int(v : Int) -> ColorId {
  ColorId(v)
}

///|
/// SGR indexed-color parameters clamp to the 256-color table (xterm clamps
/// out-of-range indexed colors; values ≥ 256 are malformed).
pub fn ColorId::from_i32(v : Int) -> ColorId {
  if v < 0 {
    ColorId(0)
  } else if v > 255 {
    ColorId(255)
  } else {
    ColorId(v)
  }
}

///|
/// Reserved palette index for the default foreground (SGR 39).
pub fn default_fg_id() -> ColorId {
  ColorId(256)
}

///|
/// Reserved palette index for the default background (SGR 49).
pub fn default_bg_id() -> ColorId {
  ColorId(257)
}

// ── RGB packing / unpacking ─────────────────────────────────────────

///|
/// Clamp one 0..255 channel.
fn clamp_channel(v : Int) -> Int {
  if v < 0 {
    0
  } else if v > 255 {
    255
  } else {
    v
  }
}

///|
/// Pack three 0..255 channels into RGB8 (`0x00RRGGBB`).
pub fn rgb(r : Int, g : Int, b : Int) -> Int {
  (clamp_channel(r) << 16) | (clamp_channel(g) << 8) | clamp_channel(b)
}

///|
/// Convert packed 0xRRGGBB to its three 8-bit channels.
pub fn u32_to_rgb(rgb : Int) -> Array[Int] {
  [(rgb >> 16) & 0xff, (rgb >> 8) & 0xff, rgb & 0xff]
}

// ── xterm 256-color table ──────────────────────────────────────────

///|
/// One channel of the 6×6×6 color cube: level 0 is black, 1..=5 are
/// `55 + level * 40` (0, 95, 135, 175, 215, 255).
fn cube_level(v : Int) -> Int {
  if v == 0 {
    0
  } else {
    55 + v * 40
  }
}

///|
/// Resolve an xterm 256-color index (`0..=255`) to packed `0xRRGGBB`: the 16
/// ANSI colors, the 6×6×6 color cube (`16..=231`), and the grayscale ramp
/// (`232..=255`).
pub fn indexed_rgb(n : Int) -> Int {
  match n {
    0 => 0x000000
    1 => 0xcd0000
    2 => 0x00cd00
    3 => 0xcdcd00
    4 => 0x0000ee
    5 => 0xcd00cd
    6 => 0x00cdcd
    7 => 0xe5e5e5
    8 => 0x7f7f7f
    9 => 0xff0000
    10 => 0x00ff00
    11 => 0xffff00
    12 => 0x5c5cff
    13 => 0xff00ff
    14 => 0x00ffff
    15 => 0xffffff
    16..=231 => {
      let v = n - 16
      let r = v / 36
      let g = (v % 36) / 6
      let b = v % 6
      rgb(cube_level(r), cube_level(g), cube_level(b))
    }
    232..=255 => {
      let v = 8 + (n - 232) * 10
      rgb(v, v, v)
    }
    _ => 0
  }
}

// ── OSC color parsing ───────────────────────────────────────────────

///|
/// A single hex digit (`0..=15`).
fn hex_digit(b : Int) -> Option[Int] {
  if b >= 0x30 && b <= 0x39 {
    Some(b - 0x30)
  } else if b >= 0x61 && b <= 0x66 {
    Some(b - 0x61 + 10)
  } else if b >= 0x41 && b <= 0x46 {
    Some(b - 0x41 + 10)
  } else {
    None
  }
}

///|
/// Decode an `RRGGBB` hex string into three 8-bit channels.
fn decode_rgb(s : ArrayView[Int]) -> Option[Array[Int]] {
  if s.length() != 6 {
    return None
  }
  let out : Array[Int] = []
  let mut i = 0
  while i < 6 {
    let hi = match hex_digit(s[i]) {
      Some(d) => d
      None => return None
    }
    let lo = match hex_digit(s[i + 1]) {
      Some(d) => d
      None => return None
    }
    out.push(hi * 16 + lo)
    i = i + 2
  }
  Some(out)
}

///|
/// Scale one `rgb:` channel of 1..=4 hex digits to 8 bits (`XParseColor`).
fn scale_channel(part : ArrayView[Int]) -> Option[Int] {
  let len = part.length()
  if len < 1 || len > 4 {
    return None
  }
  let mut v = 0
  for b in part {
    let d = match hex_digit(b) {
      Some(d) => d
      None => return None
    }
    v = v * 16 + d
  }
  Some(v * 255 / ((1 << (4 * len)) - 1))
}

///|
/// Parse an OSC color (`rgb:RR/GG/BB`, `rgb:RRRR/GGGG/BBBB`, or
/// `#RRGGBB`) into a 0xRRGGBB value. `rgb:` channels of 1..4 hex digits are
/// scaled to 8 bits (`XParseColor` semantics).
pub fn parse(s : ArrayView[Int]) -> Option[Int] {
  // `rgb:` prefix: 0x72 0x67 0x62 0x3a.
  if s.length() >= 4 && s[0] == 0x72 && s[1] == 0x67 && s[2] == 0x62 &&
    s[3] == 0x3a {
    let parts : Array[ArrayView[Int]] = []
    let mut start = 4
    let mut i = 4
    while i <= s.length() {
      if i == s.length() || s[i] == 0x2f {
        parts.push(s[start:i])
        start = i + 1
      }
      i = i + 1
    }
    if parts.length() != 3 {
      return None
    }
    let a = match scale_channel(parts[0]) {
      Some(v) => v
      None => return None
    }
    let b = match scale_channel(parts[1]) {
      Some(v) => v
      None => return None
    }
    let c = match scale_channel(parts[2]) {
      Some(v) => v
      None => return None
    }
    return Some(rgb(a, b, c))
  }
  // `#RRGGBB`.
  if s.length() >= 1 && s[0] == 0x23 {
    let channels = match decode_rgb(s[1:]) {
      Some(c) => c
      None => return None
    }
    return Some(rgb(channels[0], channels[1], channels[2]))
  }
  None
}

// ── OSC color replies ───────────────────────────────────────────────

///|
/// One lowercase hex digit character (`0..=15`).
fn hex_digit_char(d : Int) -> Char {
  if d < 10 {
    Int::to_char(0x30 + d).unwrap_or('0')
  } else {
    Int::to_char(0x61 + d - 10).unwrap_or('a')
  }
}

///|
/// Format one 0..255 channel as two lowercase hex digits.
fn hex2(v : Int) -> String {
  hex_digit_char((v >> 4) & 0xf).to_string() +
    hex_digit_char(v & 0xf).to_string()
}

///|
/// Format an OSC color reply `ESC]CODE;rgb:RRRR/GGGG/BBBB ESC\` from a
/// 0xRRGGBB value (8-bit channels repeated to 4 hex digits, the xterm
/// convention).
pub fn format_osc_color_reply(code : Int, rgb : Int) -> String {
  let r = (rgb >> 16) & 0xff
  let g = (rgb >> 8) & 0xff
  let b = rgb & 0xff
  "\u{1b}]" +
    code.to_string() +
    ";rgb:" +
    hex2(r) +
    hex2(r) +
    "/" +
    hex2(g) +
    hex2(g) +
    "/" +
    hex2(b) +
    hex2(b) +
    "\u{1b}\\"
}

///|
/// Format an `OSC 4` palette-entry reply `ESC]4;N;rgb:RRRR/GGGG/BBBB ESC\`.
pub fn format_osc_palette_reply(index : Int, rgb : Int) -> String {
  let r = (rgb >> 16) & 0xff
  let g = (rgb >> 8) & 0xff
  let b = rgb & 0xff
  "\u{1b}]4;" +
    index.to_string() +
    ";rgb:" +
    hex2(r) +
    hex2(r) +
    "/" +
    hex2(g) +
    hex2(g) +
    "/" +
    hex2(b) +
    hex2(b) +
    "\u{1b}\\"
}
