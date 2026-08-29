import ServiceManagement
import VoculaKit

@MainActor
enum LoginItem {
  private static let initialAttemptKey = "autostart.initialRegistrationAttempted"

  static func status() -> OnboardingStatus {
    switch SMAppService.mainApp.status {
    case .enabled: return .granted
    case .requiresApproval: return .needsUserApproval
    case .notRegistered, .notFound: return .missing
    @unknown default: return .unknown
    }
  }

  @discardableResult
  static func register() -> OnboardingStatus {
    do {
      try SMAppService.mainApp.register()
    } catch {
      let current = status()
      if current == .granted || current == .needsUserApproval {
        lastError = nil
        return current
      }
      lastError =
        Bundle.main.bundleURL.path.hasPrefix("/Applications")
        ? error.localizedDescription
        : String(
          localized: "loginItem.notInApplications",
          defaultValue: "Launch at login needs the app to live in /Applications.",
          comment: "/Applications is a filesystem path and is never translated.")
      return .missing
    }
    lastError = nil
    return status()
  }

  private(set) static var lastError: String?

  static func registerIfNeverAsked(defaults: UserDefaults = .standard) {
    guard !VoculaAppDelegate.isSecondCopy else { return }
    guard !defaults.bool(forKey: initialAttemptKey) else { return }
    let result = register()
    if result == .granted || result == .needsUserApproval {
      defaults.set(true, forKey: initialAttemptKey)
    }
  }

  static func recordUserChoice(defaults: UserDefaults = .standard) {
    defaults.set(true, forKey: initialAttemptKey)
  }

  static func unregister() {
    do {
      try SMAppService.mainApp.unregister()
      lastError = nil
    } catch {
      lastError = error.localizedDescription
    }
  }
}
