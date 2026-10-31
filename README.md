# vtty (MoonBit port)

A byte-input DEC VT500 terminal parser with UTF-8 decoding — a MoonBit port of
the core `vtty` Rust crate.

## Ported

- **DEC VT500 state machine** (`table.mbt`) — all 14 parser states, the
  `transition` lookup, and the `c1_transition` "anywhere" rule for 8-bit C1
  controls (a C1 control cancels an OSC/DCS string and fires its exit action).
- **`Perform` sink trait** (`perform.mbt`) — `print` / `print_bytes` /
  `print_codepoints` / `execute` / `print_line` / `print_crlf_line` /
  `csi_dispatch` / `esc_dispatch` / `hook` / `put` / `put_slice` / `unhook` /
  `osc_dispatch`, all with no-op defaults.
- **Owned event API** (`event.mbt`) — `Event` (with `PrintBytes` bulk runs and
  CSI `sep`) + `Recording` (replay, helpers) and `Event::write_bytes`.
- **UTF-8** (`utf8.mbt`) — W3C "Substitution of Maximal Subparts": each
  invalid maximal subpart becomes one `U+FFFD`, standalone C1 keeps `execute`
  semantics, and trailing partial code points are detected up front
  (`trailing_partial`) and carried across `advance` calls.
- **`Parser`** (`parser.mbt`) — zero-allocation dispatch to a `Perform` sink:
  bulk `print_bytes` runs, a `ESC [ … final` CSI fast path, inline
  escape/param/OSC/DCS dispatchers, a 1 MiB OSC payload cap with deferred
  copy, `flush()` for end-of-stream, and `reset()`.
- **SIMD byte scans** (`simd.mbt`) — `first_non_printable` / `first_esc` via
  `@v128`, plus branchless `decode_validated`. Opt in with
  `Parser::with_simd()`.
- **Terminal model types** (the `vtty_core` data plane) — `ColorId` + RGB
  packing/OSC color parsing (`color.mbt`), `SgrFlags`/`StyleFlags`/
  `UnderlineStyle`/`CursorStyle` + the `ColorSpec`/`SgrEffect`/`Sgr` effect
  parser (`style.mbt`), `Charset`/`Charsets`/`Scs`/`dec_special_graphics`
  (`charset.mbt`), `KittyFlags` (`keyboard.mbt`), `TermFlags`/`MOUSE_MASK`
  (incl. DECBKM `67` / numlock `1035`, `mode.mbt`), and `MouseButton`/
  `MouseTracking` (`mouse.mbt`).
- **Perform-sink consumers** — `State` byte-cursor geometry (`state.mbt`),
  `Reply` query-reply builders (associated functions + `osc_color`/
  `osc_palette`, `reply.mbt`), the XTGETTCAP `Cap` table with host-supplied
  `TN` (`termcap.mbt`), and the OSC 7501 `ProgramStatus` parser/encoder +
  `PerformProgramStatus` (`status.mbt`).

## Not ported

SIMD UTF-8 window validation (`simd-transcode`), the float/`no_std` color
helpers (`u32_to_rgba`, `format_osc_background`, `blend_faint`),
`vtty_codec`, `vtty_screen`, `vtty_grapheme`, `vtty_width` (ICU4X),
`vtty_ffi` (C ABI), and the benchmark harness.

## Usage

```moonbit
let p = @vtty.Parser::new() // or Parser::with_simd() for the SIMD fast path
let input : Array[Int] = [0x1b, 0x5b, 0x31, 0x3b, 0x33, 0x31, 0x6d] // CSI 1;31m

// Sink into a Recording and inspect the owned events.
let rec = @vtty.Recording::new()
p.advance(rec, input[:])
inspect(rec.events())

// Or collect owned events in one call.
let events = @vtty.Parser::new().parse_events(input[:])
```

## Terminal example

`cmd/term` is an interactive terminal emulator: it spawns a shell on a PTY
(`moonbit-community/pty`), puts stdin into raw mode (`moonbit-community/tty`),
and feeds the shell's output through `vtty` into an 80×24 screen sink
(cursor tracking, SGR colors, OSC title) that redraws on every chunk. Ctrl-D
ends the session.

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
