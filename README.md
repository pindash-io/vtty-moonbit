# vtty (MoonBit port)

A byte-input DEC VT500 terminal parser with UTF-8 decoding — a port of the
core `vtty` Rust crate to MoonBit (scalar path).

## What is ported

- **DEC VT500 state machine** (`table.mbt`) — all 14 parser states and the
  `transition` lookup, including the `c1_transition` / `c1_in_sequence`
  "anywhere" rule for 8-bit C1 controls.
- **`Perform` sink trait** (`perform.mbt`) — print / print_bytes /
  print_codepoints / execute / csi_dispatch / esc_dispatch / hook / put /
  put_slice / unhook / osc_dispatch, all with no-op defaults.
- **Owned event API** (`event.mbt`) — `Event` + `Recording`.
- **UTF-8** (`utf8.mbt`, scalar in `parser.mbt`) — W3C "Substitution of
  Maximal Subparts": each invalid maximal subpart becomes one `U+FFFD`, a
  standalone C1 byte keeps `execute` semantics, and code points split across
  `advance` calls are carried over as a partial.
- **`Parser`** (`parser.mbt`) — zero-allocation dispatch to a `Perform` sink.
- **SIMD byte scans** (`simd.mbt`) — `first_non_printable` / `first_esc` via
  `@v128` (i8x16 comparisons + bitmask), plus branchless `decode_validated`.
  Opt in with `Parser::with_simd()`.

## Not ported (yet)

- SIMD UTF-8 window validation (`simdutf8` equivalent), `vtty_emoji` (ICU4X),
  `vtty_ffi` (C ABI), and the benchmark harness.

## Usage

```moonbit
let rec = @vtty.Recording::new()
let p = @vtty.Parser::new() // or Parser::with_simd() for the SIMD fast path
let input : Array[Int] = [0x1b, 0x5b, 0x31, 0x3b, 0x33, 0x31, 0x6d] // CSI 1;31m
p.advance(rec, input[:])
inspect(rec.events())
```

## Terminal example

`cmd/term` is an interactive minimal terminal emulator: it spawns a real shell
on a PTY (via `moonbit-community/pty`), puts stdin into raw mode (via
`moonbit-community/tty`), forwards keystrokes to the shell, and feeds the
shell's output through the parser into an 80×24 screen sink (cursor tracking,
`CSI … H`/`A`/`B`/`C`/`D`, `ED`, OSC title) that redraws on every chunk.
Ctrl-D ends the session.

```bash
moon run --target native cmd/term   # interactive (native only)
# or pipe a session:
printf 'ls\nexit\n' | moon run --target native cmd/term
```

## Test

```bash
moon test
moon check
```
