// Program Status Protocol (`OSC 7501`) — parse and encode.
//
// A program reports what it is doing (idle, working, done, blocked, error,
// or clear) to the terminal with:
//
// ```text
// ESC ] 7501 ; state=working:app=brew:msg=<base64> ESC \
// ```
//
// Reference: <https://www.superlogical.com/rex/docs/build/program-status>.

///|
/// Report body length limit (bytes).
const MAX_SEQUENCE : Int = 4096

///|
/// `key` length limit (bytes).
const MAX_KEY : Int = 16

///|
/// `msg` limits: on-wire base64, then decoded bytes.
const MAX_MSG_ENCODED : Int = 2732

///|
const MAX_MSG_DECODED : Int = 2048

///|
/// `title` limits: on-wire base64, then decoded bytes.
const MAX_TITLE_ENCODED : Int = 256

///|
const MAX_TITLE_DECODED : Int = 192

///|
/// `app` length limit (bytes).
const MAX_APP : Int = 32

///|
/// `id` limits: total length, per segment, and depth.
const MAX_ID : Int = 128

///|
const MAX_ID_SEGMENT : Int = 32

///|
const MAX_ID_DEPTH : Int = 8

///|
/// The state a program reports.
pub(all) enum StatusState {
  /// At rest, waiting for the user's next instruction.
  Idle
  /// Running. May carry `progress`.
  Working
  /// Finished a piece of work; the user has not seen the result yet.
  Done
  /// Cannot continue until the user does something.
  Blocked
  /// Failed and stopped.
  Error
  /// Not a state: clears the addressed record (and its children).
  Clear
} derive(Eq, Debug)

///|
pub extend StatusState with Eq::{equal, not_equal}

///|
pub extend StatusState with @debug.Debug::{to_repr}

///|
/// Parse a status-state wire name.
pub fn StatusState::parse(name : String) -> Option[StatusState] {
  match name {
    "idle" => Some(StatusState::Idle)
    "working" => Some(StatusState::Working)
    "done" => Some(StatusState::Done)
    "blocked" => Some(StatusState::Blocked)
    "error" => Some(StatusState::Error)
    "clear" => Some(StatusState::Clear)
    _ => None
  }
}

///|
/// The wire name for a status state.
pub fn StatusState::as_string(self : StatusState) -> String {
  match self {
    StatusState::Idle => "idle"
    StatusState::Working => "working"
    StatusState::Done => "done"
    StatusState::Blocked => "blocked"
    StatusState::Error => "error"
    StatusState::Clear => "clear"
  }
}

///|
/// What a `blocked` program is waiting for.
pub(all) enum StatusKind {
  /// Approval to do something.
  Permission
  /// The user must type an answer.
  Question
  /// A login, token, or credential.
  Auth
} derive(Eq, Debug)

///|
pub extend StatusKind with Eq::{equal, not_equal}

///|
pub extend StatusKind with @debug.Debug::{to_repr}

///|
/// Parse a status-kind wire name.
pub fn StatusKind::parse(name : String) -> Option[StatusKind] {
  match name {
    "permission" => Some(StatusKind::Permission)
    "question" => Some(StatusKind::Question)
    "auth" => Some(StatusKind::Auth)
    _ => None
  }
}

///|
/// The wire name for a status kind.
pub fn StatusKind::as_string(self : StatusKind) -> String {
  match self {
    StatusKind::Permission => "permission"
    StatusKind::Question => "question"
    StatusKind::Auth => "auth"
  }
}

///|
/// A parsed OSC 7501 report.
///
/// A report without `id` addresses the root record; each report replaces its
/// record completely.
pub struct ProgramStatus {
  /// The reported state. Required by the protocol.
  state : StatusState
  /// Optional record path (`a/b/c`); absent means the root record.
  id : Option[String]
  /// Why the program is `blocked`; ignored for other states.
  kind : Option[StatusKind]
  /// Progress in `0..=100`; absent means indeterminate.
  progress : Option[Int]
  /// Stable program identifier (`cargo`, `terraform`, …).
  app : Option[String]
  /// Short human-readable label.
  title : Option[String]
  /// One human-readable line about what the record is doing.
  msg : Option[String]
} derive(Eq, Debug)

///|
pub extend ProgramStatus with Eq::{equal, not_equal}

///|
pub extend ProgramStatus with @debug.Debug::{to_repr}

///|
/// Build a `ProgramStatus` from its fields.
pub fn ProgramStatus::new(
  state : StatusState,
  id : Option[String],
  kind : Option[StatusKind],
  progress : Option[Int],
  app : Option[String],
  title : Option[String],
  msg : Option[String],
) -> ProgramStatus {
  { state, id, kind, progress, app, title, msg }
}

///|
/// An empty report (idle, no fields).
pub fn ProgramStatus::default() -> ProgramStatus {
  {
    state: StatusState::Idle,
    id: None,
    kind: None,
    progress: None,
    app: None,
    title: None,
    msg: None,
  }
}

///|
/// Feature-detection query: `ESC ] 7501 ; ? ESC \`.
pub fn program_status_query() -> Array[Int] {
  [0x1b, 0x5d, 0x37, 0x35, 0x30, 0x31, 0x3b, 0x3f, 0x1b, 0x5c]
}

///|
/// Parses an OSC 7501 report body (the `key=value` pairs).
///
/// Returns `None` if the report is invalid and must be discarded whole:
/// missing/invalid `state`, malformed `id`, any limit exceeded, bad base64,
/// or control characters in a decoded `msg`/`title`.
pub fn ProgramStatus::parse(body : ArrayView[Int]) -> Option[ProgramStatus] {
  if body.length() > MAX_SEQUENCE {
    return None
  }
  let mut state : Option[StatusState] = None
  let mut id : Option[String] = None
  let mut kind : Option[StatusKind] = None
  let mut progress : Option[Int] = None
  let mut app : Option[String] = None
  let mut title : Option[String] = None
  let mut msg : Option[String] = None

  // Split the body on `:` and each pair on `=`. Malformed/unknown pairs are
  // skipped; a hard error in a recognized field discards the whole report.
  let mut start = 0
  let mut i = 0
  while i <= body.length() {
    if i == body.length() || body[i] == 0x3a {
      match split_pair(body[start:i]) {
        Some((key, value)) =>
          match ascii_to_string(key) {
            "state" => state = StatusState::parse(ascii_to_string(value))
            "id" =>
              match parse_id(value) {
                Some(s) => id = Some(s)
                None => return None
              }
            "kind" => kind = StatusKind::parse(ascii_to_string(value))
            "progress" => progress = parse_progress(value)
            "app" => {
              if value.length() == 0 {
                app = None
              } else if !all_ident(value) {
                app = None // outside the character set: treated as absent
              } else if value.length() > MAX_APP {
                return None // limit exceeded
              } else {
                app = Some(ascii_to_string(value))
              }
            }
            "title" =>
              match parse_text(value, MAX_TITLE_ENCODED, MAX_TITLE_DECODED) {
                Some(s) => title = Some(s)
                None => return None
              }
            "msg" =>
              match parse_text(value, MAX_MSG_ENCODED, MAX_MSG_DECODED) {
                Some(s) => msg = Some(s)
                None => return None
              }
            _ => () // unknown key
          }
        None => ()
      }
      start = i + 1
    }
    i = i + 1
  }

  let st = match state {
    Some(s) => s
    None => return None
  }
  // `kind` only applies to blocked; `progress` only to working/blocked.
  let kind2 = if st == StatusState::Blocked { kind } else { None }
  let progress2 = if st == StatusState::Working || st == StatusState::Blocked {
    progress
  } else {
    None
  }
  Some(
    {
      state: st,
      id,
      kind: kind2,
      progress: progress2,
      app,
      title,
      msg,
    },
  )
}

///|
/// Parses a report from an OSC dispatch's params (`params[0] == "7501"`).
pub fn ProgramStatus::from_osc_params(
  params : Array[Array[Int]],
) -> Option[ProgramStatus] {
  if params.length() < 2 {
    return None
  }
  if !(ascii_to_string(params[0][:]) == "7501") {
    return None
  }
  ProgramStatus::parse(params[1][:])
}

///|
/// Extension for `Perform` sinks that want typed `OSC 7501` reports.
pub(open) trait PerformProgramStatus : Perform {
  /// Called with each valid `OSC 7501` report.
  fn program_status(Self, ProgramStatus) -> Unit = _

  /// Routes one OSC dispatch. Returns `true` when the params were a valid
  /// `OSC 7501` report (and `program_status` was called).
  fn route_osc_7501(Self, Array[Array[Int]]) -> Bool = _
}

///|
impl PerformProgramStatus with fn program_status(_self, _status) {

}

///|
impl PerformProgramStatus with fn route_osc_7501(self, params) {
  match ProgramStatus::from_osc_params(params) {
    Some(status) => {
      self.program_status(status)
      true
    }
    None => false
  }
}

///|
/// The full `OSC 7501 ; pairs ST` byte sequence.
pub fn ProgramStatus::to_osc(self : ProgramStatus) -> Array[Int] {
  let out : Array[Int] = []
  self.write_osc(out)
  out
}

///|
/// Appends the full `OSC 7501 ; pairs ST` sequence to `out`.
pub fn ProgramStatus::write_osc(
  self : ProgramStatus,
  out : Array[Int],
) -> Unit {
  push_string(out, "\u{1b}]")
  push_string(out, "7501")
  out.push(0x3b) // ';'
  push_field(out, "state", self.state.as_string())
  match self.id {
    Some(s) => push_field(out, "id", s)
    None => ()
  }
  match self.kind {
    Some(k) => push_field(out, "kind", k.as_string())
    None => ()
  }
  match self.progress {
    Some(p) => push_field(out, "progress", p.to_string())
    None => ()
  }
  match self.app {
    Some(s) => push_field(out, "app", s)
    None => ()
  }
  match self.title {
    Some(s) => push_field(out, "title", @base64.encode(@utf8.encode(s)))
    None => ()
  }
  match self.msg {
    Some(s) => push_field(out, "msg", @base64.encode(@utf8.encode(s)))
    None => ()
  }
  push_string(out, "\u{1b}\\")
}

///|
/// Build a `String` from ASCII byte values.
fn ascii_to_string(bytes : ArrayView[Int]) -> String {
  let chars : Array[Char] = []
  for b in bytes {
    chars.push(Int::to_char(b).unwrap_or('\u{FFFD}'))
  }
  String::from_array(chars[:])
}

///|
/// Append a `String`'s UTF-8 bytes to `out`.
fn push_string(out : Array[Int], s : String) -> Unit {
  for b in @utf8.encode(s).iter() {
    out.push(b.to_int())
  }
}

///|
/// Append `:key=value` to `out`.
fn push_field(out : Array[Int], key : String, value : String) -> Unit {
  out.push(0x3a) // ':'
  push_string(out, key)
  out.push(0x3d) // '='
  push_string(out, value)
}

///|
/// A byte allowed in a `value` (`[A-Za-z0-9_.,+/=-]`).
fn is_value_byte(b : Int) -> Bool {
  (b >= 0x30 && b <= 0x39) || // 0-9
  (b >= 0x41 && b <= 0x5a) || // A-Z
  (b >= 0x61 && b <= 0x7a) || // a-z
  b == 0x5f || // _
  b == 0x2e || // .
  b == 0x2c || // ,
  b == 0x2b || // +
  b == 0x2f || // /
  b == 0x3d || // =
  b == 0x2d // -
}

///|
/// A byte allowed in an `app` or `id` segment (`[A-Za-z0-9_.+-]`).
fn is_ident_byte(b : Int) -> Bool {
  (b >= 0x30 && b <= 0x39) || // 0-9
  (b >= 0x41 && b <= 0x5a) || // A-Z
  (b >= 0x61 && b <= 0x7a) || // a-z
  b == 0x5f || // _
  b == 0x2e || // .
  b == 0x2b || // +
  b == 0x2d // -
}

///|
/// Whether every byte in `bytes` is an identifier byte.
fn all_ident(bytes : ArrayView[Int]) -> Bool {
  for b in bytes {
    if !is_ident_byte(b) {
      return false
    }
  }
  true
}

///|
/// Splits a `key=value` pair at the first `=`. Returns `None` for a malformed
/// pair: no `=`, an empty/over-long/non-lowercase key, or a forbidden value
/// byte.
fn split_pair(pair : ArrayView[Int]) -> Option[(ArrayView[Int], ArrayView[Int])] {
  let mut i = 0
  while i < pair.length() {
    if pair[i] == 0x3d {
      let key = pair[:i]
      let value = pair[i + 1:]
      if key.length() == 0 || key.length() > MAX_KEY {
        return None
      }
      for k in key {
        if !(k >= 0x61 && k <= 0x7a) {
          return None // key must be lowercase ASCII
        }
      }
      for v in value {
        if !is_value_byte(v) {
          return None
        }
      }
      return Some((key, value))
    }
    i = i + 1
  }
  None
}

///|
/// Parses a decimal `progress` value in `0..=100`.
fn parse_progress(value : ArrayView[Int]) -> Option[Int] {
  if value.length() == 0 || value.length() > 3 {
    return None
  }
  let mut n = 0
  for b in value {
    if !(b >= 0x30 && b <= 0x39) {
      return None
    }
    n = n * 10 + (b - 0x30)
  }
  if n <= 100 {
    Some(n)
  } else {
    None
  }
}

///|
/// Parses an `id` path (`a/b/c`), enforcing the length, segment and depth
/// limits.
fn parse_id(value : ArrayView[Int]) -> Option[String] {
  if value.length() == 0 || value.length() > MAX_ID {
    return None
  }
  let mut depth = 1
  for b in value {
    if b == 0x2f {
      depth = depth + 1
    }
  }
  if depth > MAX_ID_DEPTH {
    return None
  }
  let mut start = 0
  let mut i = 0
  while i <= value.length() {
    if i == value.length() || value[i] == 0x2f {
      let seg_len = i - start
      if seg_len == 0 || seg_len > MAX_ID_SEGMENT {
        return None
      }
      let mut j = start
      while j < i {
        if !is_ident_byte(value[j]) {
          return None
        }
        j = j + 1
      }
      start = i + 1
    }
    i = i + 1
  }
  Some(ascii_to_string(value))
}

///|
/// Whether `c` is a control character (C0, DEL, or C1).
fn is_control_char(c : Char) -> Bool {
  let cp = c.to_int()
  (cp >= 0x00 && cp <= 0x1f) || cp == 0x7f || (cp >= 0x80 && cp <= 0x9f)
}

///|
/// Decodes a base64 `title`/`msg` value, enforcing the encoded/decoded limits
/// and rejecting control characters.
fn parse_text(
  value : ArrayView[Int],
  max_encoded : Int,
  max_decoded : Int,
) -> Option[String] {
  if value.length() > max_encoded {
    return None
  }
  let s = ascii_to_string(value)
  let decoded = try {
    @base64.decode(s)
  } catch {
    _ => return None
  }
  if decoded.length() > max_decoded {
    return None
  }
  let text = try {
    @utf8.decode(decoded)
  } catch {
    _ => return None
  }
  for c in text {
    if is_control_char(c) {
      return None
    }
  }
  Some(text)
}
