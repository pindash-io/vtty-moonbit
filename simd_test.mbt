///|
/// Black-box tests for the SIMD byte-scan helpers and `Parser::with_simd`.
test "first_non_printable" {
  // All printable → length.
  let printable : Array[Int] = [0x20, 0x41, 0x42, 0x7e, 0x20]
  assert_eq(@vtty.first_non_printable(printable[:]), 5)
  // ESC at index 2.
  let esc : Array[Int] = [0x41, 0x42, 0x1b, 0x41]
  assert_eq(@vtty.first_non_printable(esc[:]), 2)
  // DEL (0x7f) is non-printable.
  let del : Array[Int] = [0x41, 0x7f, 0x42]
  assert_eq(@vtty.first_non_printable(del[:]), 1)
  // High-bit lead at index 0.
  let high : Array[Int] = [0xe6, 0x97, 0xa5]
  assert_eq(@vtty.first_non_printable(high[:]), 0)
}

///|
test "first_non_printable across a 16-byte chunk" {
  // 20 printable bytes, then ESC — exercises the SIMD chunk loop + tail.
  let bytes : Array[Int] = []
  for i in 0..<20 {
    bytes.push(0x41)
  }
  bytes.push(0x1b)
  assert_eq(@vtty.first_non_printable(bytes[:]), 20)
}

///|
test "first_esc" {
  let bytes : Array[Int] = [0x41, 0x42, 0x43, 0x1b, 0x5b]
  assert_eq(@vtty.first_esc(bytes[:]), 3)
  let no_esc : Array[Int] = [0x41, 0x42, 0x43]
  assert_eq(@vtty.first_esc(no_esc[:]), 3)
}

///|
test "decode_validated" {
  // "日" = E6 97 A5 → U+65E5, 3 bytes.
  let r : Array[Int] = [0xe6, 0x97, 0xa5, 0x00]
  assert_eq(@vtty.decode_validated(r[:], 0), (0x65e5, 3))
  // 2-byte "é" = C3 A9 → U+00E9.
  let r2 : Array[Int] = [0xc3, 0xa9, 0x00]
  assert_eq(@vtty.decode_validated(r2[:], 0), (0xe9, 2))
  // 4-byte "🚀" = F0 9F 9A 80 → U+1F680.
  let r4 : Array[Int] = [0xf0, 0x9f, 0x9a, 0x80, 0x00]
  assert_eq(@vtty.decode_validated(r4[:], 0), (0x1f680, 4))
}

///|
test "with_simd matches scalar parser" {
  let input : Array[Int] = [
    0x68, 0x69, 0x20, 0x1b, 0x5b, 0x31, 0x6d, 0xe6, 0x97, 0xa5,
  ]
  let rec_scalar = @vtty.Recording::new()
  @vtty.Parser::new().advance(rec_scalar, input[:])
  let rec_simd = @vtty.Recording::new()
  @vtty.Parser::with_simd().advance(rec_simd, input[:])
  assert_eq(rec_simd.events(), rec_scalar.events())
}
