import Foundation

enum KeyLabels {
  static func named(
    _ keyCode: UInt16, locale: Locale = .interface,
    bundle: Bundle = .main
  ) -> String? {
    switch keyCode {
    case 0x31:
      return String(
        localized: "key.space", defaultValue: "Space", bundle: bundle, locale: locale,
        comment: "Keycap label for the space bar.")
    case 0x24:
      return String(
        localized: "key.return", defaultValue: "Return", bundle: bundle, locale: locale,
        comment: "Keycap label for the main return key.")
    case 0x4C:
      return String(
        localized: "key.enter", defaultValue: "Enter", bundle: bundle, locale: locale,
        comment: "Keycap label for the numeric keypad's enter key.")
    case 0x30:
      return String(
        localized: "key.tab", defaultValue: "Tab", bundle: bundle, locale: locale,
        comment: "Keycap label for the tab key.")
    case 0x33:
      return String(
        localized: "key.delete", defaultValue: "Delete", bundle: bundle, locale: locale,
        comment: "Keycap label for backspace.")
    case 0x75:
      return String(
        localized: "key.forwardDelete",
        defaultValue: "Forward delete", bundle: bundle, locale: locale,
        comment: "Keycap label for the forward-delete key.")
    case 0x35:
      return String(
        localized: "key.escape", defaultValue: "Esc", bundle: bundle, locale: locale,
        comment: "Keycap label for the escape key.")
    case 0x73:
      return String(
        localized: "key.home", defaultValue: "Home", bundle: bundle, locale: locale,
        comment: "Keycap label for the home key.")
    case 0x77:
      return String(
        localized: "key.end", defaultValue: "End", bundle: bundle, locale: locale,
        comment: "Keycap label for the end key.")
    case 0x74:
      return String(
        localized: "key.pageUp", defaultValue: "Page up", bundle: bundle, locale: locale,
        comment: "Keycap label for page up.")
    case 0x79:
      return String(
        localized: "key.pageDown", defaultValue: "Page down", bundle: bundle, locale: locale,
        comment: "Keycap label for page down.")
    default: return nil
    }
  }

  static func notSet(locale: Locale = .interface, bundle: Bundle = .main) -> String {
    String(
      localized: "key.notSet", defaultValue: "not set", bundle: bundle, locale: locale,
      comment: "Shown where a key binding has none assigned.")
  }

  static func unknown(
    _ keyCode: UInt16, locale: Locale = .interface,
    bundle: Bundle = .main
  ) -> String {
    String(
      localized: "key.unknown", defaultValue: "key \(keyCode)", bundle: bundle, locale: locale,
      comment: "Fallback keycap label; the argument is a hardware key code.")
  }

  static func left(
    _ glyph: String, locale: Locale = .interface,
    bundle: Bundle = .main
  ) -> String {
    String(
      localized: "key.side.left", defaultValue: "left \(glyph)", bundle: bundle, locale: locale,
      comment: "A left-hand modifier; the argument is its glyph, e.g. ⌃.")
  }

  static func right(
    _ glyph: String, locale: Locale = .interface,
    bundle: Bundle = .main
  ) -> String {
    String(
      localized: "key.side.right", defaultValue: "right \(glyph)", bundle: bundle, locale: locale,
      comment: "A right-hand modifier; the argument is its glyph, e.g. ⌘.")
  }
}
