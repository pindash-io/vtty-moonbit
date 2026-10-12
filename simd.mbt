// SIMD-accelerated byte-scan and UTF-8 decode helpers for the parser hot path
// (via `@v128`, MoonBit's 128-bit SIMD intrinsics).

///| Index of the first byte that is NOT printable ASCII (`0x20..=0x7e`; DEL

///|
/// `0x7f` is a C0 control), or `bytes.length()` if every byte is printable.
pub fn first_non_printable(bytes : ArrayView[Int]) -> Int {
  // Fast path: the next byte is usually the match on escape-dense streams.
  if bytes.length() > 0 {
    let b0 = bytes[0]
    if !(b0 >= 0x20 && b0 <= 0x7e) {
      return 0
    }
  }
  let n = bytes.length()
  let mut offset = 0
  while offset + 16 <= n {
    let v = load16(bytes, offset)
    // b < 0x20 (control) or b >= 0x7f (DEL + high-bit).
    let special = @v128.v128_or_(
      @v128.i8x16_lt_u(v, @v128.i8x16_splat(0x20)),
      @v128.i8x16_ge_u(v, @v128.i8x16_splat(0x7f)),
    )
    if @v128.v128_any_true(special) {
      let mask = @v128.i8x16_bitmask(special)
      return offset + first_set(mask)
    }
    offset = offset + 16
  }
  // Scalar tail (< 16 bytes).
  while offset < n {
    let b = bytes[offset]
    if !(b >= 0x20 && b <= 0x7e) {
      return offset
    }
    offset = offset + 1
  }
  n
}

///|
/// Index of the first ESC byte (`0x1b`), or `bytes.length()` if none.
pub fn first_esc(bytes : ArrayView[Int]) -> Int {
  let n = bytes.length()
  let mut offset = 0
  while offset + 16 <= n {
    let v = load16(bytes, offset)
    let special = @v128.i8x16_eq(v, @v128.i8x16_splat(0x1b))
    if @v128.v128_any_true(special) {
      let mask = @v128.i8x16_bitmask(special)
      return offset + first_set(mask)
    }
    offset = offset + 16
  }
  while offset < n {
    if bytes[offset] == 0x1b {
      return offset
    }
    offset = offset + 1
  }
  n
}

///| Branchless decode of a UTF-8 code point already validated by the caller.

///| Assumes `b[0]` is a 2/3/4-byte lead with its continuation bytes present.

///|
/// Returns `(code_point, byte_length)`.
pub fn decode_validated(b : ArrayView[Int], pos : Int) -> (Int, Int) {
  let b0 = b[pos]
  match b0 {
    0xc2..=0xdf => (((b0 & 0x1f) << 6) | (b[pos + 1] & 0x3f), 2)
    0xe0..=0xef =>
      (
        ((b0 & 0x0f) << 12) | ((b[pos + 1] & 0x3f) << 6) | (b[pos + 2] & 0x3f),
        3,
      )
    _ =>
      (
        ((b0 & 0x07) << 18) |
        ((b[pos + 1] & 0x3f) << 12) |
        ((b[pos + 2] & 0x3f) << 6) |
        (b[pos + 3] & 0x3f),
        4,
      )
  }
}

///|
/// Load 16 bytes from `bytes` at `offset` into a `V128`.
fn load16(bytes : ArrayView[Int], offset : Int) -> V128 {
  @v128.i8x16_const(
    bytes[offset].to_byte(),
    bytes[offset + 1].to_byte(),
    bytes[offset + 2].to_byte(),
    bytes[offset + 3].to_byte(),
    bytes[offset + 4].to_byte(),
    bytes[offset + 5].to_byte(),
    bytes[offset + 6].to_byte(),
    bytes[offset + 7].to_byte(),
    bytes[offset + 8].to_byte(),
    bytes[offset + 9].to_byte(),
    bytes[offset + 10].to_byte(),
    bytes[offset + 11].to_byte(),
    bytes[offset + 12].to_byte(),
    bytes[offset + 13].to_byte(),
    bytes[offset + 14].to_byte(),
    bytes[offset + 15].to_byte(),
  )
}

///|
/// Index of the first non-zero lane in a 16-bit mask.
fn first_set(mask : Int) -> Int {
  for j = 0; j < 16; j = j + 1 {
    if (mask & (1 << j)) != 0 {
      return j
    }
  }
  16
}
