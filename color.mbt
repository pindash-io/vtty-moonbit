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
