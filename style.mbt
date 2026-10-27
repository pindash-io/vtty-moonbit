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
