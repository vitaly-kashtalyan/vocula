import Foundation

public struct SystemHotkeyConflict: Equatable, Sendable {
  public let identifier: Int
  public let displayName: String
}

public enum SystemHotkeys {
  static func name(_ identifier: Int) -> String? {
    switch identifier {
    case 7:
      return String(
        localized: "hotkey.menuBar", defaultValue: "Move focus to the menu bar", bundle: .module,
        comment: "macOS Keyboard Shortcuts row name — use that system's own wording.")
    case 27:
      return String(
        localized: "hotkey.dock", defaultValue: "Move focus to the Dock", bundle: .module,
        comment:
          "macOS Keyboard Shortcuts row name — use that system's own wording. Dock is Apple's own name."
      )
    case 32:
      return String(
        localized: "hotkey.missionControl", defaultValue: "Mission Control", bundle: .module,
        comment:
          "macOS Keyboard Shortcuts row name — Apple keeps this name untranslated in most languages; check that system."
      )
    case 33:
      return String(
        localized: "hotkey.applicationWindows", defaultValue: "Application windows",
        bundle: .module,
        comment: "macOS Keyboard Shortcuts row name — use that system's own wording.")
    case 36:
      return String(
        localized: "hotkey.showDesktop", defaultValue: "Show desktop", bundle: .module,
        comment: "macOS Keyboard Shortcuts row name — use that system's own wording.")
    case 60:
      return String(
        localized: "hotkey.previousInputSource", defaultValue: "Select the previous input source",
        bundle: .module,
        comment: "macOS Keyboard Shortcuts row name — use that system's own wording.")
    case 61:
      return String(
        localized: "hotkey.nextInputSource", defaultValue: "Select the next input source",
        bundle: .module,
        comment: "macOS Keyboard Shortcuts row name — use that system's own wording.")
    case 64:
      return String(
        localized: "hotkey.spotlight", defaultValue: "Spotlight", bundle: .module,
        comment:
          "macOS Keyboard Shortcuts row name — Spotlight is Apple's product name and is not translated."
      )
    case 65:
      return String(
        localized: "hotkey.spotlightFinder", defaultValue: "Spotlight search in Finder",
        bundle: .module,
        comment: "macOS Keyboard Shortcuts row name — Spotlight and Finder are Apple's names.")
    case 79:
      return String(
        localized: "hotkey.spaceLeft", defaultValue: "Move one space left", bundle: .module,
        comment: "macOS Keyboard Shortcuts row name — a Space is Apple's desktop, not a blank.")
    case 81:
      return String(
        localized: "hotkey.spaceRight", defaultValue: "Move one space right", bundle: .module,
        comment: "macOS Keyboard Shortcuts row name — a Space is Apple's desktop, not a blank.")
    case 98:
      return String(
        localized: "hotkey.help", defaultValue: "Help", bundle: .module,
        comment: "macOS Keyboard Shortcuts row name — use that system's own wording.")
    case 160:
      return String(
        localized: "hotkey.launchpad", defaultValue: "Launchpad", bundle: .module,
        comment: "macOS Keyboard Shortcuts row name — Launchpad is Apple's product name.")
    case 162:
      return String(
        localized: "hotkey.notificationCentre", defaultValue: "Notification Centre",
        bundle: .module,
        comment:
          "macOS Keyboard Shortcuts row name — use that system's own wording, and its own spelling."
      )
    case 175:
      return String(
        localized: "hotkey.quickNote", defaultValue: "Quick Note", bundle: .module,
        comment: "macOS Keyboard Shortcuts row name — Apple's feature name.")
    default: return nil
    }
  }

  public static func conflict(for binding: KeyBinding, in defaults: [String: Any])
    -> SystemHotkeyConflict?
  {
    guard let keyCode = binding.keyCode,
      let entries = defaults["AppleSymbolicHotKeys"] as? [String: Any]
    else { return nil }
    for (key, raw) in entries {
      guard let identifier = Int(key),
        let entry = raw as? [String: Any],
        (entry["enabled"] as? Bool) ?? false,
        let value = entry["value"] as? [String: Any],
        let parameters = value["parameters"] as? [Int],
        parameters.count >= 3
      else { continue }
      guard UInt16(exactly: parameters[1]) == keyCode,
        UInt32(bitPattern: Int32(parameters[2])) == binding.modifiers.carbonMask
      else { continue }
      return SystemHotkeyConflict(
        identifier: identifier,
        displayName: name(identifier)
          ?? String(
            localized: "hotkey.unknown",
            defaultValue: "system action #\(String(identifier))", bundle: .module,
            comment:
              "Fallback when this table has gone stale against a macOS release; the argument is a numeric identifier and is never translated."
          ))
    }
    return nil
  }

  public static func systemDefaults() -> [String: Any] {
    UserDefaults(suiteName: "com.apple.symbolichotkeys")?
      .persistentDomain(forName: "com.apple.symbolichotkeys") ?? [:]
  }
}
