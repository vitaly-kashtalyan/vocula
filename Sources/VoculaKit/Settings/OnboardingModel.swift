import Foundation

public enum OnboardingRowKind: String, Sendable, Equatable, CaseIterable {
  case microphone, accessibility, autostart, globeKey
}

public enum OnboardingStatus: String, Sendable, Equatable, CaseIterable {
  case granted
  case missing
  case restricted
  case needsUserApproval
  case promptDidNotAppear
  case unknown
}

public struct OnboardingRow: Sendable, Equatable {
  public let kind: OnboardingRowKind
  public let status: OnboardingStatus
  public let title: String
  public let explanation: String
  public let actionTitle: String
  public let settingsPath: String?
  public let actionEnabled: Bool
}

public struct OnboardingRowKeys: Sendable, Equatable {
  public let title: String
  public let explanation: String
  public let actionTitle: String
}

public enum OnboardingModel {
  public static let privacyAndSecurityPath = "System Settings → Privacy & Security"
  public static let microphonePath = "System Settings → Privacy & Security → Microphone"
  public static let accessibilityPath = "System Settings → Privacy & Security → Accessibility"
  public static let loginItemsPath = "System Settings → General → Login Items & Extensions"
  public static let keyboardPath = "System Settings → Keyboard → Press 🌐 key to"
  public static let screenTimePath = "System Settings → Screen Time → Content & Privacy"

  public static func rows(
    microphone: OnboardingStatus,
    accessibility: OnboardingStatus,
    autostart: OnboardingStatus,
    globeKeyNeeded: Bool,
    globeKeyDone: Bool
  ) -> [OnboardingRow] {
    var rows = [
      row(kind: .microphone, status: microphone),
      row(kind: .accessibility, status: accessibility),
      row(kind: .autostart, status: autostart),
    ]
    if globeKeyNeeded {
      rows.append(row(kind: .globeKey, status: globeKeyDone ? .granted : .missing))
    }
    return rows
  }

  private static func row(kind: OnboardingRowKind, status: OnboardingStatus) -> OnboardingRow {
    let keys = keys(kind: kind, status: status)
    return OnboardingRow(
      kind: kind, status: status,
      title: text(forKey: keys.title),
      explanation: text(forKey: keys.explanation),
      actionTitle: text(forKey: keys.actionTitle),
      settingsPath: settingsPath(kind: kind, status: status),
      actionEnabled: kind == .autostart || status != .granted)
  }

  private static func settingsPath(kind: OnboardingRowKind, status: OnboardingStatus) -> String? {
    switch kind {
    case .microphone:
      switch status {
      case .missing: return microphonePath
      case .restricted: return screenTimePath
      default: return nil
      }
    case .accessibility:
      return status == .granted ? nil : accessibilityPath
    case .autostart:
      return status == .needsUserApproval ? loginItemsPath : nil
    case .globeKey:
      return status == .granted ? nil : keyboardPath
    }
  }

  public static func text(forKey key: String) -> String {
    switch key {
    case "onboarding.microphone.title":
      return String(
        localized: "onboarding.microphone.title", defaultValue: "Microphone",
        bundle: .module,
        comment:
          "Row title; must match macOS's own Microphone pane name AND this app's own Microphone section."
      )
    case "onboarding.accessibility.title":
      return String(
        localized: "onboarding.accessibility.title", defaultValue: "Accessibility",
        bundle: .module,
        comment: "Row title; must match macOS's own Accessibility pane name.")
    case "onboarding.autostart.title":
      return String(
        localized: "onboarding.autostart.title", defaultValue: "Launch at login",
        bundle: .module,
        comment: "Row title; Login Items is macOS's own name for the pane.")
    case "onboarding.globeKey.title":
      return String(
        localized: "onboarding.globeKey.title", defaultValue: "Press 🌐 key to → Do Nothing",
        bundle: .module,
        comment:
          "Row title. This is macOS's own setting name, verbatim from its Keyboard pane, and 🌐 is the key's own glyph."
      )
    case "onboarding.microphone.explanation.promptDidNotAppear":
      return String(
        localized: "onboarding.microphone.explanation.promptDidNotAppear",
        defaultValue:
          "macOS never showed the prompt, so nothing was refused — and it does not list Vocula under Microphone until the app has asked. Try again. If it stays silent, quit Vocula, run `tccutil reset Microphone app.vocula.mac` in Terminal, and reopen.",
        bundle: .module,
        comment:
          "Must keep saying that NOTHING was refused. The backticked command is typed by the user and is never translated; Terminal is macOS's own app name."
      )
    case "onboarding.microphone.explanation.refusedEarlier":
      return String(
        localized: "onboarding.microphone.explanation.refusedEarlier",
        defaultValue:
          "Refused earlier, and macOS asks only once — the app cannot show that dialog again. Switch it back on yourself.",
        bundle: .module,
        comment:
          "That macOS asks only once is a fact about the platform and must survive translation.")
    case "onboarding.microphone.explanation.restricted":
      return String(
        localized: "onboarding.microphone.explanation.restricted",
        defaultValue:
          "Blocked by a policy on this Mac — you did not refuse anything. Privacy & Security → Microphone cannot switch it on and does not list Vocula while the policy holds. Look in Screen Time → Content & Privacy; if this Mac is managed, its configuration profile decides.",
        bundle: .module,
        comment:
          "Blames the POLICY, never the user. The two pane paths are Apple's own and come from the glossary."
      )
    case "onboarding.microphone.explanation.granted":
      return String(
        localized: "onboarding.microphone.explanation.granted",
        defaultValue:
          "Switched on only while you dictate. Outside a dictation the app hears nothing at all.",
        bundle: .module,
        comment:
          "A PRIVACY statement: the microphone is not open outside a dictation. Must keep saying so."
      )
    case "onboarding.microphone.explanation.willAsk":
      return String(
        localized: "onboarding.microphone.explanation.willAsk",
        defaultValue:
          "Switched on only while you dictate. macOS shows this dialog once per install: if you dismiss it, the app cannot ask again.",
        bundle: .module,
        comment:
          "States the one-shot rule BEFORE the request is made. That macOS asks once per install is a platform fact."
      )
    case "onboarding.accessibility.explanation":
      return String(
        localized: "onboarding.accessibility.explanation",
        defaultValue:
          "So ⌘V can be sent to another application, and so we can ask whether the focused field is a secure one.",
        bundle: .module,
        comment: "Why Accessibility is needed. ⌘V is a key chord and is never translated.")
    case "onboarding.autostart.explanation":
      return String(
        localized: "onboarding.autostart.explanation",
        defaultValue: "Dictation you have to start by hand every time is not dictation.",
        bundle: .module,
        comment: "Why launching at login matters.")
    case "onboarding.autostart.explanation.needsApproval":
      return String(
        localized: "onboarding.autostart.explanation.needsApproval",
        defaultValue:
          "Requires your approval in System Settings. Dictation you have to start by hand every time is not dictation.",
        bundle: .module,
        comment: "Shown while macOS is waiting for the user to approve the login item.")
    case "onboarding.globeKey.explanation":
      return String(
        localized: "onboarding.globeKey.explanation",
        defaultValue:
          "Otherwise the system takes the key for its own dictation or the emoji picker.",
        bundle: .module,
        comment: "Why the globe key must be set to do nothing.")
    case "onboarding.action.tryAgain":
      return String(
        localized: "onboarding.action.tryAgain", defaultValue: "Try again",
        bundle: .module,
        comment: "Asks macOS for the microphone once more. A VERB.")
    case "onboarding.action.openSettings":
      return String(
        localized: "onboarding.action.openSettings", defaultValue: "Open Settings",
        bundle: .module,
        comment: "Opens a macOS System Settings pane. Shared by three rows on purpose.")
    case "onboarding.action.openScreenTime":
      return String(
        localized: "onboarding.action.openScreenTime", defaultValue: "Open Screen Time",
        bundle: .module,
        comment: "Opens macOS's own Screen Time pane.")
    case "onboarding.action.request":
      return String(
        localized: "onboarding.action.request", defaultValue: "Request",
        bundle: .module,
        comment: "Asks macOS for the microphone. A VERB.")
    case "onboarding.action.disable":
      return String(
        localized: "onboarding.action.disable", defaultValue: "Disable",
        bundle: .module,
        comment: "Turns the login item off. A VERB.")
    case "onboarding.action.enable":
      return String(
        localized: "onboarding.action.enable", defaultValue: "Enable",
        bundle: .module,
        comment: "Turns the login item on. A VERB.")
    case "onboarding.action.openKeyboardSettings":
      return String(
        localized: "onboarding.action.openKeyboardSettings",
        defaultValue: "Open Keyboard Settings",
        bundle: .module,
        comment: "Opens macOS's own Keyboard pane.")
    default:
      return key
    }
  }

  public static func keys(
    kind: OnboardingRowKind,
    status: OnboardingStatus
  ) -> OnboardingRowKeys {
    OnboardingRowKeys(
      title: titleKey(kind),
      explanation: explanationKey(kind: kind, status: status),
      actionTitle: actionKey(kind: kind, status: status))
  }

  private static func titleKey(_ kind: OnboardingRowKind) -> String {
    "onboarding.\(kind.rawValue).title"
  }

  private static func explanationKey(
    kind: OnboardingRowKind,
    status: OnboardingStatus
  ) -> String {
    let stem = "onboarding.\(kind.rawValue).explanation"
    switch kind {
    case .microphone:
      switch status {
      case .promptDidNotAppear: return "\(stem).promptDidNotAppear"
      case .missing: return "\(stem).refusedEarlier"
      case .restricted: return "\(stem).restricted"
      case .granted: return "\(stem).granted"
      default: return "\(stem).willAsk"
      }
    case .autostart:
      return status == .needsUserApproval ? "\(stem).needsApproval" : stem
    case .accessibility, .globeKey:
      return stem
    }
  }

  private static func actionKey(
    kind: OnboardingRowKind,
    status: OnboardingStatus
  ) -> String {
    switch kind {
    case .microphone:
      switch status {
      case .promptDidNotAppear: return "onboarding.action.tryAgain"
      case .missing: return "onboarding.action.openSettings"
      case .restricted: return "onboarding.action.openScreenTime"
      default: return "onboarding.action.request"
      }
    case .autostart:
      switch status {
      case .granted: return "onboarding.action.disable"
      case .needsUserApproval: return "onboarding.action.openSettings"
      default: return "onboarding.action.enable"
      }
    case .globeKey:
      return "onboarding.action.openKeyboardSettings"
    case .accessibility:
      return "onboarding.action.openSettings"
    }
  }

  public static let blockingKinds: Set<OnboardingRowKind> =
    [.microphone, .accessibility]

  public static func isComplete(_ rows: [OnboardingRow]) -> Bool {
    incomplete(rows).isEmpty
  }

  public static func incomplete(_ rows: [OnboardingRow]) -> [OnboardingRow] {
    rows.filter { blockingKinds.contains($0.kind) && $0.status != .granted }
  }
}
