import Foundation

public enum StopPhrases {
  public static let english: [String] = [
    "thanks for watching",
    "thank you for watching",
    "subscribe to my channel",
  ]

  public static let byLanguage: [String: [String]] = [
    "en": english,
    "fr": ["sous-titrage société radio-canada", "sous-titrage st' 501"],
    "uk": ["дякую за перегляд"],
    "ru": ["продолжение следует"],
  ]

  public static func forLanguage(_ code: String?) -> [String] {
    let key = code?.lowercased(with: .invariant)
    guard let key, let own = byLanguage[key], key != "en"
    else { return english }
    return own + english
  }
}
