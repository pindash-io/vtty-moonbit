// An interactive minimal terminal emulator: spawn a shell on a real PTY
// (via `moonbit-community/pty`), forward stdin keystrokes to it, feed its
// output through `vtty` into an 80x24 screen sink, and redraw the screen on
// every chunk. Ctrl-D ends the session.
//
// Run with:
//   moon run --target native cmd/term

///|
const COLS : Int = 80

///|
const ROWS : Int = 24

///| A tiny 80x24 screen: a `Perform` sink that tracks the cursor and writes

///|
/// printable cells. SGR colors are ignored; the OSC title is kept.
struct Screen {
  grid : Array[Array[Char]]
  mut row : Int
  mut col : Int
  mut title : String
}

///|
fn Screen::new() -> Screen {
  let grid : Array[Array[Char]] = []
  for _ in 0..<ROWS {
    let line : Array[Char] = []
    for _ in 0..<COLS {
      line.push(' ')
    }
    grid.push(line)
  }
  { grid, row: 0, col: 0, title: "", }
}

///|
/// Write one cell and advance the cursor (wrapping to the next line).
fn Screen::write_cell(self : Screen, c : Char) -> Unit {
  if self.row < ROWS && self.col < COLS {
    self.grid[self.row][self.col] = c
  }
  self.col = self.col + 1
  if self.col >= COLS {
    self.col = 0
    self.row = self.row + 1
  }
}

///|
fn Screen::render(self : Screen) -> String {
  let mut out = ""
  let mut first = true
  for line in self.grid {
    if !first {
      out = out + "\n"
    }
    first = false
    out = out + String::from_array(line)
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
            self.grid[r][c] = ' '
          }
        }
        self.row = 0
        self.col = 0
      }
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
/// Clear the screen and redraw it from the current grid.
fn redraw(screen : Screen) -> Unit {
  println("\u{1b}[H" + screen.render())
}

///| Forward stdin keystrokes to the PTY. In raw mode each keystroke arrives

///| immediately; the shell (canonical + echo on the PTY) echoes it back

///| through the output path. Ctrl-D (0x04) is forwarded too, so the shell

///|
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
