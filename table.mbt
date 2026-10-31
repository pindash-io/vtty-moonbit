// DEC VT500 escape-sequence state machine: parser states, action bit flags,
// and the `transition` lookup.
//
// Reference: Paul Flo Williams' VT500 parser state diagram
// https://vt100.net/emu/dec_ansi_parser — "State Definitions" and "Action
// Definitions" map 1:1 to `ParseState` and the `Action` bit flags. The
// grammar is ECMA-48 §5.4/§8.3.

///|
/// VT500 parser states (mutually exclusive).
pub enum ParseState {
  Ground
  Escape
  EscapeIntermediate
  CsiEntry
  CsiParam
  CsiIntermediate
  CsiIgnore
  OscString
  DcsEntry
  DcsParam
  DcsIntermediate
  DcsPassthrough
  DcsIgnore
  SosPmApcString
} derive(Eq, Debug)

///|
pub extend ParseState with Eq::{equal, not_equal}

///|
pub extend ParseState with @debug.Debug::{to_repr}

///|
/// Action bit flags (a byte can trigger several).
///
/// No action.
pub const ACTION_NONE : Int = 0

///|
/// Print the byte as a character.
pub const ACTION_PRINT : Int = 1 << 0

///|
/// Execute a C0/C1 control byte.
pub const ACTION_EXECUTE : Int = 1 << 1

///|
/// Dispatch a CSI sequence.
pub const ACTION_CSI_DISPATCH : Int = 1 << 2

///|
/// Dispatch an escape sequence.
pub const ACTION_ESC_DISPATCH : Int = 1 << 3

///|
/// Start a DCS string (hook).
pub const ACTION_HOOK : Int = 1 << 4

///|
/// Accumulate a DCS payload byte.
pub const ACTION_PUT : Int = 1 << 5

///|
/// End a DCS string (unhook).
pub const ACTION_UNHOOK : Int = 1 << 6

///|
/// Start an OSC string.
pub const ACTION_OSC_START : Int = 1 << 7

///|
/// Accumulate an OSC payload byte.
pub const ACTION_OSC_PUT : Int = 1 << 8

///|
/// End an OSC string.
pub const ACTION_OSC_END : Int = 1 << 9

///|
/// Test whether `action` contains `flag`.
pub fn action_has(action : Int, flag : Int) -> Bool {
  (action & flag) != 0
}

///|
/// DEC "anywhere" transition for a raw 8-bit C1 control byte (`0x80..=0x9f`).
///
/// The introducers start their sequence; ST is a no-op; the rest execute and
/// return to ground.
pub fn c1_transition(b : Int) -> (Int, ParseState) {
  match b {
    0x90 => (ACTION_NONE, ParseState::DcsEntry) // DCS
    0x98 | 0x9e | 0x9f => (ACTION_NONE, ParseState::SosPmApcString) // SOS/PM/APC
    0x9b => (ACTION_NONE, ParseState::CsiEntry) // CSI
    0x9d => (ACTION_OSC_START, ParseState::OscString) // OSC
    0x9c => (ACTION_NONE, ParseState::Ground) // ST
    _ => (ACTION_EXECUTE, ParseState::Ground) // other C1
  }
}

///|
/// The DEC VT500 transition table for the non-ground states.
///
/// A byte can trigger several actions; the result is
/// `(action_bitmask, next_state)`.
pub fn transition(state : ParseState, b : Int) -> (Int, ParseState) {
  match state {
    ParseState::Escape =>
      match b {
        0x00..=0x17 | 0x19 | 0x1c..=0x1f => (ACTION_EXECUTE, ParseState::Escape)
        0x18 | 0x1a => (ACTION_EXECUTE, ParseState::Ground)
        0x1b => (ACTION_NONE, ParseState::Escape)
        0x20..=0x2f => (ACTION_NONE, ParseState::EscapeIntermediate)
        0x30..=0x4f | 0x51..=0x57 | 0x59 | 0x5a | 0x5c | 0x60..=0x7e =>
          (ACTION_ESC_DISPATCH, ParseState::Ground)
        0x50 => (ACTION_NONE, ParseState::DcsEntry) // 'P' → DCS
        0x58 | 0x5e | 0x5f => (ACTION_NONE, ParseState::SosPmApcString) // 'X' '^' '_'
        0x5b => (ACTION_NONE, ParseState::CsiEntry) // '[' → CSI
        0x5d => (ACTION_OSC_START, ParseState::OscString) // ']' → OSC
        _ => (ACTION_NONE, ParseState::Escape)
      }
    ParseState::EscapeIntermediate =>
      match b {
        0x00..=0x17 | 0x19 | 0x1c..=0x1f =>
          (ACTION_EXECUTE, ParseState::EscapeIntermediate)
        0x18 | 0x1a => (ACTION_EXECUTE, ParseState::Ground)
        0x1b => (ACTION_NONE, ParseState::Escape)
        0x20..=0x2f => (ACTION_NONE, ParseState::EscapeIntermediate)
        0x30..=0x7e => (ACTION_ESC_DISPATCH, ParseState::Ground)
        _ => (ACTION_NONE, ParseState::EscapeIntermediate)
      }
    ParseState::CsiEntry =>
      match b {
        0x00..=0x17 | 0x19 | 0x1c..=0x1f =>
          (ACTION_EXECUTE, ParseState::CsiEntry)
        0x18 | 0x1a => (ACTION_EXECUTE, ParseState::Ground)
        0x1b => (ACTION_NONE, ParseState::Escape)
        0x20..=0x2f => (ACTION_NONE, ParseState::CsiIntermediate)
        0x30..=0x39 | 0x3a | 0x3b | 0x3c..=0x3f =>
          (ACTION_NONE, ParseState::CsiParam)
        0x40..=0x7e => (ACTION_CSI_DISPATCH, ParseState::Ground)
        _ => (ACTION_NONE, ParseState::CsiEntry)
      }
    ParseState::CsiParam =>
      match b {
        0x00..=0x17 | 0x19 | 0x1c..=0x1f =>
          (ACTION_EXECUTE, ParseState::CsiParam)
        0x18 | 0x1a => (ACTION_EXECUTE, ParseState::Ground)
        0x1b => (ACTION_NONE, ParseState::Escape)
        0x20..=0x2f => (ACTION_NONE, ParseState::CsiIntermediate)
        0x30..=0x39 | 0x3a | 0x3b => (ACTION_NONE, ParseState::CsiParam)
        0x3c..=0x3f => (ACTION_NONE, ParseState::CsiIgnore)
        0x40..=0x7e => (ACTION_CSI_DISPATCH, ParseState::Ground)
        _ => (ACTION_NONE, ParseState::CsiParam)
      }
    ParseState::CsiIntermediate =>
      match b {
        0x00..=0x17 | 0x19 | 0x1c..=0x1f =>
          (ACTION_EXECUTE, ParseState::CsiIntermediate)
        0x18 | 0x1a => (ACTION_EXECUTE, ParseState::Ground)
        0x1b => (ACTION_NONE, ParseState::Escape)
        0x20..=0x2f => (ACTION_NONE, ParseState::CsiIntermediate)
        0x30..=0x3f => (ACTION_NONE, ParseState::CsiIgnore)
        0x40..=0x7e => (ACTION_CSI_DISPATCH, ParseState::Ground)
        _ => (ACTION_NONE, ParseState::CsiIntermediate)
      }
    ParseState::CsiIgnore =>
      match b {
        0x00..=0x17 | 0x19 | 0x1c..=0x1f =>
          (ACTION_EXECUTE, ParseState::CsiIgnore)
        0x18 | 0x1a => (ACTION_EXECUTE, ParseState::Ground)
        0x1b => (ACTION_NONE, ParseState::Escape)
        0x20..=0x3f => (ACTION_NONE, ParseState::CsiIgnore)
        0x40..=0x7e => (ACTION_NONE, ParseState::Ground)
        _ => (ACTION_NONE, ParseState::CsiIgnore)
      }
    ParseState::OscString =>
      match b {
        0x00..=0x06 | 0x08..=0x17 | 0x19 | 0x1c..=0x1f =>
          (ACTION_NONE, ParseState::OscString)
        0x07 => (ACTION_OSC_END, ParseState::Ground)
        0x18 | 0x1a => (ACTION_OSC_END | ACTION_EXECUTE, ParseState::Ground)
        0x1b => (ACTION_OSC_END, ParseState::Escape)
        0x9c => (ACTION_OSC_END, ParseState::Ground)
        _ => (ACTION_OSC_PUT, ParseState::OscString)
      }
    ParseState::DcsEntry =>
      match b {
        0x00..=0x17 | 0x19 | 0x1c..=0x1f => (ACTION_NONE, ParseState::DcsEntry)
        0x18 | 0x1a => (ACTION_EXECUTE, ParseState::Ground)
        0x1b => (ACTION_NONE, ParseState::Escape)
        0x20..=0x2f => (ACTION_NONE, ParseState::DcsIntermediate)
        0x30..=0x39 | 0x3a | 0x3b | 0x3c..=0x3f =>
          (ACTION_NONE, ParseState::DcsParam)
        0x40..=0x7e => (ACTION_HOOK, ParseState::DcsPassthrough)
        _ => (ACTION_NONE, ParseState::DcsEntry)
      }
    ParseState::DcsParam =>
      match b {
        0x00..=0x17 | 0x19 | 0x1c..=0x1f => (ACTION_NONE, ParseState::DcsParam)
        0x18 | 0x1a => (ACTION_EXECUTE, ParseState::Ground)
        0x1b => (ACTION_NONE, ParseState::Escape)
        0x20..=0x2f => (ACTION_NONE, ParseState::DcsIntermediate)
        0x30..=0x39 | 0x3a | 0x3b => (ACTION_NONE, ParseState::DcsParam)
        0x3c..=0x3f => (ACTION_NONE, ParseState::DcsIgnore)
        0x40..=0x7e => (ACTION_HOOK, ParseState::DcsPassthrough)
        _ => (ACTION_NONE, ParseState::DcsParam)
      }
    ParseState::DcsIntermediate =>
      match b {
        0x00..=0x17 | 0x19 | 0x1c..=0x1f =>
          (ACTION_NONE, ParseState::DcsIntermediate)
        0x18 | 0x1a => (ACTION_EXECUTE, ParseState::Ground)
        0x1b => (ACTION_NONE, ParseState::Escape)
        0x20..=0x2f => (ACTION_NONE, ParseState::DcsIntermediate)
        0x30..=0x3f => (ACTION_NONE, ParseState::DcsIgnore)
        0x40..=0x7e => (ACTION_HOOK, ParseState::DcsPassthrough)
        _ => (ACTION_NONE, ParseState::DcsIntermediate)
      }
    ParseState::DcsPassthrough =>
      match b {
        0x00..=0x17 | 0x19 | 0x1c..=0x7e =>
          (ACTION_PUT, ParseState::DcsPassthrough)
        0x18 | 0x1a => (ACTION_UNHOOK | ACTION_EXECUTE, ParseState::Ground)
        0x1b => (ACTION_UNHOOK, ParseState::Escape)
        0x9c => (ACTION_UNHOOK, ParseState::Ground)
        _ => (ACTION_NONE, ParseState::DcsPassthrough)
      }
    ParseState::DcsIgnore =>
      match b {
        0x00..=0x17 | 0x19 | 0x1c..=0x1f => (ACTION_NONE, ParseState::DcsIgnore)
        0x18 | 0x1a => (ACTION_EXECUTE, ParseState::Ground)
        0x1b => (ACTION_NONE, ParseState::Escape)
        0x20..=0x7f => (ACTION_NONE, ParseState::DcsIgnore)
        0x9c => (ACTION_NONE, ParseState::Ground)
        _ => (ACTION_NONE, ParseState::DcsIgnore)
      }
    ParseState::SosPmApcString =>
      match b {
        0x00..=0x17 | 0x19 | 0x1c..=0x1f =>
          (ACTION_NONE, ParseState::SosPmApcString)
        0x18 | 0x1a => (ACTION_EXECUTE, ParseState::Ground)
        0x1b => (ACTION_NONE, ParseState::Escape)
        // The first content byte is the "action" (e.g. `G` for kitty graphics
        // APC `_G`); dispatch it as a hook and reuse the DCS passthrough state.
        0x20..=0x7e => (ACTION_HOOK, ParseState::DcsPassthrough)
        0x9c => (ACTION_NONE, ParseState::Ground)
        _ => (ACTION_NONE, ParseState::SosPmApcString)
      }
    ParseState::Ground => (ACTION_NONE, ParseState::Ground)
  }
}
