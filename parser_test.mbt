///|
/// Black-box tests for the DEC VT500 parser (scalar path).
test "ascii print run" {
  let rec = @vtty.Recording::new()
  let p = @vtty.Parser::new()
  let input : Array[Int] = [0x68, 0x65, 0x6c, 0x6c, 0x6f] // "hello"
  p.advance(rec, input[:])
  assert_eq(rec.events(), [
    @vtty.Event::Print('h'),
    @vtty.Event::Print('e'),
    @vtty.Event::Print('l'),
    @vtty.Event::Print('l'),
    @vtty.Event::Print('o'),
  ])
}

///|
test "csi dispatch with params" {
  let rec = @vtty.Recording::new()
  let p = @vtty.Parser::new()
  // ESC [ 1 ; 31 m
  let input : Array[Int] = [0x1b, 0x5b, 0x31, 0x3b, 0x33, 0x31, 0x6d]
  p.advance(rec, input[:])
  assert_eq(rec.events(), [@vtty.Event::CsiDispatch([1, 31], [], 0x6d)])
}

///|
test "csi private marker and intermediate" {
  let rec = @vtty.Recording::new()
  let p = @vtty.Parser::new()
  // ESC [ ? 1 h
  let input : Array[Int] = [0x1b, 0x5b, 0x3f, 0x31, 0x68]
  p.advance(rec, input[:])
  assert_eq(rec.events(), [@vtty.Event::CsiDispatch([1], [0x3f], 0x68)])
}

///|
test "esc dispatch" {
  let rec = @vtty.Recording::new()
  let p = @vtty.Parser::new()
  // ESC ( 0
  let input : Array[Int] = [0x1b, 0x28, 0x30]
  p.advance(rec, input[:])
  assert_eq(rec.events(), [@vtty.Event::EscDispatch([0x28], 0x30)])
}

///|
test "osc dispatch" {
  let rec = @vtty.Recording::new()
  let p = @vtty.Parser::new()
  // ESC ] 0 ; title BEL
  let input : Array[Int] = [
    0x1b, 0x5d, 0x30, 0x3b, 0x74, 0x69, 0x74, 0x6c, 0x65, 0x07,
  ]
  p.advance(rec, input[:])
  assert_eq(rec.events(), [
    @vtty.Event::OscDispatch([[0x30], [0x74, 0x69, 0x74, 0x6c, 0x65]], true),
  ])
}

///|
test "dcs hook put unhook" {
  let rec = @vtty.Recording::new()
  let p = @vtty.Parser::new()
  // ESC P 1 ; 2 q "abc" ESC \
  let input : Array[Int] = [
    0x1b, 0x50, 0x31, 0x3b, 0x32, 0x71, 0x61, 0x62, 0x63, 0x1b, 0x5c,
  ]
  p.advance(rec, input[:])
  assert_eq(rec.events(), [
    @vtty.Event::DcsHook([1, 2], [], 0x71),
    @vtty.Event::DcsPut(0x61),
    @vtty.Event::DcsPut(0x62),
    @vtty.Event::DcsPut(0x63),
    @vtty.Event::DcsUnhook,
    @vtty.Event::EscDispatch([], 0x5c),
  ])
}

///|
test "utf8 valid and malformed" {
  let rec = @vtty.Recording::new()
  let p = @vtty.Parser::new()
  // "日" (E6 97 A5) then a truncated lead (E6 9C) then 'A'
  let input : Array[Int] = [0xe6, 0x97, 0xa5, 0xe6, 0x9c, 0x41]
  p.advance(rec, input[:])
  assert_eq(rec.events(), [
    @vtty.Event::Print('日'),
    @vtty.Event::Print('\u{FFFD}'),
    @vtty.Event::Print('A'),
  ])
}

///|
test "utf8 split across calls" {
  let rec = @vtty.Recording::new()
  let p = @vtty.Parser::new()
  // "日" split: E6 97 | A5
  p.advance(rec, [0xe6, 0x97][:])
  p.advance(rec, [0xa5][:])
  assert_eq(rec.events(), [@vtty.Event::Print('日')])
}

///|
test "parse_events convenience" {
  let events = @vtty.Parser::new().parse_events([0x1b, 0x5b, 0x31, 0x6d][:])
  assert_eq(events, [@vtty.Event::CsiDispatch([1], [], 0x6d)])
}

///|
test "dcs put_slice bulk run" {
  let rec = @vtty.Recording::new()
  let p = @vtty.Parser::new()
  // ESC P q + 20 payload bytes + ESC \
  let input : Array[Int] = [0x1b, 0x50, 0x71]
  for _ in 0..<20 {
    input.push(0x61)
  }
  input.push(0x1b)
  input.push(0x5c)
  p.advance(rec, input[:])
  let expected = [@vtty.Event::DcsHook([], [], 0x71)]
  for _ in 0..<20 {
    expected.push(@vtty.Event::DcsPut(0x61))
  }
  expected.push(@vtty.Event::DcsUnhook)
  expected.push(@vtty.Event::EscDispatch([], 0x5c))
  assert_eq(rec.events(), expected)
}

///|
test "first_dcs_boundary" {
  // 0x19 is a PUT byte (not a boundary); 0x7f stops the run.
  let bytes : Array[Int] = [0x41, 0x19, 0x42, 0x7f, 0x43]
  assert_eq(@vtty.first_dcs_boundary(bytes[:]), 3)
  // CAN/SUB/ESC/high bytes are boundaries; all-PUT input scans to the end.
  let all_put : Array[Int] = [0x00, 0x17, 0x19, 0x1c, 0x7e]
  assert_eq(@vtty.first_dcs_boundary(all_put[:]), 5)
}
