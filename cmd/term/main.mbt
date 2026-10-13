// An interactive minimal terminal emulator: spawn a shell on a real PTY
// (via `moonbit-community/pty`), forward stdin keystrokes to it, feed its
// output through `vtty` into an 80x24 screen sink (cursor tracking, SGR
// colors, `CSI … H`/`A`/`B`/`C`/`D`, `ED`, OSC title), and redraw the screen
// on every chunk. Ctrl-D ends the session.
//
// Run with:
//   moon run --target native cmd/term

///|
const COLS : Int = 80

///|
const ROWS : Int = 24

///|
/// One styled screen cell.
struct Cell {
  ch : Char
  fg : Int
  bg : Int
  bold : Bool
}

///|
/// A tiny 80×24 screen: a `Perform` sink that tracks the cursor and writes
/// styled cells.
///
/// Basic + 256-color SGR is supported; truecolor is snapped to the nearest
/// 256-color entry. The OSC title is kept for the status line.
struct Screen {
  grid : Array[Array[Cell]]
  mut row : Int
  mut col : Int
  mut title : String
  mut fg : Int
  mut bg : Int
  mut bold : Bool
}

///|
fn Screen::new() -> Screen {
  let grid : Array[Array[Cell]] = []
  for _ in 0..<ROWS {
    let line : Array[Cell] = []
    for _ in 0..<COLS {
      line.push({ ch: ' ', fg: -1, bg: -1, bold: false })
    }
    grid.push(line)
  }
  { grid, row: 0, col: 0, title: "", fg: -1, bg: -1, bold: false }
}

///|
/// Write one cell with the current SGR style and advance the cursor (wrapping
/// to the next line).
fn Screen::write_cell(self : Screen, c : Char) -> Unit {
  if self.row < ROWS && self.col < COLS {
    self.grid[self.row][self.col] = {
      ch: c,
      fg: self.fg,
      bg: self.bg,
      bold: self.bold,
    }
  }
  self.col = self.col + 1
  if self.col >= COLS {
    self.col = 0
    self.row = self.row + 1
  }
}

///|
/// Apply an SGR (CSI … m) parameter list to the current style.
fn Screen::apply_sgr(self : Screen, params : ArrayView[Int]) -> Unit {
  let n = params.length()
  let mut i = 0
  while i < n {
    let p = params[i]
    if p == 0 {
      self.fg = -1
      self.bg = -1
      self.bold = false
    } else if p == 1 {
      self.bold = true
    } else if p == 22 {
      self.bold = false
    } else if p >= 30 && p <= 37 {
      self.fg = p - 30
    } else if p == 38 {
      if i + 2 < n && params[i + 1] == 5 {
        self.fg = params[i + 2]
        i = i + 2
      } else if i + 4 < n && params[i + 1] == 2 {
        self.fg = rgb_to_256(params[i + 2], params[i + 3], params[i + 4])
        i = i + 4
      }
    } else if p == 39 {
      self.fg = -1
    } else if p >= 40 && p <= 47 {
      self.bg = p - 40
    } else if p == 48 {
      if i + 2 < n && params[i + 1] == 5 {
        self.bg = params[i + 2]
        i = i + 2
      } else if i + 4 < n && params[i + 1] == 2 {
        self.bg = rgb_to_256(params[i + 2], params[i + 3], params[i + 4])
        i = i + 4
      }
    } else if p == 49 {
      self.bg = -1
    } else if p >= 90 && p <= 97 {
      self.fg = p - 90 + 8
    } else if p >= 100 && p <= 107 {
      self.bg = p - 100 + 8
    }
    i = i + 1
  }
}

///|
/// Snap an RGB triple to the nearest xterm 256-color entry (6×6×6 cube +
/// grayscale ramp).
fn rgb_to_256(r : Int, g : Int, b : Int) -> Int {
  if r == g && g == b {
    if r < 8 {
      16
    } else if r > 248 {
      231
    } else {
      232 + (r - 8) / 10
    }
  } else {
    16 + 36 * (r / 51) + 6 * (g / 51) + (b / 51)
  }
}

///|
/// Build an ANSI SGR escape for a cell style, run-length encoding so
/// consecutive same-styled cells share one escape.
fn sgr_code(fg : Int, bg : Int, bold : Bool) -> String {
  if fg < 0 && bg < 0 && !bold {
    return "\u{1b}[0m"
  }
  let parts : Array[String] = []
  if bold {
    parts.push("1")
  }
  if fg >= 0 && fg < 8 {
    parts.push("\{30 + fg}")
  } else if fg >= 8 && fg < 16 {
    parts.push("\{90 + fg - 8}")
  } else if fg >= 16 {
    parts.push("38;5;\{fg}")
  }
  if bg >= 0 && bg < 8 {
    parts.push("\{40 + bg}")
  } else if bg >= 8 && bg < 16 {
    parts.push("\{100 + bg - 8}")
  } else if bg >= 16 {
    parts.push("48;5;\{bg}")
  }
  let mut s = "\u{1b}["
  let mut first = true
  for part in parts {
    if !first {
      s = s + ";"
    }
    first = false
    s = s + part
  }
  s + "m"
}

///|
fn Screen::render(self : Screen) -> String {
  let mut out = ""
  let mut first_line = true
  let mut cur_fg = -1
  let mut cur_bg = -1
  let mut cur_bold = false
  for line in self.grid {
    if !first_line {
      out = out + "\n"
    }
    first_line = false
    for cell in line {
      if cell.fg != cur_fg || cell.bg != cur_bg || cell.bold != cur_bold {
        out = out + sgr_code(cell.fg, cell.bg, cell.bold)
        cur_fg = cell.fg
        cur_bg = cell.bg
        cur_bold = cell.bold
      }
      out = out + cell.ch.to_string()
    }
  }
  if cur_fg != -1 || cur_bg != -1 || cur_bold {
    out = out + "\u{1b}[0m"
  }
  out
}

///|
impl @vtty.Perform for Screen with fn print(self, c : Char) {
  self.write_cell(c)
}

///|
impl @vtty.Perform for Screen with fn print_bytes(self, s : ArrayView[Int]) {
  for b in s {
    self.write_cell(@vtty.cp_to_char(b))
  }
}

///|
impl @vtty.Perform for Screen with fn print_codepoints(
  self,
  cps : ArrayView[Int],
) {
  for cp in cps {
    self.write_cell(@vtty.cp_to_char(cp))
  }
}

///|
impl @vtty.Perform for Screen with fn execute(self, b : Int) {
  match b {
    0x0a => {
      self.row = self.row + 1
      if self.row >= ROWS {
        self.row = ROWS - 1
      }
    }
    0x0d => self.col = 0
    _ => ()
  }
}

///|
impl @vtty.Perform for Screen with fn csi_dispatch(
  self,
  params : ArrayView[Int],
  _sep : Int,
  _intermediates : ArrayView[Int],
  final_byte : Int,
) {
  let n = params.length()
  let p0 = if n > 0 { params[0] } else { 0 }
  let p1 = if n > 1 { params[1] } else { 0 }
  let step = p0.max(1)
  match final_byte {
    0x48 | 0x66 => {
      // CUP / HVP: CSI row ; col H  (1-based).
      self.row = if p0 > 0 { p0 - 1 } else { 0 }
      self.col = if p1 > 0 { p1 - 1 } else { 0 }
    }
    0x41 => self.row = if self.row > step { self.row - step } else { 0 } // Up
    0x42 =>
      self.row = if self.row + step < ROWS - 1 {
        self.row + step
      } else {
        ROWS - 1
      } // Down
    0x43 =>
      self.col = if self.col + step < COLS - 1 {
        self.col + step
      } else {
        COLS - 1
      } // Fwd
    0x44 => self.col = if self.col > step { self.col - step } else { 0 } // Back
    0x4a =>
      // ED: CSI n J — 2/3 clears the whole screen.
      if p0 == 2 || p0 == 3 {
        for r in 0..<ROWS {
          for c in 0..<COLS {
            self.grid[r][c] = { ch: ' ', fg: -1, bg: -1, bold: false }
          }
        }
        self.row = 0
        self.col = 0
      }
    0x6d => self.apply_sgr(params)
    _ => ()
  }
}

///|
impl @vtty.Perform for Screen with fn osc_dispatch(
  self,
  params : Array[Array[Int]],
  _bell : Bool,
) {
  if params.length() > 1 {
    let mut title = ""
    for b in params[1] {
      title = title + @vtty.cp_to_char(b).to_string()
    }
    self.title = title
  }
}

///|
/// Convert raw PTY bytes to the parser's `Array[Int]` input.
fn bytes_to_ints(b : Bytes) -> Array[Int] {
  let arr : Array[Int] = []
  for byte in b {
    arr.push(byte.to_int())
  }
  arr
}

///|
/// Clear the screen and redraw it from the current grid, with the OSC title
/// on a status line.
fn redraw(screen : Screen) -> Unit {
  println("\u{1b}[H" + screen.render())
  if screen.title != "" {
    println("\u{1b}[90mOSC title: \{screen.title}\u{1b}[0m")
  }
}

///|
/// Forward stdin keystrokes to the PTY.
///
/// In raw mode each keystroke arrives immediately; the shell echoes it back
/// through the output path. Ctrl-D (`0x04`) is forwarded too, so the shell
/// sees EOF and exits.
async fn forward_stdin(pty : @pty.Pty) -> Unit {
  while true {
    let chunk = @stdio.stdin.read_some() catch { _ => break }
    match chunk {
      Some(b) => {
        let _ = pty.write_once(b, offset=0, len=b.length()) catch { _ => break }
      }
      None => break
    }
  }
}

///|
async fn main {
  println("\u{1b}[2Jvtty (MoonBit) — Ctrl-D to exit")

  @async.with_task_group() <| g => {
    let pty = @pty.spawn(g, rows=ROWS, cols=COLS, "sh", [])
    let screen = Screen::new()
    let parser = @vtty.Parser::new()

    // PTY output → parser → redraw.
    g.spawn_bg(no_wait=true, () => {
      while true {
        let chunk = pty.read_some() catch { _ => break }
        match chunk {
          Some(b) => {
            parser.advance(screen, bytes_to_ints(b)[:])
            redraw(screen)
          }
          None => break
        }
      }
    })

    // Stdin → PTY, in raw mode when stdin is a terminal (via
    // `moonbit-community/tty`). Piped stdin skips raw mode and just forwards.
    g.spawn_bg(no_wait=true, () => {
      let tty = @tty.Tty::stdio() catch {
        _ => {
          forward_stdin(pty)
          return
        }
      }
      let state = tty.enter_raw_mode() catch {
        _ => {
          forward_stdin(pty)
          return
        }
      }
      defer tty.leave_raw_mode(state)
      forward_stdin(pty)
    })

    // Wait for the shell to exit (Ctrl-D / `exit`).
    let exit = pty.wait()
    println("\nexit: \{exit}")
  }
}
