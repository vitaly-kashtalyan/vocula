import AppKit
import Carbon.HIToolbox
import VoculaKit

struct SyntheticPaste: PasteSending {
  static func keyCode(for character: String, in layoutData: Data) -> CGKeyCode? {
    (0..<128).map(CGKeyCode.init).first {
      KeyLayout.character(for: $0, in: layoutData) == character
    }
  }

  static var pasteKeyCode: CGKeyCode {
    guard let layout = KeyLayout.currentData(),
      let resolved = keyCode(for: "v", in: layout)
    else { return CGKeyCode(kVK_ANSI_V) }
    return resolved
  }

  static func chord(
    for key: CGKeyCode,
    whileHolding held: CGEventFlags
  ) -> [(key: CGKeyCode, isDown: Bool, flags: CGEventFlags)] {
    let pressed: [(CGKeyCode, Bool, CGEventFlags)] =
      [(key, true, .maskCommand), (key, false, .maskCommand)]
    guard !held.contains(.maskCommand) else { return pressed }
    let command = CGKeyCode(kVK_Command)
    return [(command, true, held.union(.maskCommand))]
      + pressed
      + [(command, false, held.subtracting(.maskCommand))]
  }

  func sendPaste() -> Bool {
    guard let source = CGEventSource(stateID: .hidSystemState) else { return false }
    let held = CGEventSource.flagsState(.hidSystemState)
    let steps = Self.chord(for: Self.pasteKeyCode, whileHolding: held)
    let events = steps.compactMap { step -> CGEvent? in
      let event = CGEvent(
        keyboardEventSource: source,
        virtualKey: step.key, keyDown: step.isDown)
      event?.flags = step.flags
      return event
    }
    guard events.count == steps.count else { return false }

    for event in events {
      event.setIntegerValueField(
        .eventSourceUserData,
        value: SyntheticEventSignature.value)
      event.post(tap: .cghidEventTap)
    }
    return true
  }
}
