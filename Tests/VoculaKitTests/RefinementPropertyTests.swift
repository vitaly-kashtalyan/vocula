import Foundation
import Testing

@testable import VoculaKit

private func verdict(_ produced: String, _ original: String) -> RefinementPolicy.Verdict {
  RefinementPolicy.verdict(on: produced, original: original)
}

private func isKept(_ verdict: RefinementPolicy.Verdict, as produced: String) -> Bool {
  verdict == .unchanged || verdict == .accepted(produced)
}

@Suite("Every meaning-changing mutation of a clean-up is refused")
struct CleanupMutationTests {
  @Test(
    "dropping a negation particle is refused",
    arguments: CleanupCorpus.with { !$0.particleIndices.isEmpty })
  func droppedParticle(_ sentence: Dictated) {
    for index in sentence.particleIndices {
      var tokens = sentence.tokens
      tokens.remove(at: index)
      let produced = Dictated.render(tokens)
      #expect(verdict(produced, sentence.spoken) == .refused(.negationChanged), "\(produced)")
    }
  }

  @Test("adding a negation particle anywhere is refused", arguments: CleanupCorpus.all)
  func addedParticle(_ sentence: Dictated) {
    for position in 0...sentence.tokens.count {
      var tokens = sentence.tokens
      tokens.insert(sentence.tongue.particle, at: position)
      let produced = Dictated.render(tokens)
      #expect(verdict(produced, sentence.spoken) == .refused(.negationChanged), "\(produced)")
    }
  }

  @Test(
    "dropping or adding n't is refused, whichever apostrophe spells it",
    arguments: CleanupCorpus.with(\.isContracted), ["'", "’", "ʼ"])
  func contraction(_ sentence: Dictated, apostrophe: String) {
    let negative = sentence.spoken(apostrophe: apostrophe)
    #expect(verdict(sentence.positive, negative) == .refused(.negationChanged))
    #expect(verdict(negative, sentence.positive) == .refused(.negationChanged))
  }

  @Test(
    "moving a negation particle onto another word is refused",
    arguments: CleanupCorpus.with { !$0.particleIndices.isEmpty })
  func movedParticle(_ sentence: Dictated) {
    for index in sentence.particleIndices {
      var rest = sentence.tokens
      let particle = rest.remove(at: index)
      let negated = Dictated.word(rest[index])
      for position in 0...rest.count where position != index {
        guard position == rest.count || Dictated.word(rest[position]) != negated else { continue }
        var tokens = rest
        tokens.insert(particle, at: position)
        let produced = Dictated.render(tokens)
        #expect(verdict(produced, sentence.spoken) == .refused(.negationChanged), "\(produced)")
      }
    }
  }

  @Test(
    "dropping a run of digits, or changing any one digit, is refused",
    arguments: CleanupCorpus.with { $0.spoken.contains(where: \.isNumber) })
  func digits(_ sentence: Dictated) {
    let spoken = sentence.spoken
    for run in spoken.matches(of: #/\d+/#) {
      var produced = spoken
      produced.removeSubrange(run.range)
      #expect(verdict(produced, spoken) == .refused(.numberLost), "\(produced)")
    }
    for index in spoken.indices where spoken[index].isNumber {
      let digit = spoken[index].wholeNumberValue!
      var produced = spoken
      produced.replaceSubrange(index...index, with: String((digit + 1) % 10))
      #expect(verdict(produced, spoken) == .refused(.numberLost), "\(produced)")
    }
  }

  @Test(
    "dropping a number spoken as words, or its last word, is refused",
    arguments: CleanupCorpus.with { !$0.numbers.isEmpty })
  func numberWords(_ sentence: Dictated) {
    for (index, number) in sentence.numbers.enumerated() {
      let dropped = sentence.spoken(replacingNumber: index) { _, _ in "" }
      #expect(verdict(dropped, sentence.spoken) == .refused(.numberLost), "\(dropped)")
      let words = number.words.split(separator: " ")
      guard words.count > 1 else { continue }
      let shortened = sentence.spoken(replacingNumber: index) { _, _ in
        words.dropLast().joined(separator: " ")
      }
      #expect(verdict(shortened, sentence.spoken) == .refused(.numberLost), "\(shortened)")
    }
  }

  @Test(
    "a question that comes back as a statement is refused",
    arguments: CleanupCorpus.with { $0.spoken.hasSuffix("?") })
  func questionLost(_ sentence: Dictated) {
    let statement = String(sentence.spoken.dropLast())
    #expect(verdict(statement + ".", sentence.spoken) == .refused(.questionLost))
    #expect(verdict(statement, sentence.spoken) == .refused(.questionLost))
  }

  @Test(
    "a translation into any other of the four languages is refused",
    arguments: [
      (
        "Почему тесты падают только на CI, а локально всё зелёное?",
        "Why do the tests fail only on CI while everything is green locally?"
      ),
      (
        "Листья можно убрать в дальнем углу у забора, пока сухо.",
        "Листя можна прибрати в дальньому кутку біля паркану, поки сухо."
      ),
      (
        "Можно ли запустить деплой в staging до обеда?",
        "Czy można uruchomić deploy na staging przed obiadem?"
      ),
      (
        "Залей ветку в гитхаб и открой pull request на ревью.",
        "Push the branch to GitHub and open a pull request for review."
      ),
      ("Can you review the pull request before lunch?", "Можешь посмотреть pull request до обеда?"),
      (
        "The garden hose leaks at the tap, so turn the water off.",
        "Wąż ogrodowy cieknie przy kranie, więc zakręć wodę."
      ),
      (
        "The garden hose leaks at the tap, so turn the water off.",
        "Садовий шланг протікає біля крана, тому перекрий воду."
      ),
      (
        "Kup cztery jabłka i chleb w sklepie na rogu.",
        "Buy four apples and bread at the shop on the corner."
      ),
      (
        "Nie chcę zmieniać konfiguracji, ale muszę dodać nowy klucz.",
        "Не хочу менять конфигурацию, но должен добавить новый ключ."
      ),
      (
        "Czy możesz przejrzeć ten kod przed obiadem?",
        "Can you look through this code before lunch?"
      ),
      (
        "Чи можеш ти переглянути цей код до обіду?",
        "Можешь ли ты просмотреть этот код до обеда?"
      ),
      (
        "Потяг відправляється о 8:15 з першої платформи.",
        "The train leaves at 8:15 from the first platform."
      ),
      ("Я зараз працюю вдома, приходь до мене", "Я сейчас работаю дома, приходи ко мне."),
    ])
  func translated(original: String, produced: String) {
    #expect(verdict(produced, original) == .refused(.translated))
  }

  @Test("a tail cut below half of the text is refused", arguments: CleanupCorpus.all)
  func truncated(_ sentence: Dictated) {
    let kept = String(sentence.spoken.prefix(sentence.spoken.count * 45 / 100))
    #expect(verdict(kept, sentence.spoken) == .refused(.truncated), "\(kept)")
  }

  @Test("a line break is folded back into a space, never refused", arguments: CleanupCorpus.all)
  func lineBreak(_ sentence: Dictated) {
    let spoken = sentence.spoken
    for space in spoken.indices where spoken[space] == " " {
      for lineBreak in ["\n", "\r\n", "\u{2028}", " \n\t "] {
        var produced = spoken
        produced.replaceSubrange(space...space, with: lineBreak)
        #expect(verdict(produced, spoken) == .unchanged, "\(produced.debugDescription)")
      }
    }
    #expect(verdict(spoken + "\n", spoken) == .unchanged)
  }

  @Test("an answer appended to the clean-up is refused as runaway", arguments: CleanupCorpus.all)
  func runaway(_ sentence: Dictated) {
    let answer = String(
      repeating: " Here is a more detailed explanation of what this means.",
      count: sentence.spoken.count / 20 + 1)
    #expect(verdict(sentence.spoken + answer, sentence.spoken) == .refused(.runaway))
  }
}

@Suite("Every benign clean-up is accepted")
struct CleanupAcceptanceTests {
  private static func raw(_ written: String) -> String {
    let lowered = written.prefix(1).lowercased(with: Locale.invariant) + written.dropFirst()
    return lowered.hasSuffix(".") ? String(lowered.dropLast()) : lowered
  }

  @Test(
    "dropping any set of filler words is accepted",
    arguments: CleanupCorpus.with { $0.fillerCount > 0 })
  func fillers(_ sentence: Dictated) {
    for mask in 1..<(1 << sentence.fillerCount) {
      let produced = sentence.spoken(droppingFillers: mask)
      #expect(isKept(verdict(produced, sentence.spoken), as: produced), "\(produced)")
    }
  }

  @Test("a capital and a final period are accepted", arguments: CleanupCorpus.all)
  func capitalAndPeriod(_ sentence: Dictated) {
    let written = sentence.spoken
    #expect(verdict(written, Self.raw(written)) == .accepted(written))
  }

  @Test(
    "a comma moved against its word is accepted",
    arguments: CleanupCorpus.with { $0.spoken.contains(", ") })
  func commaSpacing(_ sentence: Dictated) {
    let written = sentence.spoken
    for loose in [" , ", ",", " ,"] {
      let spoken = written.replacingOccurrences(of: ", ", with: loose)
      #expect(verdict(written, spoken) == .accepted(written), "\(spoken)")
    }
  }

  @Test(
    "a number spoken as words and written as its digits is accepted",
    arguments: CleanupCorpus.with { !$0.numbers.isEmpty })
  func digitsForWords(_ sentence: Dictated) {
    for index in sentence.numbers.indices {
      let produced = sentence.spoken(replacingNumber: index) { _, value in String(value) }
      #expect(verdict(produced, sentence.spoken) == .accepted(produced), "\(produced)")
    }
    #expect(verdict(sentence.withDigits, sentence.spoken) == .accepted(sentence.withDigits))
  }

  @Test(
    "a brand the recogniser spelled in Cyrillic may be written in Latin",
    arguments: CleanupCorpus.with { $0.spoken.contains("гитхаб") || $0.spoken.contains("гітхаб") })
  func brandInLatin(_ sentence: Dictated) {
    let produced = sentence.spoken.replacingOccurrences(of: "гитхаб", with: "GitHub")
      .replacingOccurrences(of: "гітхаб", with: "GitHub")
    #expect(verdict(produced, sentence.spoken) == .accepted(produced))
  }

  @Test(
    "an apostrophe written in another style is accepted",
    arguments: CleanupCorpus.with { $0.marked.contains("'") }, ["'", "’", "ʼ"])
  func apostropheStyle(_ sentence: Dictated, spokenWith apostrophe: String) {
    let spoken = sentence.spoken(apostrophe: apostrophe)
    for written in ["'", "’", "ʼ"].map(sentence.spoken(apostrophe:)) {
      #expect(isKept(verdict(written, spoken), as: written), "\(spoken) → \(written)")
    }
  }

  @Test("every benign clean-up at once is accepted", arguments: CleanupCorpus.all)
  func everythingAtOnce(_ sentence: Dictated) {
    let written = Dictated.render(sentence.tokens.filter { !$0.hasPrefix("~") }) { _, _, value in
      String(value)
    }
    let produced = (written.prefix(1).uppercased(with: Locale.invariant) + written.dropFirst())
      .replacingOccurrences(of: "гитхаб", with: "GitHub")
      .replacingOccurrences(of: "гітхаб", with: "GitHub")
    #expect(verdict(produced, Self.raw(sentence.spoken)) == .accepted(produced), "\(produced)")
  }
}

@Suite("What the clean-up guards deliberately cannot see")
struct CleanupLimitTests {
  @Test(
    "LIMIT: a number word replaced by the wrong digit is accepted, because a new digit pays for it",
    arguments: CleanupCorpus.with { !$0.numbers.isEmpty })
  func wrongDigitForAWord(_ sentence: Dictated) {
    for index in sentence.numbers.indices {
      let produced = sentence.spoken(replacingNumber: index) { _, value in String(value + 1) }
      #expect(verdict(produced, sentence.spoken) == .accepted(produced), "\(produced)")
    }
  }

  @Test("LIMIT: a particle moved onto a second copy of its word is not seen")
  func particleBetweenCopiesOfOneWord() {
    let produced = "Надо делать, не надо ждать."
    #expect(verdict(produced, "Не надо делать, надо ждать.") == .accepted(produced))
  }

  @Test("LIMIT: a negating word that is not a particle may move to another verb")
  func carrierMoves() {
    let produced = "We deploy on Fridays, we never test on Mondays."
    #expect(
      verdict(produced, "We never deploy on Fridays, we test on Mondays.") == .accepted(produced))
  }

  @Test(
    "LIMIT: a translation of three words in one alphabet is too short to judge by overlap",
    arguments: [("Kup mleko teraz", "Buy milk now."), ("Зараз зроблю це", "Сейчас сделаю это.")])
  func shortTranslation(original: String, produced: String) {
    #expect(verdict(produced, original) == .accepted(produced))
  }

  @Test("LIMIT: a cut that keeps more than half of the text is accepted as tightening")
  func cutAboveHalf() {
    let produced = "Листья можно убрать в дальнем углу."
    #expect(
      verdict(produced, "Листья можно убрать в дальнем углу у забора, пока сухо.")
        == .accepted(produced))
  }

  @Test("LIMIT: an edge space that only the trim removes comes back accepted and trimmed")
  func edgeSpaceIsTrimmed() {
    let text = "\u{3000}Готово, проверь\u{200B}"
    #expect(verdict(text, text) == .accepted("Готово, проверь"))
  }

  @Test("ACCEPTED COST: heavy filler cleaned below half of the text is refused as truncated")
  func heavyFillerReadsAsTruncation() {
    #expect(
      verdict("Сделаю завтра.", "ну вот короче типа да сделаю завтра")
        == .refused(.truncated))
  }

  @Test("ACCEPTED COST: a comma between two numbers, the second of three digits, splits a group")
  func commaSplitsADigitGroup() {
    #expect(
      verdict("Закрыты этажи 3, 150 и 7.", "закрыты этажи 3 150 и 7") == .refused(.numberLost))
  }

  @Test("LIMIT: a \"no,\" in English beside a Polish name is read as Polish filler")
  func englishNoBesideAPolishName() {
    let produced = "Tell Paweł it is ready."
    #expect(verdict(produced, "Tell Paweł no, it is ready") == .accepted(produced))
  }
}

@Suite("The clean-up verdict under fuzz")
struct CleanupVerdictFuzzTests {
  private static let fragments: [String] =
    [
      "", " ", "  ", "\n", "\r\n", "\r", "\t", "\u{2028}", "\u{2029}", "\u{85}", "\u{0B}", "\u{0C}",
      "\u{00A0}", "\u{3000}", "\u{200B}", "\u{FEFF}", "👍🏽", "🇺🇦", "👨‍👩‍👧", "مرحبا، كيف حالك؟",
      "שלום עולם", "\u{200F}", "\u{202E}", "e\u{301}", "и\u{306}", "Z\u{336}\u{334}a\u{335}",
      "\u{301}", "٣", "３", "𝟓", "1 000", "3,5", "7:45", "0", "?", "؟", "？", ".", ",", "...", "'",
      "’", "ʼ", "n't", "nʼt", "не", "not", "nie", "no", "ні", "две", "two", "trzy", "п'ять",
      "гитхаб", "GitHub", "\u{0}",
    ] + CleanupCorpus.all.flatMap { $0.spoken.split(separator: " ").map(String.init) }

  private static func noise(_ rng: inout SeededRandom) -> String {
    (0..<Int.random(in: 0...8, using: &rng))
      .map { _ in fragments.randomElement(using: &rng)! + (Bool.random(using: &rng) ? " " : "") }
      .joined()
  }

  private static func near(_ original: String, _ rng: inout SeededRandom) -> String {
    var characters = Array(original)
    let index = Int.random(in: 0...characters.count, using: &rng)
    characters.insert(contentsOf: noise(&rng), at: index)
    if !characters.isEmpty, Bool.random(using: &rng) {
      characters.remove(at: Int.random(in: 0..<characters.count, using: &rng))
    }
    return String(characters)
  }

  @Test("no pair crashes it, and an accepted text never carries a line break")
  func acceptedIsOneLine() {
    var rng = SeededRandom(seed: 0x5EED_0001)
    var accepted = 0
    for _ in 0..<2_000 {
      let original =
        Bool.random(using: &rng)
        ? CleanupCorpus.all.randomElement(using: &rng)!.spoken : Self.noise(&rng)
      let produced = Bool.random(using: &rng) ? Self.near(original, &rng) : Self.noise(&rng)
      guard case .accepted(let text) = verdict(produced, original) else { continue }
      accepted += 1
      #expect(!text.contains { $0.isNewline }, "\(produced.debugDescription)")
      #expect(
        !text.unicodeScalars.contains { CharacterSet.newlines.contains($0) },
        "\(produced.debugDescription)")
      #expect(!text.isEmpty)
    }
    #expect(accepted > 250, "only \(accepted) pairs were accepted — the fuzz checks nothing")
  }

  @Test("a one-line text handed back exactly as it came is unchanged")
  func identityIsUnchanged() {
    var rng = SeededRandom(seed: 0x5EED_0002)
    var checked = 0
    for _ in 0..<2_000 {
      let raw =
        Bool.random(using: &rng)
        ? Self.near(CleanupCorpus.all.randomElement(using: &rng)!.spoken, &rng)
        : Self.noise(&rng)
      let text = SingleLine.collapse(raw.trimmingCharacters(in: .whitespacesAndNewlines))
      guard !text.isEmpty else { continue }
      checked += 1
      #expect(verdict(text, text) == .unchanged, "\(text.debugDescription)")
    }
    #expect(checked > 1_000)
  }
}
