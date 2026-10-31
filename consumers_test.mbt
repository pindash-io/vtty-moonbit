///|
/// Tests for the Perform-sink and reply-building consumers: `State`, `Reply`,
/// `Cap`, and `ProgramStatus`.

///|
/// Encode a `String` to an `Array[Int]` of UTF-8 bytes.
fn bytes(s : String) -> Array[Int] {
  let out : Array[Int] = []
  for b in @utf8.encode(s).iter() {
    out.push(b.to_int())
  }
  out
}

///|
/// Drive a parser into a fresh `State` and return it.
fn drive(b : Array[Int]) -> @vtty.State {
  let p = @vtty.Parser::new()
  let s = @vtty.State::new()
  p.advance(s, b[:])
  s
}

///|
test "state empty" {
  let s = @vtty.State::new()
  assert_eq(s.line_count(), 0)
  assert_eq(s.cursor_row(), 0)
  assert_eq(s.cursor_col(), 0)
  assert_eq(s.line_range(0), None)
}

///|
test "state line and cursor geometry" {
  let s = drive(bytes("hello\nworld"))
  assert_eq(s.text(), "hello\nworld")
  assert_eq(s.line_count(), 2)
  assert_eq(s.cursor_row(), 1)
  assert_eq(s.cursor_col(), 5)
  assert_eq(s.line_range(0), Some((0, 5)))
  assert_eq(s.line_range(1), Some((6, 11)))
  assert_eq(s.line_range(2), None)
}

///|
test "state trailing newline counts as empty line" {
  let s = drive(bytes("a\n"))
  assert_eq(s.line_count(), 2)
  assert_eq(s.line_range(0), Some((0, 1)))
  assert_eq(s.line_range(1), Some((2, 2)))
  assert_eq(s.line_range(2), None)
}

///|
test "state crlf is one line break" {
  let s = drive(bytes("a\r\nb"))
  assert_eq(s.text(), "a\nb")
  assert_eq(s.line_count(), 2)
  assert_eq(s.cursor_row(), 1)
  assert_eq(s.cursor_col(), 1)
}

///|
test "state cr resets column without advancing line" {
  let s = drive(bytes("ab\r"))
  assert_eq(s.text(), "ab")
  assert_eq(s.line_count(), 1)
  assert_eq(s.cursor_row(), 0)
  assert_eq(s.cursor_col(), 0)
}

///|
test "state line range uses byte offsets" {
  let s = drive(bytes("中a\nb"))
  assert_eq(s.line_range(0), Some((0, 4)))
  assert_eq(s.line_range(1), Some((5, 6)))
}

///|
test "reply decrqss" {
  let r = @vtty.Reply::decrqss(true, "value")
  assert_eq(r, "\u{1b}P1$rvalue\u{1b}\\")
  let r2 = @vtty.Reply::decrqss(false, "x")
  assert_eq(r2, "\u{1b}P0$rx\u{1b}\\")
}

///|
test "reply xtgettcap" {
  // hex("RGB") = 524742, hex("8/8/8") = 382f382f38
  let r = @vtty.Reply::xtgettcap_reply("RGB", "8/8/8")
  assert_eq(r, "\u{1b}P1+r524742=382f382f38\u{1b}\\")
  // Boolean: bare key.
  let b = @vtty.Reply::xtgettcap_reply_bool("Tc")
  assert_eq(b, "\u{1b}P1+r5463\u{1b}\\")
  // Numeric: hex("co") = 636f, hex("80") = 3830.
  let n = @vtty.Reply::xtgettcap_num("co", 80)
  assert_eq(n, "\u{1b}P1+r636f=3830\u{1b}\\")
  // Error.
  let e = @vtty.Reply::xtgettcap_error("unsupported")
  assert_eq(e, "\u{1b}P0+r756e737570706f72746564\u{1b}\\")
}

///|
test "reply decrqm" {
  let r = @vtty.Reply::decrqm(1049, true, 1)
  assert_eq(r, "\u{1b}[?1049;1$y")
  let r2 = @vtty.Reply::decrqm(4, false, 0)
  assert_eq(r2, "\u{1b}[4;0$y")
}

///|
test "reply sgr" {
  let no_palette : Array[Int] = []
  let r = @vtty.Reply::sgr(
    @vtty.default_fg_id(),
    @vtty.default_bg_id(),
    @vtty.SGR_BOLD,
    no_palette[:],
  )
  assert_eq(r, "0;1;39;49")
}

///|
test "termcap parse" {
  let (k, v) = @vtty.cap_parse("RGB")
  assert_eq(k, "RGB")
  assert_eq(v, @vtty.CapValue::Text("8/8/8"))
  let (k2, v2) = @vtty.cap_parse("Tc")
  assert_eq(k2, "Tc")
  assert_eq(v2, @vtty.CapValue::Bool)
  let (k3, v3) = @vtty.cap_parse("co")
  assert_eq(k3, "co")
  assert_eq(v3, @vtty.CapValue::Cols)
  let (k4, v4) = @vtty.cap_parse("bogus")
  assert_eq(k4, "")
  assert_eq(v4, @vtty.CapValue::None)
}

///|
test "reply termcap multi-cap" {
  // "co" → 636f=3830 (cols=80), "RGB" → 524742=382f382f38.
  let r = @vtty.Reply::termcap("co;RGB", 80, 24, "jetfish")
  assert_eq(
    r,
    "\u{1b}P1+r636f=3830\u{1b}\\\u{1b}P1+r524742=382f382f38\u{1b}\\",
  )
}

///|
test "status parse minimal" {
  let s = @vtty.ProgramStatus::parse(bytes("state=working")[:]).unwrap()
  assert_eq(s.state, @vtty.StatusState::Working)
  assert_eq(s.id, None)
  assert_eq(s.kind, None)
  assert_eq(s.progress, None)
  assert_eq(s.app, None)
  assert_eq(s.title, None)
  assert_eq(s.msg, None)
}

///|
test "status parse full" {
  let s = @vtty.ProgramStatus::parse(
    bytes("state=blocked:kind=permission:id=build/test:progress=40:app=terraform:title=SGVsbG8=:msg=QXBwcm92ZQ==")[:],
  ).unwrap()
  assert_eq(s.state, @vtty.StatusState::Blocked)
  assert_eq(s.kind, Some(@vtty.StatusKind::Permission))
  assert_eq(s.id, Some("build/test"))
  assert_eq(s.progress, Some(40))
  assert_eq(s.app, Some("terraform"))
  assert_eq(s.title, Some("Hello"))
  assert_eq(s.msg, Some("Approve"))
}

///|
test "status parse invalid" {
  // Missing state.
  assert_eq(@vtty.ProgramStatus::parse(bytes("app=brew")[:]), None)
  // Invalid state.
  assert_eq(@vtty.ProgramStatus::parse(bytes("state=bogus")[:]), None)
  // Kind ignored without blocked.
  let s = @vtty.ProgramStatus::parse(bytes("state=working:kind=auth")[:]).unwrap()
  assert_eq(s.kind, None)
  // Progress out of range.
  let s2 = @vtty.ProgramStatus::parse(bytes("state=working:progress=101")[:]).unwrap()
  assert_eq(s2.progress, None)
  // Invalid id discards the report.
  assert_eq(@vtty.ProgramStatus::parse(bytes("state=working:id=a//b")[:]), None)
}

///|
test "status write osc roundtrip" {
  let status = @vtty.ProgramStatus::new(
    @vtty.StatusState::Working,
    Some("build/test"),
    None,
    Some(40),
    Some("terraform"),
    Some("US East"),
    Some("Deploying v2"),
  )
  let osc = status.to_osc()
  // Strip the 7-byte `ESC ] 7501 ;` prefix and the 2-byte ST.
  let body = osc[7:osc.length() - 2]
  let parsed = @vtty.ProgramStatus::parse(body[:]).unwrap()
  assert_eq(parsed.state, @vtty.StatusState::Working)
  assert_eq(parsed.id, Some("build/test"))
  assert_eq(parsed.progress, Some(40))
  assert_eq(parsed.app, Some("terraform"))
  assert_eq(parsed.title, Some("US East"))
  assert_eq(parsed.msg, Some("Deploying v2"))
}

///|
test "status from osc params" {
  let params : Array[Array[Int]] = [bytes("7501"), bytes("state=idle")]
  let s = @vtty.ProgramStatus::from_osc_params(params).unwrap()
  assert_eq(s.state, @vtty.StatusState::Idle)
  let bad : Array[Array[Int]] = [bytes("9999"), bytes("state=idle")]
  assert_eq(@vtty.ProgramStatus::from_osc_params(bad), None)
}

///|
test "termcap tn from host and osc replies" {
  // TN / name now maps to the host-supplied terminal name.
  let (k, v) = @vtty.cap_parse("TN")
  assert_eq(k, "TN")
  assert_eq(v, @vtty.CapValue::Tn)
  let r = @vtty.Reply::termcap("TN", 80, 24, "jetfish")
  assert_eq(r, "\u{1b}P1+r544e=6a657466697368\u{1b}\\")
  // OSC color / palette replies.
  assert_eq(
    @vtty.Reply::osc_color(10, 0x112233),
    "\u{1b}]10;rgb:1111/2222/3333\u{1b}\\",
  )
  assert_eq(
    @vtty.Reply::osc_palette(4, 0x112233),
    "\u{1b}]4;4;rgb:1111/2222/3333\u{1b}\\",
  )
}

///|
test "event write_bytes roundtrips through the parser" {
  // CSI with a private marker and params.
  let out : Array[Int] = []
  @vtty.Event::CsiDispatch([25], 0, [0x3f], 0x68).write_bytes(out)
  assert_eq(out, [0x1b, 0x5b, 0x3f, 0x32, 0x35, 0x68])
  // OSC ST-terminated.
  let out2 : Array[Int] = []
  @vtty.Event::OscDispatch([[0x30], [0x74]], false).write_bytes(out2)
  assert_eq(out2, [0x1b, 0x5d, 0x30, 0x3b, 0x74, 0x1b, 0x5c])
}

///|
test "recording replay forwards every event" {
  let rec = @vtty.Recording::new()
  rec.print_char('A')
  rec.print_ascii([0x62, 0x63][:])
  rec.control(0x0a)
  rec.csi([1, 31][:], 0, [][:], 0x6d)
  let target = @vtty.Recording::new()
  rec.replay(target)
  assert_eq(target.events(), rec.events())
  assert_eq(rec.is_empty(), false)
  assert_eq(rec.len(), 4)
}
