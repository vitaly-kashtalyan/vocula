import Foundation

public enum BindingVerdict: Equatable, Sendable {
  case allowed
  case warning(String)
  case rejected(String)

  public var key: String? {
    switch self {
    case .allowed: return nil
    case .warning(let key), .rejected(let key): return key
    }
  }
}

public enum BindingBlacklist {
  private enum Key {
    static let escape: UInt16 = 0x35
    static let capsLock: UInt16 = 0x39
    static let tab: UInt16 = 0x30
    static let space: UInt16 = 0x31
    static let q: UInt16 = 0x0C
    static let w: UInt16 = 0x0D
    static let v: UInt16 = 0x09

    static let appleStandard: Set<UInt16> = [
      0x00, 0x0B, 0x08, 0x0E, 0x03, 0x05, 0x04, 0x22, 0x26, 0x2E,
      0x2D, 0x1F, 0x23, 0x01, 0x11, 0x20, 0x07, 0x06, 0x2B, 0x2F, 0x2C,
    ]
  }

  public static func check(_ binding: KeyBinding) -> BindingVerdict {
    if binding.keyCode == Key.capsLock {
      return .rejected("binding.rejected.capsLock")
    }
    if binding.keyCode == Key.escape, binding.modifiers.isEmpty {
      return .rejected("binding.rejected.escape")
    }
    if binding.keyCode != nil, binding.modifiers.isEmpty, binding.klass != .functionKey {
      return .rejected("binding.rejected.bareKey")
    }
    let hasCommand = !binding.modifiers.isDisjoint(with: [.leftCommand, .rightCommand])
    if hasCommand, let code = binding.keyCode {
      switch code {
      case Key.v:
        return .rejected("binding.rejected.commandV")
      case Key.tab:
        return .rejected("binding.rejected.commandTab")
      case Key.space:
        return .rejected("binding.rejected.commandSpace")
      case Key.q:
        return .rejected("binding.rejected.commandQ")
      case Key.w:
        return .rejected("binding.rejected.commandW")
      default:
        break
      }
    }
    if hasCommand, let code = binding.keyCode, Key.appleStandard.contains(code) {
      return .warning("binding.warning.appleStandard")
    }
    if binding.modifiers.contains(.rightOption) {
      return .warning("binding.warning.rightOption")
    }
    if binding.klass == .singleModifier,
      !binding.modifiers.isDisjoint(with: [.leftShift, .rightShift])
    {
      return .warning("binding.warning.doubleShift")
    }
    if binding.keyCode == Key.space,
      !binding.modifiers.isDisjoint(with: [.leftControl, .rightControl])
    {
      return .warning("binding.warning.controlSpace")
    }
    return .allowed
  }

  public static let allMessageKeys: [String] = [
    "binding.rejected.capsLock", "binding.rejected.escape", "binding.rejected.bareKey",
    "binding.rejected.commandV", "binding.rejected.commandTab",
    "binding.rejected.commandSpace", "binding.rejected.commandQ",
    "binding.rejected.commandW", "binding.warning.appleStandard",
    "binding.warning.rightOption", "binding.warning.doubleShift",
    "binding.warning.controlSpace",
  ]

  public static func text(forKey key: String) -> String {
    switch key {
    case "binding.rejected.capsLock":
      return String(
        localized: "binding.rejected.capsLock",
        defaultValue:
          "Caps Lock cannot be assigned: the system treats it specially, with latching and a delay of its own. Turning it into an ordinary key needs driver-level remapping — that is a setting of the machine, not of this app.",
        bundle: .module,
        comment:
          "Why Caps Lock cannot be bound. Load-bearing: this row has no footer of its own and carries the whole explanation."
      )
    case "binding.rejected.escape":
      return String(
        localized: "binding.rejected.escape",
        defaultValue:
          "Esc cancels a recording. Binding to it would make cancelling indistinguishable from starting.",
        bundle: .module,
        comment: "Why Esc cannot be bound. Esc is a key name and is not translated.")
    case "binding.rejected.bareKey":
      return String(
        localized: "binding.rejected.bareKey",
        defaultValue: "An ordinary key with no modifiers: typing would become dictation.",
        bundle: .module,
        comment: "Why a key with no modifiers cannot be bound.")
    case "binding.rejected.commandV":
      return String(
        localized: "binding.rejected.commandV",
        defaultValue:
          "The app synthesises ⌘V itself — a paste would immediately start a new session.",
        bundle: .module,
        comment: "Why ⌘V cannot be bound; the app synthesises it. The chord is never translated.")
    case "binding.rejected.commandTab":
      return String(
        localized: "binding.rejected.commandTab", defaultValue: "⌘Tab switches applications.",
        bundle: .module,
        comment: "Why ⌘Tab cannot be bound. The chord is never translated.")
    case "binding.rejected.commandSpace":
      return String(
        localized: "binding.rejected.commandSpace", defaultValue: "⌘Space opens Spotlight.",
        bundle: .module,
        comment: "Why ⌘Space cannot be bound. Spotlight is macOS's own name.")
    case "binding.rejected.commandQ":
      return String(
        localized: "binding.rejected.commandQ",
        defaultValue: "⌘Q quits the application. An app that breaks ⌘Q is a broken app.",
        bundle: .module,
        comment: "Why ⌘Q cannot be bound.")
    case "binding.rejected.commandW":
      return String(
        localized: "binding.rejected.commandW", defaultValue: "⌘W closes the window.",
        bundle: .module,
        comment: "Why ⌘W cannot be bound.")
    case "binding.warning.appleStandard":
      return String(
        localized: "binding.warning.appleStandard",
        defaultValue:
          "macOS gives this shortcut a standard meaning in every app. Binding it here takes it away from all of them.",
        bundle: .module,
        comment: "Warning that a standard macOS shortcut is being taken over.")
    case "binding.warning.rightOption":
      return String(
        localized: "binding.warning.rightOption",
        defaultValue: "On some layouts the right ⌥ takes part in typing characters.",
        bundle: .module,
        comment: "Warning that the right ⌥ types characters on some layouts.")
    case "binding.warning.doubleShift":
      return String(
        localized: "binding.warning.doubleShift",
        defaultValue: "Double ⇧ is taken in JetBrains IDEs.",
        bundle: .module,
        comment: "Warning that double ⇧ is taken in JetBrains IDEs, which is a product name.")
    case "binding.warning.controlSpace":
      return String(
        localized: "binding.warning.controlSpace",
        defaultValue: "⌃Space switches the input source.",
        bundle: .module,
        comment: "Warning that ⌃Space switches the input source.")
    default:
      return key
    }
  }

  public static func text(for verdict: BindingVerdict) -> String? {
    verdict.key.map(text(forKey:))
  }
}
