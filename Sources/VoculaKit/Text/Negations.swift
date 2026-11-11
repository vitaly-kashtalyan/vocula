import Foundation

public enum Negations {
  static let particles: Set<String> = [
    "не", "ни", "ні", "nie", "ani", "not", "no", "non", "não",
  ]

  static let carriers: Set<String> = [
    "нет", "нету", "нема", "немає", "нельзя", "невозможно", "никогда", "никак", "никакой",
    "ничего", "ничто", "никто", "нечего", "некому", "нигде", "никуда", "без",
    "ніколи", "нічого", "ніхто", "ніде",
    "never", "nor", "nothing", "none", "nobody", "nowhere", "without", "neither",
    "nikt", "nic", "nigdy", "żaden", "żadna", "żadne", "żadnego", "bez",
    "nicht", "kein", "keine", "niemals",
    "nunca", "jamás",
    "pas", "jamais", "aucun",
    "mai",
  ]

  static let prefixes = ["не", "ни", "бес", "без", "nie", "un"]

  static let polishLetters = Set("ąćęłńśźż")

  static let polishFillerFollowers: Set<String> = [
    "dobra", "to", "i", "więc", "ale", "tak", "właśnie", "cóż",
  ]

  public static func isNegation(_ word: String) -> Bool {
    particles.contains(word) || carriers.contains(word)
  }

  static func changed(from original: String, to produced: String) -> Bool {
    let before = tokens(in: original)
    let after = tokens(in: produced)
    return count(in: before, against: after) != count(in: after, against: before)
      || aParticleLeftItsWord(before, after)
  }

  private static func count(in words: [String], against other: [String]) -> Int {
    let present = Set(other)
    return words.filter { isNegation($0) || stem(of: $0).map(present.contains) == true }.count
  }

  private static func stem(of word: String) -> String? {
    guard word.count > 4, let prefix = prefixes.first(where: word.hasPrefix) else { return nil }
    return String(word.dropFirst(prefix.count))
  }

  private static func aParticleLeftItsWord(_ before: [String], _ after: [String]) -> Bool {
    let pairsAfter = zip(after, after.dropFirst())
    return zip(before, before.dropFirst()).contains { particle, word in
      particles.contains(particle) && after.contains(word)
        && !pairsAfter.contains { $0 == (particle, word) }
    }
  }

  static func tokens(in text: String) -> [String] {
    let polish = RefinementPolicy.uses(polishLetters, text)
    let lowered = text.lowercased(with: Locale.invariant)
      .replacingOccurrences(of: "n['’ʼ]t", with: " not", options: .regularExpression)
    let words =
      (polish
      ? lowered.replacingOccurrences(of: #"\bno,"#, with: ",", options: .regularExpression)
      : lowered)
      .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
      .map { $0 == "cannot" ? "not" : String($0) }
    return zip(words, words.dropFirst() + [""])
      .filter { word, next in !(polish && word == "no" && polishFillerFollowers.contains(next)) }
      .map(\.0)
  }
}
