import Foundation

public struct TextFilter: TextFiltering {
  private let byLanguage: [String: Set<String>]
  private let fallback: Set<String>

  public init(stopPhrases: [String: [String]] = StopPhrases.byLanguage) {
    byLanguage = stopPhrases.reduce(into: [:]) { result, entry in
      result[entry.key.lowercased(with: .invariant)] = Set(entry.value.map(Self.normalise))
    }
    fallback = Set(StopPhrases.english.map(Self.normalise))
  }

  public func evaluate(_ text: String, language: String?) -> FilterResult {
    let normalised = Self.normalise(text)
    if phrases(for: language).contains(normalised) || Self.isSoundEventTag(normalised) {
      return FilterResult(text: "", wasDroppedAsHallucination: true)
    }
    return FilterResult(text: text, wasDroppedAsHallucination: false)
  }

  private func phrases(for language: String?) -> Set<String> {
    guard let language, let own = byLanguage[language.lowercased(with: .invariant)]
    else { return fallback }
    return own.union(fallback)
  }

  private static let soundEventTag: NSRegularExpression? = {
    let tag = #"(?:\*[^*]*\*|\[[^\[\]]*\]|\([^()]*\)|[♪♫]+[^♪♫]*[♪♫]+)"#
    return try? NSRegularExpression(pattern: "^\(tag)(?:\\s*\(tag))*$")
  }()

  private static func isSoundEventTag(_ normalised: String) -> Bool {
    guard let regex = soundEventTag, !normalised.isEmpty else { return false }
    return regex.firstMatch(
      in: normalised,
      range: NSRange(normalised.startIndex..., in: normalised)) != nil
  }

  private static func normalise(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased(with: .invariant)
      .replacingOccurrences(of: "…", with: "")
      .trimmingCharacters(in: CharacterSet(charactersIn: ".!?,;: "))
  }
}
