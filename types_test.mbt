///|
/// Black-box tests for the terminal model types (color, style, charset,
/// keyboard, mode, mouse).
test "color id" {
  let c = @vtty.ColorId::from_int(42)
  assert_eq(c.index(), 42)
  // SGR indexed colors clamp to 0..=255.
  assert_eq(@vtty.ColorId::from_i32(-1).index(), 0)
  assert_eq(@vtty.ColorId::from_i32(300).index(), 255)
  assert_eq(@vtty.ColorId::from_i32(7).index(), 7)
  // Default fg/bg are reserved palette indices.
  assert_eq(@vtty.default_fg_id().index(), 256)
  assert_eq(@vtty.default_bg_id().index(), 257)
}

///|
test "sgr flags" {
  assert_eq(@vtty.sgr_flags_from_code(1), @vtty.SGR_BOLD)
  assert_eq(@vtty.sgr_flags_from_code(4), @vtty.SGR_UNDERLINE)
  assert_eq(@vtty.sgr_flags_from_code(21), @vtty.SGR_UNDERLINE)
  // Reset codes carry the RESET mark plus the flags to clear.
  assert_eq(
    @vtty.sgr_flags_from_code(22),
    @vtty.SGR_BOLD | @vtty.SGR_FAINT | @vtty.SGR_RESET,
  )
  assert_eq(@vtty.sgr_flags_from_code(99), @vtty.SGR_DEFAULT)
  assert_eq(
    @vtty.sgr_flags_has(@vtty.SGR_BOLD | @vtty.SGR_ITALIC, @vtty.SGR_BOLD),
    true,
  )
  assert_eq(
    @vtty.sgr_flags_has(@vtty.SGR_BOLD, @vtty.SGR_ITALIC),
    false,
  )
  // Decorations keep only the low five bits.
  assert_eq(@vtty.sgr_flags_decorations(@vtty.SGR_BOLD), @vtty.STYLE_BOLD)
  assert_eq(
    @vtty.sgr_flags_decorations(@vtty.SGR_BOLD | @vtty.SGR_RESET),
    @vtty.STYLE_BOLD,
  )
}

///|
test "underline and cursor style" {
  assert_eq(@vtty.UnderlineStyle::from_int(0), @vtty.UnderlineStyle::None)
  assert_eq(@vtty.UnderlineStyle::from_int(1), @vtty.UnderlineStyle::Single)
  assert_eq(@vtty.UnderlineStyle::from_int(2), @vtty.UnderlineStyle::Double)
  assert_eq(@vtty.UnderlineStyle::from_int(3), @vtty.UnderlineStyle::Curly)
  assert_eq(@vtty.UnderlineStyle::from_int(4), @vtty.UnderlineStyle::Dotted)
  assert_eq(@vtty.UnderlineStyle::from_int(5), @vtty.UnderlineStyle::Dashed)

  assert_eq(@vtty.CursorStyle::from_decscusr(0), @vtty.CursorStyle::Block)
  assert_eq(@vtty.CursorStyle::from_decscusr(3), @vtty.CursorStyle::Underline)
  assert_eq(@vtty.CursorStyle::from_decscusr(5), @vtty.CursorStyle::Bar)
  assert_eq(@vtty.CursorStyle::from_decscusr(7), @vtty.CursorStyle::None)
  assert_eq(@vtty.CursorStyle::from_osc(0), @vtty.CursorStyle::Block)
  assert_eq(@vtty.CursorStyle::from_osc(2), @vtty.CursorStyle::Underline)
  assert_eq(@vtty.CursorStyle::parse("block"), @vtty.CursorStyle::Block)
  assert_eq(@vtty.CursorStyle::parse("BAR"), @vtty.CursorStyle::Bar)
  assert_eq(@vtty.CursorStyle::parse("none"), @vtty.CursorStyle::None)
  assert_eq(@vtty.CursorStyle::parse("garbage"), @vtty.CursorStyle::Bar)
}

///|
test "charset map and slots" {
  assert_eq(@vtty.Charset::Ascii.map('q'), 'q')
  // DEC Special Graphics: 'q' → '─' (line drawing).
  assert_eq(@vtty.Charset::Dec.map('q'), '─')
  assert_eq(@vtty.Charset::Dec.map('A'), 'A')
  // British: '#' → '£'.
  assert_eq(@vtty.Charset::British.map('#'), '£')
  assert_eq(@vtty.Charset::British.map('A'), 'A')

  let sets = @vtty.Charsets::ascii()
  assert_eq(sets.g0(), @vtty.Charset::Ascii)
  assert_eq(sets.g3(), @vtty.Charset::Ascii)
  sets.designate(1, @vtty.Charset::Dec)
  assert_eq(sets.g1(), @vtty.Charset::Dec)
  assert_eq(sets.get(1), @vtty.Charset::Dec)
  // Out-of-range designation clamps to G3.
  sets.designate(9, @vtty.Charset::British)
  assert_eq(sets.g3(), @vtty.Charset::British)
}

///|
test "kitty flags" {
  assert_eq(@vtty.KITTY_DISAMBIGUATE, 1)
  assert_eq(@vtty.KITTY_REPORT_ALL_KEYS, 8)
  assert_eq(
    @vtty.kitty_flags_has(3, @vtty.KITTY_DISAMBIGUATE),
    true,
  )
  assert_eq(
    @vtty.kitty_flags_has(3, @vtty.KITTY_REPORT_EVENT_TYPES),
    true,
  )
  assert_eq(
    @vtty.kitty_flags_has(3, @vtty.KITTY_REPORT_ALTERNATE_KEYS),
    false,
  )
}

///|
test "term flags mode mapping" {
  // ANSI modes.
  assert_eq(@vtty.term_flags_from_mode_code(4, false), @vtty.TERM_INSERT)
  assert_eq(@vtty.term_flags_from_mode_code(20, false), @vtty.TERM_LINEFEED)
  // DEC private modes.
  assert_eq(
    @vtty.term_flags_from_private_param(1),
    @vtty.TERM_CURSOR_KEYS,
  )
  assert_eq(
    @vtty.term_flags_from_private_param(1049),
    @vtty.TERM_ALT_SCREEN_1049,
  )
  assert_eq(
    @vtty.term_flags_from_private_param(2004),
    @vtty.TERM_BRACKETED_PASTE,
  )
  assert_eq(
    @vtty.term_flags_from_private_param(9999),
    @vtty.TERM_NONE,
  )
  // Round-trip flag → private param.
  assert_eq(@vtty.term_flags_private_param(@vtty.TERM_CURSOR_KEYS), 1)
  assert_eq(@vtty.term_flags_private_param(@vtty.TERM_ALT_SCREEN_1049), 1049)
  assert_eq(@vtty.term_flags_private_param(@vtty.TERM_BRACKETED_PASTE), 2004)
  // Any-code lookup falls back to the private table.
  assert_eq(@vtty.term_flags_from_any_mode_code(4), @vtty.TERM_INSERT)
  assert_eq(@vtty.term_flags_from_any_mode_code(1049), @vtty.TERM_ALT_SCREEN_1049)
  // MOUSE_MASK covers the mouse-tracking modes.
  assert_eq(
    @vtty.term_flags_has(@vtty.MOUSE_MASK, @vtty.TERM_MOUSE_SGR),
    true,
  )
}

///|
test "mouse button codes" {
  assert_eq(@vtty.MouseButton::Left.code(), 0)
  assert_eq(@vtty.MouseButton::Middle.code(), 1)
  assert_eq(@vtty.MouseButton::Right.code(), 2)
  assert_eq(@vtty.MouseButton::Release.code(), 3)
  assert_eq(@vtty.MouseButton::Motion.code(), 32)
  assert_eq(@vtty.MouseButton::MotionNoButton.code(), 35)
  assert_eq(@vtty.MouseButton::WheelUp.code(), 64)
  assert_eq(@vtty.MouseButton::WheelDown.code(), 65)
  assert_eq(@vtty.MouseButton::WheelLeft.code(), 66)
  assert_eq(@vtty.MouseButton::WheelRight.code(), 67)
}

///|
test "mouse encoding" {
  // SGR: ESC [ < 0 ; 1 ; 1 M
  assert_eq(
    @vtty.MouseButton::Left.encode_sgr(0, 0, true),
    [0x1b, 0x5b, 0x3c, 0x30, 0x3b, 0x31, 0x3b, 0x31, 0x4d],
  )
  // X10: ESC [ M 32 33 33
  assert_eq(
    @vtty.MouseButton::Left.encode_x10(0, 0),
    [0x1b, 0x5b, 0x4d, 32, 33, 33],
  )
  // UTF-8: ESC [ M 0x20 0x21 0x21
  assert_eq(
    @vtty.MouseButton::Left.encode_utf8(0, 0),
    [0x1b, 0x5b, 0x4d, 0x20, 0x21, 0x21],
  )
  // Tracking disabled → None.
  assert_eq(@vtty.MouseButton::Left.encode(@vtty.MOUSE_DEFAULT, 0, 0, true), None)
  // X10 reports only presses.
  assert_eq(
    @vtty.MouseButton::Left.encode(@vtty.MOUSE_ENABLED | @vtty.MOUSE_X10, 0, 0, false),
    None,
  )
  // SGR protocol.
  assert_eq(
    @vtty.MouseButton::Left.encode(@vtty.MOUSE_ENABLED | @vtty.MOUSE_SGR, 0, 0, true),
    Some([0x1b, 0x5b, 0x3c, 0x30, 0x3b, 0x31, 0x3b, 0x31, 0x4d]),
  )
  // Plain X10 (press).
  assert_eq(
    @vtty.MouseButton::Left.encode(@vtty.MOUSE_ENABLED, 0, 0, true),
    Some([0x1b, 0x5b, 0x4d, 32, 33, 33]),
  )
  // X10 coordinates ≥ 223 are dropped.
  assert_eq(
    @vtty.MouseButton::Left.encode(@vtty.MOUSE_ENABLED, 223, 0, true),
    None,
  )
}
