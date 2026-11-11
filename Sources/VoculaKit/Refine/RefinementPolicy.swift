import Foundation

public enum RefinementPolicy {
  static let shortestWorthRefining = 12

  public static let longestAcceptableRatio = 3.0

  static let shortestAcceptableRatio = 0.5

  public static func shouldRun(isEnabled: Bool, text: String) -> Bool {
    isEnabled && text.count >= shortestWorthRefining
  }

  static let deadlineBase: Duration = .seconds(2)
  static let deadlinePerCharacter: Duration = .milliseconds(10)

  public static func deadline(for text: String, ceiling: Duration) -> Duration {
    min(ceiling, deadlineBase + deadlinePerCharacter * text.count)
  }

  static let measuredPass: Duration = .milliseconds(480)
  static let measuredPerCharacter: Duration = .microseconds(4_800)

  public static func isSlow(_ took: Duration, characters: Int) -> Bool {
    took > max(measuredPass, measuredPerCharacter * characters) * 2
  }

  public enum Refusal: String, Equatable, Sendable {
    case empty, truncated, runaway, translated, negationChanged, numberLost, questionLost
  }

  public enum Verdict: Equatable, Sendable {
    case accepted(String)
    case unchanged
    case refused(Refusal)
  }

  static func changedAlphabet(from original: String, to produced: String) -> Bool {
    has(.cyrillic, original) != has(.cyrillic, produced)
      || (uses(ukrainianLetters, produced) && !uses(ukrainianLetters, original))
      || (has(.nonCyrillic, original) && !has(.nonCyrillic, produced))
      || (lostOwnLetters(from: original, to: produced)
        && mostWordsAreNew(from: original, to: produced))
  }

  static func lostOwnLetters(from original: String, to produced: String) -> Bool {
    [ukrainianLetters, lettersEnglishLacks].contains { uses($0, original) && !uses($0, produced) }
  }

  static let fewestWordsJudgedByOverlap = 4

  static func replacedMostWords(from original: String, to produced: String) -> Bool {
    words(in: produced).count >= fewestWordsJudgedByOverlap
      && mostWordsAreNew(from: original, to: produced)
  }

  static func mostWordsAreNew(from original: String, to produced: String) -> Bool {
    let spoken = Set(words(in: original))
    let written = words(in: produced)
    return written.filter(spoken.contains).count * 2 < written.count
  }

  static let ukrainianLetters = Set("іїєґ")
  static let lettersEnglishLacks = Set("ąćęłńśźżóäöüßàâæçéèêëîïôœùûÿñáíúãõìò")

  static func uses(_ letters: Set<Character>, _ text: String) -> Bool {
    text.lowercased(with: Locale.invariant).contains(where: letters.contains)
  }

  enum Script { case cyrillic, nonCyrillic }

  static let alphabetLetters: Set<Unicode.GeneralCategory> = [
    .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .otherLetter,
  ]

  static func has(_ script: Script, _ text: String) -> Bool {
    text.unicodeScalars.contains { scalar in
      guard alphabetLetters.contains(scalar.properties.generalCategory) else { return false }
      let isCyrillic = (0x0400...0x04FF).contains(scalar.value)
      return script == .cyrillic ? isCyrillic : !isCyrillic
    }
  }

  static func numbersSurvive(from original: String, to produced: String) -> Bool {
    let before = digits(in: original)
    let after = digits(in: produced)
    let wordsLost = surplus(
      of: NumberWords.groups(in: original), over: NumberWords.groups(in: produced))
    return surplus(of: before, over: after) == 0 && wordsLost <= surplus(of: after, over: before)
  }

  private static func surplus(of these: [String], over those: [String]) -> Int {
    var counts: [String: Int] = [:]
    for item in these { counts[item, default: 0] += 1 }
    for item in those { counts[item, default: 0] -= 1 }
    return counts.values.filter { $0 > 0 }.reduce(0, +)
  }

  static func words(in text: String) -> [String] {
    text.lowercased(with: Locale.invariant)
      .filter { !"'’ʼ".contains($0) }
      .split { !$0.isLetter }
      .map(String.init)
  }

  private static func digits(in text: String) -> [String] {
    text.replacingOccurrences(
      of: #"(?<=\d)[ \u00A0\u2009\u202F,](?=\d{3}(?!\d))"#, with: "", options: .regularExpression
    )
    .components(separatedBy: CharacterSet.decimalDigits.inverted)
    .filter { !$0.isEmpty }
  }

  static func asks(_ text: some StringProtocol) -> Bool {
    text.contains(where: "?？؟".contains)
  }

  public static func verdict(on produced: String, original: String) -> Verdict {
    let folded = SingleLine.collapse(produced.trimmingCharacters(in: .whitespacesAndNewlines))
    guard !folded.isEmpty else { return .refused(.empty) }
    guard Double(folded.count) <= Double(original.count) * longestAcceptableRatio else {
      return .refused(.runaway)
    }
    guard Double(folded.count) >= Double(original.count) * shortestAcceptableRatio else {
      return .refused(.truncated)
    }
    guard !changedAlphabet(from: original, to: folded),
      !replacedMostWords(from: original, to: folded)
    else { return .refused(.translated) }
    guard !Negations.changed(from: original, to: folded) else {
      return .refused(.negationChanged)
    }
    guard numbersSurvive(from: original, to: folded) else { return .refused(.numberLost) }
    guard !asks(original) || asks(folded) else { return .refused(.questionLost) }
    return folded == original ? .unchanged : .accepted(folded)
  }
}
