name = "fundon/vtty"

version = "0.1.0"

description = "Zero-allocation, panic-free DEC VT500 terminal parser with UTF-8 decoding (MoonBit port)"

repository = "https://github.com/pindash-io/vtty"

keywords = [ "terminal", "vt100", "vt500", "ansi", "parser", "escape" ]

license = "Apache-2.0"

import {
  "moonbit-community/pty@0.4.3",
  "moonbitlang/async@0.22.4",
  "moonbit-community/tty@0.4.0",
}

preferred_target = "native"
