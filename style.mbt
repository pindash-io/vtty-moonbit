// Shared style types (cursor shape, underline style, SGR flags).

// ── SGR flags (bitmask) ────────────────────────────────────────────────

///|
/// SGR 4 underline.
pub const SGR_UNDERLINE : Int = 1 << 0

///|
/// SGR 9 strikethrough.
pub const SGR_STRIKETHROUGH : Int = 1 << 1

///|
/// SGR 53 overline.
pub const SGR_OVERLINE : Int = 1 << 2

///|
/// SGR 1 bold.
pub const SGR_BOLD : Int = 1 << 3

///|
/// SGR 3 italic.
pub const SGR_ITALIC : Int = 1 << 4

///|
/// SGR 2 faint.
pub const SGR_FAINT : Int = 1 << 5

///|
/// SGR 7 inverse video.
pub const SGR_INVERSE : Int = 1 << 6

///|
/// SGR 8 invisible.
pub const SGR_INVISIBLE : Int = 1 << 7

///|
/// SGR 5 slow blink.
pub const SGR_BLINK : Int = 1 << 8

///|
/// SGR 6 rapid blink.
pub const SGR_BLINK_RAPID : Int = 1 << 9

///|
/// Parse-time mark: an SGR "reset" code clears the carried flags rather than
/// setting them (stripped before the flags reach state).
pub const SGR_RESET : Int = 1 << 10

///|
/// No attributes set — the default SGR state.
pub const SGR_DEFAULT : Int = 0

///|
/// Map an SGR code to its flags. "Reset" codes (22/23/24/25/27/28/29/55)
/// carry the `SGR_RESET` mark so the caller can tell clear from set.
pub fn sgr_flags_from_code(code : Int) -> Int {
  match code {
    1 => SGR_BOLD
    2 => SGR_FAINT
    3 => SGR_ITALIC
    4 | 21 => SGR_UNDERLINE
    5 => SGR_BLINK
    6 => SGR_BLINK_RAPID
    7 => SGR_INVERSE
    8 => SGR_INVISIBLE
    9 => SGR_STRIKETHROUGH
    53 => SGR_OVERLINE
    // Reset codes: the flags to clear, marked with RESET.
    22 => SGR_BOLD | SGR_FAINT | SGR_RESET
    23 => SGR_ITALIC | SGR_RESET
    24 => SGR_UNDERLINE | SGR_RESET
    25 => SGR_BLINK | SGR_BLINK_RAPID | SGR_RESET
    27 => SGR_INVERSE | SGR_RESET
    28 => SGR_INVISIBLE | SGR_RESET
    29 => SGR_STRIKETHROUGH | SGR_RESET
    55 => SGR_OVERLINE | SGR_RESET
    _ => SGR_DEFAULT
  }
}

///|
/// Test whether `flags` contains `flag`.
pub fn sgr_flags_has(flags : Int, flag : Int) -> Bool {
  (flags & flag) != 0
}

///|
/// The decoration subset carried on a span/cell — the low five bits of the
/// SGR flags (underline/strikethrough/overline/bold/italic).
pub fn sgr_flags_decorations(flags : Int) -> Int {
  flags & 0x1f
}

// ── Style flags (the five decorations) ─────────────────────────────────

///|
/// SGR 4 underline.
pub const STYLE_UNDERLINE : Int = 1 << 0

///|
/// SGR 9 strikethrough.
pub const STYLE_STRIKETHROUGH : Int = 1 << 1

///|
/// SGR 53 overline.
pub const STYLE_OVERLINE : Int = 1 << 2

///|
/// SGR 1 bold.
pub const STYLE_BOLD : Int = 1 << 3

///|
/// SGR 3 italic.
pub const STYLE_ITALIC : Int = 1 << 4

// ── Underline style ────────────────────────────────────────────────────

///|
/// SGR underline style (`4:0..5` / SGR 21).
pub(all) enum UnderlineStyle {
  /// No underline (`SGR 24` / `4:0`).
  None
  /// A single underline (`SGR 4`).
  Single
  /// A double underline (`SGR 4:2` / `21`).
  Double
  /// A curly underline (`SGR 4:3`).
  Curly
  /// A dotted underline (`SGR 4:4`).
  Dotted
  /// A dashed underline (`SGR 4:5`).
  Dashed
} derive(Eq, Debug)

///|
pub extend UnderlineStyle with Eq::{equal, not_equal}

///|
pub extend UnderlineStyle with @debug.Debug::{to_repr}

///|
/// Map an SGR `4:<n>` sub-parameter to a style: `0` → `None`, `2..=5` → the
/// specific style, anything else → `Single` (the plain-`4` default).
pub fn UnderlineStyle::from_int(v : Int) -> UnderlineStyle {
  match v {
    0 => UnderlineStyle::None
    2 => UnderlineStyle::Double
    3 => UnderlineStyle::Curly
    4 => UnderlineStyle::Dotted
    5 => UnderlineStyle::Dashed
    _ => UnderlineStyle::Single
  }
}

// ── Cursor style (DECSCUSR) ────────────────────────────────────────────

///|
/// DECSCUSR cursor shape (`CSI Ps SP q`).
pub(all) enum CursorStyle {
  /// No cursor drawn (DECTCEM `CSI ?25l`, or an invalid DECSCUSR code).
  None
  /// Solid block covering the cell.
  Block
  /// Vertical bar (I-beam) at the left of the cell.
  Bar
  /// Horizontal underline at the bottom of the cell.
  Underline
} derive(Eq, Debug)

///|
pub extend CursorStyle with Eq::{equal, not_equal}

///|
pub extend CursorStyle with @debug.Debug::{to_repr}

///|
/// Map a DECSCUSR parameter to a shape; unsupported codes → `None` (the
/// caller leaves the cursor style unchanged).
pub fn CursorStyle::from_decscusr(param : Int) -> CursorStyle {
  match param {
    0..=2 => CursorStyle::Block
    3 | 4 => CursorStyle::Underline
    5 | 6 => CursorStyle::Bar
    _ => CursorStyle::None
  }
}

///|
/// Map an OSC 50 `CursorShape=N` parameter (0 = block, 1 = beam,
/// 2 = underline); unsupported codes → `None`.
pub fn CursorStyle::from_osc(param : Int) -> CursorStyle {
  match param {
    0 => CursorStyle::Block
    1 => CursorStyle::Bar
    2 => CursorStyle::Underline
    _ => CursorStyle::None
  }
}

///|
/// Parse a cursor-style name ("block"/"bar"/"underline"/"none"). Unknown → `Bar`.
pub fn CursorStyle::parse(name : String) -> CursorStyle {
  match name.trim().to_lower() {
    "block" => CursorStyle::Block
    "bar" | "beam" | "vertical" => CursorStyle::Bar
    "underline" | "underscore" => CursorStyle::Underline
    "none" | "off" | "hidden" => CursorStyle::None
    _ => CursorStyle::Bar
  }
}

// ── Parsed SGR effects ──────────────────────────────────────────────

///|
/// An unresolved SGR color (before palette interning).
pub(all) enum ColorSpec {
  /// 39/49 — restore the default fg/bg.
  Default
  /// 30..=37 / 90..=97 / 40..=47 / 100..=107 — the direct ANSI codes.
  Ansi(Int)
  /// `38;5;n` / `48;5;n` / `58;5;n` — the extended indexed color (already
  /// clamped to 0..=255).
  Indexed(Int)
  /// `38;2;r;g;b` etc. — truecolor, packed 0xRRGGBB.
  Rgb(Int)
} derive(Eq, Debug)

///|
pub extend ColorSpec with Eq::{equal, not_equal}

///|
pub extend ColorSpec with @debug.Debug::{to_repr}

///|
/// Pack a truecolor triplet into an RGB color (`0x00RRGGBB`).
pub fn ColorSpec::rgb(r : Int, g : Int, b : Int) -> ColorSpec {
  ColorSpec::Rgb(rgb(r, g, b))
}

///|
/// Clamp an indexed color to the 256-color table and wrap it.
pub fn ColorSpec::indexed(n : Int) -> ColorSpec {
  ColorSpec::Indexed(ColorId::from_i32(n).index())
}

///|
/// A single parsed SGR effect, in sequence order.
pub(all) enum SgrEffect {
  /// 0 — reset all attributes and colors.
  Reset
  /// Turn attribute flags ON (bold/faint/…).
  Set(Int)
  /// Turn attribute flags OFF.
  Clear(Int)
  /// 4 / 4:n / 21 — set the underline style (`None` clears it).
  Underline(UnderlineStyle)
  /// 30..=37 / 39 / 38;… / 90..=97 — foreground.
  Fg(ColorSpec)
  /// 40..=47 / 49 / 48;… / 100..=107 — background.
  Bg(ColorSpec)
  /// 58;… — underline color.
  UnderlineColor(ColorSpec)
  /// 59 — clear the underline color.
  ClearUnderlineColor
} derive(Eq, Debug)

///|
pub extend SgrEffect with Eq::{equal, not_equal}

///|
pub extend SgrEffect with @debug.Debug::{to_repr}

///|
/// A raw SGR (`CSI … m`) attribute sequence: the parameter values plus the
/// colon-separator bitfield (bit `i` = parameter `i` followed by `:`).
pub struct Sgr {
  params : Array[Int]
  sep : Int
} derive(Eq, Debug)

///|
pub extend Sgr with Eq::{equal, not_equal}

///|
pub extend Sgr with @debug.Debug::{to_repr}

///|
/// Build an SGR sequence from raw CSI dispatch parts.
pub fn Sgr::new(params : Array[Int], sep : Int) -> Sgr {
  { params, sep }
}

///|
/// Append the canonical `CSI … m` sequence to `out`, honouring the
/// colon-separator bitfield.
pub fn Sgr::write_bytes(self : Sgr, out : Array[Int]) -> Unit {
  append_utf8(out, "\u{1b}[")
  for i = 0; i < self.params.length(); i = i + 1 {
    if i > 0 {
      let colon = i - 1 < 16 && (self.sep & (1 << (i - 1))) != 0
      out.push(if colon { 0x3a } else { 0x3b })
    }
    append_decimal(out, self.params[i])
  }
  out.push(0x6d) // 'm'
}

///|
/// Whether parameter `i` was followed by a colon (bit `i` of `sep`).
fn colon_sep(sep : Int, i : Int) -> Bool {
  i < 16 && (sep & (1 << i)) != 0
}

///|
/// The effect of an extended color code (`38` fg / `48` bg / `58` underline).
fn extended_effect(code : Int, spec : ColorSpec) -> SgrEffect {
  match code {
    38 => SgrEffect::Fg(spec)
    48 => SgrEffect::Bg(spec)
    _ => SgrEffect::UnderlineColor(spec)
  }
}

///|
/// The effect of a single SGR attribute code.
pub fn single_code(code : Int) -> Option[SgrEffect] {
  match code {
    0 => Some(SgrEffect::Reset)
    4 => Some(SgrEffect::Underline(UnderlineStyle::Single))
    21 => Some(SgrEffect::Underline(UnderlineStyle::Double))
    30..=37 => Some(SgrEffect::Fg(ColorSpec::Ansi(code - 30)))
    39 => Some(SgrEffect::Fg(ColorSpec::Default))
    40..=47 => Some(SgrEffect::Bg(ColorSpec::Ansi(code - 40)))
    49 => Some(SgrEffect::Bg(ColorSpec::Default))
    59 => Some(SgrEffect::ClearUnderlineColor)
    90..=97 => Some(SgrEffect::Fg(ColorSpec::Ansi(code - 90 + 8)))
    100..=107 => Some(SgrEffect::Bg(ColorSpec::Ansi(code - 100 + 8)))
    _ => {
      let flags = sgr_flags_from_code(code)
      if flags == SGR_DEFAULT {
        return None
      }
      if sgr_flags_has(flags, SGR_RESET) {
        Some(SgrEffect::Clear(flags & SGR_RESET.lnot()))
      } else {
        Some(SgrEffect::Set(flags))
      }
    }
  }
}

///|
/// Parse an extended color (38/48/58): `X;5;n` / `X;2;r;g;b` and the colon
/// forms `X:5:n`, `X:2:r:g:b`, `X:2:cs:r:g:b` / `X:2::r:g:b` (the colorspace is
/// skipped). Returns `(spec, skip)` where `skip` is the number of params
/// AFTER `i` consumed.
pub fn parse_extended(
  params : ArrayView[Int],
  sep : Int,
  i : Int,
) -> Option[(ColorSpec, Int)] {
  let len = params.length()
  let colon = colon_sep(sep, i)
  // A colon after the `g` slot (i + 4) marks the colorspace form.
  let cs = colon && colon_sep(sep, i + 4)
  if i + 1 >= len {
    return None
  }
  match params[i + 1] {
    5 =>
      if len > i + 2 {
        Some((ColorSpec::indexed(params[i + 2]), 2))
      } else {
        None
      }
    2 => {
      let off = if cs { 1 } else { 0 }
      let need = i + 4 + off
      if len <= need {
        return None
      }
      Some(
        (
          ColorSpec::rgb(
            params[i + 2 + off],
            params[i + 3 + off],
            params[i + 4 + off],
          ),
          4 + off,
        ),
      )
    }
    _ => None
  }
}

///|
/// Parse an SGR sequence into its effects, appending to `out`. Colors stay
/// unresolved (`ColorSpec`) so each consumer interns them against its own
/// palette.
pub fn parse_effects(
  params : ArrayView[Int],
  sep : Int,
  out : Array[SgrEffect],
) -> Unit {
  if params.length() == 0 {
    out.push(SgrEffect::Reset)
    return
  }
  let mut i = 0
  while i < params.length() {
    let code = params[i]
    match code {
      4 => {
        let mut style = UnderlineStyle::Single
        if colon_sep(sep, i) && i + 1 < params.length() {
          style = UnderlineStyle::from_int(params[i + 1])
          i = i + 1
        }
        out.push(SgrEffect::Underline(style))
      }
      38 | 48 | 58 =>
        match parse_extended(params, sep, i) {
          Some((c, skip)) => {
            out.push(extended_effect(code, c))
            i = i + skip
          }
          None => ()
        }
      _ =>
        match single_code(code) {
          Some(e) => out.push(e)
          None => ()
        }
    }
    i = i + 1
  }
}

///|
/// The effect of the common single-color / single-attribute SGR forms,
/// avoiding the effects buffer + iteration on the per-cell redraw hot path.
/// Returns `None` for anything else (colon forms, multi-param sequences) —
/// the caller falls back to `parse_effects`.
pub fn single_effect(params : ArrayView[Int], sep : Int) -> Option[SgrEffect] {
  if sep != 0 {
    return None
  }
  let len = params.length()
  let code = params[0]
  if len == 5 && (code == 38 || code == 48 || code == 58) && params[1] == 2 {
    return Some(
      extended_effect(code, ColorSpec::rgb(params[2], params[3], params[4])),
    )
  }
  if len == 3 && (code == 38 || code == 48 || code == 58) && params[1] == 5 {
    return Some(extended_effect(code, ColorSpec::indexed(params[2])))
  }
  if len == 1 {
    return single_code(code)
  }
  None
}
