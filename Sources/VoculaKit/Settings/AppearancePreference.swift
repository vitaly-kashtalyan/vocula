import Foundation

public enum AppearancePreference: String, CaseIterable, Sendable, Equatable {
  case system, light, dark

  public static let storageKey = "appearance"
  public static let `default` = AppearancePreference.system

  public init(stored: String?) {
    self = AppearancePreference(rawValue: stored ?? "") ?? .default
  }

  public var title: LocalizedStringResource {
    switch self {
    case .system:
      return LocalizedStringResource(
        "appearance.system", defaultValue: "Match System", bundle: .atURL(Bundle.module.bundleURL),
        comment: "Appearance tile: follow the system's light/dark setting.")
    case .light:
      return LocalizedStringResource(
        "appearance.light", defaultValue: "Light", bundle: .atURL(Bundle.module.bundleURL),
        comment: "Appearance tile: always the light appearance.")
    case .dark:
      return LocalizedStringResource(
        "appearance.dark", defaultValue: "Dark", bundle: .atURL(Bundle.module.bundleURL),
        comment: "Appearance tile: always the dark appearance.")
    }
  }
}
