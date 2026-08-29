import Carbon.HIToolbox
import Foundation

enum KeyLayout {
  static let symbols: [UInt16: String] = [
    0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑",
    0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5", 0x61: "F6",
    0x62: "F7", 0x64: "F8", 0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
    0x69: "F13", 0x6B: "F14", 0x71: "F15", 0x6A: "F16", 0x40: "F17",
    0x4F: "F18", 0x50: "F19", 0x5A: "F20",
  ]

  static let modifierGlyphs:
    (
      function: String, control: String, option: String,
      shift: String, command: String
    ) =
      ("fn", "⌃", "⌥", "⇧", "⌘")

  static func currentData() -> Data? {
    guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
      let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
    else { return nil }
    return Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
  }

  static func character(for keyCode: CGKeyCode, in layoutData: Data) -> String? {
    var deadKeyState: UInt32 = 0
    var characters = [UniChar](repeating: 0, count: 4)
    var length = 0
    let status = layoutData.withUnsafeBytes { raw -> OSStatus in
      guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress
      else { return OSStatus(paramErr) }
      return UCKeyTranslate(
        layout, UInt16(keyCode), UInt16(kUCKeyActionDown),
        0, UInt32(LMGetKbdType()),
        UInt32(kUCKeyTranslateNoDeadKeysMask),
        &deadKeyState, characters.count, &length, &characters)
    }
    guard status == noErr, length > 0 else { return nil }
    return String(utf16CodeUnits: characters, count: length)
  }
}
