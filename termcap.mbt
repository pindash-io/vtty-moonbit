// XTGETTCAP terminfo capability table.
//
// Answers the `DCS + q <hex cap> ST` capability query (xterm XTGETTCAP) with
// the terminal's advertised terminfo values. Mirrors the subset real apps
// probe (nvim `RGB`/`setrgbf`/`Smulx`/`Ss`/`sync`, fish `query-os-name`,
// tmux `setaf`/`setab`).

///|
/// The reply value for a capability.
pub(all) enum CapValue {
  /// Unknown / unsupported — reply is the `DCS 0 + r` error.
  None
  /// Boolean capability — reply is a bare `key` (no `=value`).
  Bool
  /// String capability — reply is `key=value`.
  Text(String)
  /// The terminal column count (`co`).
  Cols
  /// The terminal row count (`li`).
  Rows
  /// The OS name (`query-os-name`).
  OsName
} derive(Eq, Debug)

///|
pub extend CapValue with Eq::{equal, not_equal}

///|
pub extend CapValue with @debug.Debug::{to_repr}

///|
/// OS name for the non-standard `query-os-name` capability (the dev platform
/// in this port).
fn os_name() -> String {
  "macos"
}

///|
/// Parse a query name into a capability (canonical key + value), accepting
/// the long/short terminfo aliases. Unknown names map to `CapValue::None`.
pub fn cap_parse(query : String) -> (String, CapValue) {
  match query {
    "TN" | "name" => ("TN", CapValue::Text("jetfish"))
    "Co" | "colors" => ("Co", CapValue::Text("256"))
    "pa" | "pairs" => ("pa", CapValue::Text("32767"))
    "RGB" => ("RGB", CapValue::Text("8/8/8"))
    "Tc" => ("Tc", CapValue::Bool)
    "co" | "cols" => ("co", CapValue::Cols)
    "li" | "lines" => ("li", CapValue::Rows)
    "it" => ("it", CapValue::Text("8"))
    "am" => ("am", CapValue::Bool)
    "bce" => ("bce", CapValue::Bool)
    "ccc" => ("ccc", CapValue::Bool)
    "xenl" | "xn" => ("xn", CapValue::Bool)
    "XT" => ("XT", CapValue::Bool)
    "XF" => ("XF", CapValue::Bool)
    "sixel" => ("sixel", CapValue::Bool)
    "iterm2" => ("iterm2", CapValue::Bool)
    "kitty" | "TK" => ("kitty", CapValue::Text("yes"))
    "setrgbf" => ("setrgbf", CapValue::Text("\u{1b}[38:2:%p1%d:%p2%d:%p3%dm"))
    "setrgbb" => ("setrgbb", CapValue::Text("\u{1b}[48:2:%p1%d:%p2%d:%p3%dm"))
    "setaf" => ("setaf", CapValue::Text("\u{1b}[38;5;%p1%dm"))
    "setab" => ("setab", CapValue::Text("\u{1b}[48;5;%p1%dm"))
    "op" => ("op", CapValue::Text("\u{1b}[39;49m"))
    "oc" => ("oc", CapValue::Text("\u{1b}]104\u{07}"))
    "Smulx" => ("Smulx", CapValue::Text("\u{1b}[4:%p1%dm"))
    "Setulc" =>
      (
        "Setulc",
        CapValue::Text(
          "\u{1b}[58:2:%p1%{65536}%/%d:%p1%{256}%/%{255}%&%d:%p1%{255}%&%dm",
        ),
      )
    "Ss" => ("Ss", CapValue::Text("\u{1b}[%p1%d q"))
    "Se" => ("Se", CapValue::Text("\u{1b}[0 q"))
    "Cs" => ("Cs", CapValue::Text("\u{1b}]12;%p1%s\u{07}"))
    "Cr" => ("Cr", CapValue::Text("\u{1b}]112\u{07}"))
    "sync" => ("sync", CapValue::Text("\u{1b}[?2026%?%p1%{1}%-%tl%eh"))
    "E3" => ("E3", CapValue::Text("\u{1b}[3J"))
    "clear" | "cl" => ("clear", CapValue::Text("\u{1b}[H\u{1b}[2J"))
    "cup" | "cm" => ("cup", CapValue::Text("\u{1b}[%i%p1%d;%p2%dH"))
    "smkx" | "ks" => ("smkx", CapValue::Text("\u{1b}[?1h\u{1b}="))
    "rmkx" | "ke" => ("rmkx", CapValue::Text("\u{1b}[?1l\u{1b}>"))
    "smcup" | "ti" => ("smcup", CapValue::Text("\u{1b}[?1049h"))
    "rmcup" | "te" => ("rmcup", CapValue::Text("\u{1b}[?1049l"))
    "smacs" | "as" => ("smacs", CapValue::Text("\u{1b}(0"))
    "rmacs" | "ae" => ("rmacs", CapValue::Text("\u{1b}(B"))
    "acsc" =>
      (
        "acsc",
        CapValue::Text("``aaffggiijjkkllmmnnooppqqrrssttuuvvwwxxyyzz{{||}}~~"),
      )
    "civis" | "vi" => ("civis", CapValue::Text("\u{1b}[?25l"))
    "cnorm" | "ve" => ("cnorm", CapValue::Text("\u{1b}[?25h"))
    "kbs" => ("kbs", CapValue::Text("\u{7f}"))
    "kdch1" => ("kdch1", CapValue::Text("\u{1b}[3~"))
    "kich1" => ("kich1", CapValue::Text("\u{1b}[2~"))
    "khome" => ("khome", CapValue::Text("\u{1b}[H"))
    "kend" => ("kend", CapValue::Text("\u{1b}[F"))
    "kcuu1" => ("kcuu1", CapValue::Text("\u{1b}[A"))
    "kcud1" => ("kcud1", CapValue::Text("\u{1b}[B"))
    "kcub1" => ("kcub1", CapValue::Text("\u{1b}[D"))
    "kcuf1" => ("kcuf1", CapValue::Text("\u{1b}[C"))
    "indn" => ("indn", CapValue::Text("\u{1b}[%p1%dS"))
    "query-os-name" => ("query-os-name", CapValue::OsName)
    _ => ("", CapValue::None)
  }
}

///|
/// Answer an XTGETTCAP capability query (`DCS + q <hex cap> ST`), appending
/// the `DCS … ST` reply. The query may pack several capabilities,
/// semicolon-separated; each is answered in order.
pub fn Reply::termcap(
  self : Reply,
  cap : String,
  cols : Int,
  rows : Int,
) -> Reply {
  let mut reply = self
  for part in cap.split(";") {
    if part.length() == 0 {
      continue
    }
    let (key, value) = cap_parse(part.to_owned())
    reply = match value {
      CapValue::None => reply.xtgettcap_error("unsupported")
      CapValue::Bool => reply.xtgettcap_reply_bool(key)
      CapValue::Text(v) => reply.xtgettcap_reply(key, v)
      CapValue::Cols => reply.xtgettcap_num(key, cols)
      CapValue::Rows => reply.xtgettcap_num(key, rows)
      CapValue::OsName => reply.xtgettcap_reply(key, os_name())
    }
  }
  reply
}
