// DEC conformance and identity: DECSCL, Device Attributes (DA1/DA2/DA3), and
// the `$`-family DCS reports (DECTSR / DECCTR / DECCIR / DECTABSR).
//
// Reference: EK-VT520-RM §5.

///|
/// DECTSR prefix — `DCS 1 $ s` (Terminal State Report; lowercase `s` final).
const DECTSR_PREFIX : String = "\u{1b}P1$s"

///|
/// DECCTR prefix — `DCS 2 $ s` (Color Table Report).
const DECCTR_PREFIX : String = "\u{1b}P2$s"

///|
/// DECCIR prefix — `DCS 1 $ u` (Cursor Information Report).
const DECCIR_PREFIX : String = "\u{1b}P1$u"

///|
/// DECTABSR prefix — `DCS 2 $ u` (Tab Stop Report).
const DECTABSR_PREFIX : String = "\u{1b}P2$u"

///|
/// DECSCL conformance level: the VT operating level selected by `Ps1`
/// (`61..=65`). `Ps2` (7/8-bit C1 controls) is handled separately
/// (S7C1T / S8C1T).
pub(all) enum ConformanceLevel {
  /// VT100 (`CSI 61 " p`).
  Vt100
  /// VT200 (`CSI 62 " p`).
  Vt200
  /// VT300 (`CSI 63 " p`).
  Vt300
  /// VT400 (`CSI 64 " p`).
  Vt400
  /// VT500 (`CSI 65 " p`).
  Vt500
} derive(Eq, Debug)

///|
pub extend ConformanceLevel with Eq::{equal, not_equal}

///|
pub extend ConformanceLevel with @debug.Debug::{to_repr}

///|
/// Factory default: VT500.
pub fn ConformanceLevel::default() -> ConformanceLevel {
  ConformanceLevel::Vt500
}

///|
/// DECSCL `Ps1` parameter (`61..=65`).
pub fn ConformanceLevel::param(self : ConformanceLevel) -> Int {
  match self {
    ConformanceLevel::Vt100 => 61
    ConformanceLevel::Vt200 => 62
    ConformanceLevel::Vt300 => 63
    ConformanceLevel::Vt400 => 64
    ConformanceLevel::Vt500 => 65
  }
}

///|
/// Parse a DECSCL `Ps1` parameter; `None` for `0` (no-op) or outside
/// `61..=65`.
pub fn ConformanceLevel::from_param(p : Int) -> Option[ConformanceLevel] {
  match p {
    61 => Some(ConformanceLevel::Vt100)
    62 => Some(ConformanceLevel::Vt200)
    63 => Some(ConformanceLevel::Vt300)
    64 => Some(ConformanceLevel::Vt400)
    65 => Some(ConformanceLevel::Vt500)
    _ => None
  }
}

///|
/// Wrap `{prefix}{payload}` in a DCS string (`… ST`).
fn dcs_string(prefix : String, payload : String) -> String {
  prefix + payload + "\u{1b}\\"
}

///|
/// Lowercase hex, two digits per byte.
fn hex_encode_bytes(bytes : ArrayView[Int]) -> String {
  let buf = StringBuilder()
  for b in bytes {
    buf.write_string(hex2(b))
  }
  buf.to_string()
}

///|
/// Build `{prefix}{items}{suffix}`, items joined by `sep`.
fn join_wrapped(
  prefix : String,
  items : ArrayView[Int],
  sep : Char,
  suffix : String,
) -> String {
  let buf = StringBuilder()
  buf.write_string(prefix)
  join_display(buf, items, sep)
  buf.write_string(suffix)
  buf.to_string()
}

///|
/// Append `items` to `buf`, separated by `sep`.
fn join_display(buf : StringBuilder, items : ArrayView[Int], sep : Char) -> Unit {
  for i = 0; i < items.length(); i = i + 1 {
    if i > 0 {
      buf.write_char(sep)
    }
    buf.write_string(items[i].to_string())
  }
}

///|
/// Scale 8-bit RGB to the DEC 0-100 range (round to nearest).
fn dec_percent(v : Int) -> Int {
  (v * 100 + 127) / 255
}

///|
/// DA1 answer: `CSI ? a0;a1;… c`. First attr is the service class
/// (`65` = VT500); the rest are extension codes.
pub fn Reply::da1(attrs : ArrayView[Int]) -> String {
  join_wrapped("\u{1b}[?", attrs, ';', "c")
}

///|
/// DA2 answer: `CSI > id;firmware;keyboard c` (`id` 64/65, `keyboard` 0/1).
pub fn Reply::da2(id : Int, firmware : Int, keyboard : Int) -> String {
  "\u{1b}[>" +
    id.to_string() +
    ";" +
    firmware.to_string() +
    ";" +
    keyboard.to_string() +
    "c"
}

///|
/// DA3 answer: `DCS ! | {hex} ST` — unit ID as hex byte pairs.
pub fn Reply::da3(unit_id : ArrayView[Int]) -> String {
  dcs_string("\u{1b}P!|", hex_encode_bytes(unit_id))
}

///|
/// DECTSR answer: `DCS 1 $ s {device_attrs} ST`.
pub fn Reply::dectsr(device_attrs : String) -> String {
  dcs_string(DECTSR_PREFIX, device_attrs)
}

///|
/// XTVERSION answer: `DCS > | {name} {version} ST` (`CSI > q` query).
pub fn Reply::xtversion(name : String, version : String) -> String {
  "\u{1b}P>|" + name + " " + version + "\u{1b}\\"
}

///|
/// DECCTR answer: `DCS 2 $ s {Pc;2;r;g;b / …} ST` — 8-bit RGB scaled to
/// DEC 0-100.
pub fn Reply::decctr(entries : Array[(Int, Int, Int, Int)]) -> String {
  let buf = StringBuilder()
  buf.write_string(DECCTR_PREFIX)
  for i = 0; i < entries.length(); i = i + 1 {
    let (idx, r, g, b) = entries[i]
    if i > 0 {
      buf.write_char('/')
    }
    buf.write_string(idx.to_string())
    buf.write_string(";2;")
    buf.write_string(dec_percent(r).to_string())
    buf.write_string(";")
    buf.write_string(dec_percent(g).to_string())
    buf.write_string(";")
    buf.write_string(dec_percent(b).to_string())
  }
  buf.write_string("\u{1b}\\")
  buf.to_string()
}

///|
/// DECCIR answer: `DCS 1 $ u {payload} ST` (cursor state, screen-built).
pub fn Reply::deccir(payload : String) -> String {
  dcs_string(DECCIR_PREFIX, payload)
}

///|
/// DECTABSR answer: `DCS 2 $ u {col/col/…} ST`.
pub fn Reply::dectabsr(cols : ArrayView[Int]) -> String {
  join_wrapped(DECTABSR_PREFIX, cols, '/', "\u{1b}\\")
}
