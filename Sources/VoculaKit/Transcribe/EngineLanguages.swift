import Foundation

public enum EngineLanguages {
  public static let parakeetCodes: Set<String> = [
    "bg", "cs", "da", "de", "el", "en", "es", "et", "fi", "fr",
    "hr", "hu", "it", "lt", "lv", "mt", "nl", "pl", "pt", "ro",
    "ru", "sk", "sl", "sv", "uk",
  ]

  public static func supports(_ code: String, _ family: ModelFamily) -> Bool {
    switch family {
    case .whisper: return true
    case .parakeet: return parakeetCodes.contains(code)
    }
  }

  public static func narrow(
    _ selection: LanguageSelection, to family: ModelFamily
  ) -> LanguageSelection {
    let kept = selection.codes.filter { supports($0, family) }
    guard !kept.isEmpty else { return .default }
    return LanguageSelection(
      codes: kept, autoDetect: selection.autoDetect, pinned: selection.pinned)
  }
}
