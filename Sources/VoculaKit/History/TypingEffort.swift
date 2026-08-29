import Foundation

public enum TypingEffort {
  public static let wordsPerMinute = 52.0

  public static let charactersPerWord = 5.0

  public static func typingSeconds(characters: Int) -> Double {
    guard characters > 0 else { return 0 }
    return Double(characters) / charactersPerWord / wordsPerMinute * 60
  }
}
