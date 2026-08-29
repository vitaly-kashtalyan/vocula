import Foundation

public struct InterfaceLanguage: Equatable, Sendable, Identifiable {
  public let code: String
  public let name: String
  public var id: String { code }

  public init(code: String, name: String) {
    self.code = code
    self.name = name
  }
}

public enum InterfaceLanguages {
  public static let systemCode = ""
  public static let defaultsKey = "AppleLanguages"

  public static func available(
    in localizations: [String],
    displayIn locale: Locale = .interface
  ) -> [InterfaceLanguage] {
    localizations
      .filter { $0 != "Base" }
      .map { code in
        InterfaceLanguage(code: code, name: displayName(of: code, in: locale))
      }
      .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  public static func displayName(of code: String, in interface: Locale) -> String {
    let own = Locale(identifier: code)
    let endonym =
      own.localizedString(forIdentifier: code)
      ?? own.localizedString(forLanguageCode: code)
    guard let endonym, !endonym.isEmpty else { return code }
    return endonym.capitalized(with: own)
  }

  public static func selected(stored: [String]?, available: [String]) -> String {
    guard let code = stored?.first, available.contains(code) else { return systemCode }
    return code
  }

  public static func override(for code: String) -> [String]? {
    code == systemCode ? nil : [code]
  }
}
