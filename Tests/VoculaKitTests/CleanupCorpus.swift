import Foundation
import Testing

@testable import VoculaKit

struct SeededRandom: RandomNumberGenerator {
  private var state: UInt64

  init(seed: UInt64) { state = seed }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var mixed = state
    mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
    mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
    return mixed ^ (mixed >> 31)
  }
}

enum Tongue: String, Sendable {
  case ru, en, pl, uk

  var particle: String {
    switch self {
    case .en: "not"
    case .pl: "nie"
    case .ru, .uk: "не"
    }
  }
}

struct Dictated: Sendable, CustomTestStringConvertible {
  let tongue: Tongue
  let marked: String

  init(_ tongue: Tongue, _ marked: String) {
    self.tongue = tongue
    self.marked = marked
  }

  var testDescription: String { spoken }

  var tokens: [String] { marked.split(separator: " ").map(String.init) }

  var spoken: String { Self.render(tokens) }

  var withDigits: String { Self.render(tokens) { _, _, value in String(value) } }

  var numbers: [(words: String, value: Int)] {
    marked.matches(of: Self.numberSpan).map { (String($0.output.1), Int($0.output.2)!) }
  }

  func spoken(replacingNumber target: Int, with replacement: (String, Int) -> String) -> String {
    Self.render(tokens) { index, words, value in
      index == target ? replacement(words, value) : words
    }
  }

  var fillerCount: Int { tokens.filter { $0.hasPrefix("~") }.count }

  func spoken(droppingFillers mask: Int) -> String {
    var seen = -1
    return Self.render(
      tokens.filter { token in
        guard token.hasPrefix("~") else { return true }
        seen += 1
        return mask & (1 << seen) == 0
      })
  }

  var particleIndices: [Int] {
    tokens.indices.filter {
      !tokens[$0].hasPrefix("~") && Negations.particles.contains(Self.word(tokens[$0]))
    }
  }

  static let contractions = ["doesn't": "does", "don't": "do", "isn't": "is", "can't": "can"]

  var isContracted: Bool { tokens.contains { Self.contraction(in: $0) != nil } }

  var positive: String {
    Self.render(
      tokens.map { token in
        guard let core = Self.contraction(in: token) else { return token }
        return token.replacingOccurrences(of: core, with: Self.contractions[core]!)
      })
  }

  func spoken(apostrophe: String) -> String {
    spoken.replacingOccurrences(of: "'", with: apostrophe)
  }

  static func word(_ token: some StringProtocol) -> String {
    token.lowercased(with: Locale.invariant).filter(\.isLetter)
  }

  static func render(
    _ tokens: [String],
    number: (Int, String, Int) -> String = { _, words, _ in words }
  ) -> String {
    let joined = tokens.joined(separator: " ")
    var result = ""
    var cursor = joined.startIndex
    for (index, match) in joined.matches(of: numberSpan).enumerated() {
      result += joined[cursor..<match.range.lowerBound]
      result += number(index, String(match.output.1), Int(match.output.2)!)
      cursor = match.range.upperBound
    }
    result += joined[cursor...]
    return result.replacingOccurrences(of: "~", with: "")
      .split(separator: " ").joined(separator: " ")
  }

  private static func contraction(in token: String) -> String? {
    let core = token.trimmingCharacters(in: .punctuationCharacters).lowercased(
      with: Locale.invariant)
    return contractions[core] == nil ? nil : core
  }

  private static var numberSpan: Regex<(Substring, Substring, Substring)> {
    #/\[([^|\]]+)\|(\d+)\]/#
  }
}

enum CleanupCorpus {
  static let all: [Dictated] = [
    Dictated(.ru, "~Ну, ~короче, сборка не проходит на сервере уже второй день."),
    Dictated(.ru, "Купи [четыре|4] пачки макарон и [две|2] банки томатной пасты."),
    Dictated(.ru, "Почему тесты падают только на CI, а локально всё зелёное?"),
    Dictated(.ru, "Залей ветку в гитхаб и открой pull request на ревью."),
    Dictated(.ru, "~Вот, сервер перезагрузится через 15 минут, не трогай его."),
    Dictated(.ru, "Я не хочу обновлять Xcode, но придётся поставить новую версию."),
    Dictated(.ru, "~Кстати, встречу перенесли на [пять|5] часов вечера в пятницу."),
    Dictated(.ru, "Можно ли запустить деплой в staging до обеда?"),
    Dictated(.ru, "~Типа, этот скрипт удаляет логи старше 30 дней."),
    Dictated(.ru, "Обнови зависимости до версии 3.5 и прогони тесты ещё раз."),
    Dictated(.ru, "Никто не проверял, работает ли кэш после рестарта."),
    Dictated(.ru, "Листья можно убрать в дальнем углу у забора, пока сухо."),
    Dictated(.ru, "Нужно заказать [двадцать пять|25] стульев для нового офиса."),
    Dictated(.ru, "Заплатили 1 500 рублей за доставку дивана."),
    Dictated(.ru, "~Ну, а этот гитхаб экшен вообще не запускается?"),
    Dictated(.en, "~Um, the build doesn't pass on the staging server since Monday."),
    Dictated(.en, "Can you review the pull request before lunch?"),
    Dictated(.en, "I don't want to rewrite the parser, but we need a faster one."),
    Dictated(.en, "The cache, ~like, expires after 15 minutes and nobody notices."),
    Dictated(.en, "Add [three|3] more tests for the date parser."),
    Dictated(.en, "Why does the deploy script fail only on Fridays?"),
    Dictated(.en, "We will not ship the update this week because the docs are missing."),
    Dictated(.en, "Order [twenty|20] chairs and [two|2] tables for the new office."),
    Dictated(.en, "The garden hose leaks at the tap, so turn the water off."),
    Dictated(.en, "Rename the branch to release 2.4 and push it again."),
    Dictated(.en, "It isn't raining yet, so the windows can stay open."),
    Dictated(.en, "~Um, I can't find the config file in the repository."),
    Dictated(.pl, "~No dobra, zrobię to jutro rano przed spotkaniem."),
    Dictated(.pl, "Serwer nie odpowiada od [trzech|3] godzin, sprawdź logi."),
    Dictated(.pl, "Czy możesz przejrzeć ten kod przed obiadem?"),
    Dictated(.pl, "Kup [cztery|4] jabłka i chleb w sklepie na rogu."),
    Dictated(.pl, "Nigdy nie wdrażamy zmian w piątek po południu."),
    Dictated(.pl, "Build przechodzi lokalnie, ale na CI wciąż jest czerwony."),
    Dictated(.pl, "Nie chcę zmieniać konfiguracji, ale muszę dodać nowy klucz."),
    Dictated(.pl, "Pociąg odjeżdża o 7:45 z drugiego peronu."),
    Dictated(.uk, "~Ну, ~типу, сервер не відповідає вже [дві|2] години."),
    Dictated(.uk, "Чи можеш ти переглянути цей код до обіду?"),
    Dictated(.uk, "Я не хочу оновлювати систему, але мушу встановити патч."),
    Dictated(.uk, "Купи [три|3] пакети молока і хліб у магазині."),
    Dictated(.uk, "Потяг відправляється о 8:15 з першої платформи."),
    Dictated(.uk, "Ніхто не перевіряв, чи працює кеш після перезапуску."),
    Dictated(.uk, "Залий зміни на гітхаб і запусти збірку ще раз."),
    Dictated(.uk, "Пам'ять на сервері закінчується, перезапусти його."),
  ]

  static func with(_ feature: (Dictated) -> Bool) -> [Dictated] { all.filter(feature) }
}

@Suite("The clean-up corpus")
struct CleanupCorpusTests {
  @Test("every mutation has sentences to act on, in every language")
  func everyMutationHasMaterial() {
    #expect(CleanupCorpus.all.count >= 40)
    for tongue in [Tongue.ru, .en, .pl, .uk] {
      #expect(CleanupCorpus.with { $0.tongue == tongue }.count >= 8, "\(tongue)")
    }
    #expect(CleanupCorpus.with { !$0.particleIndices.isEmpty }.count >= 12)
    #expect(CleanupCorpus.with(\.isContracted).count >= 4)
    #expect(CleanupCorpus.with { !$0.numbers.isEmpty }.count >= 8)
    #expect(CleanupCorpus.with { $0.spoken.contains(where: \.isNumber) }.count >= 8)
    #expect(CleanupCorpus.with { $0.spoken.hasSuffix("?") }.count >= 6)
    #expect(CleanupCorpus.with { $0.fillerCount > 0 }.count >= 8)
    #expect(CleanupCorpus.with { $0.marked.contains("'") }.count >= 5)
  }

  @Test("the markup leaves nothing behind in the spoken text")
  func markupIsInvisible() {
    for sentence in CleanupCorpus.all {
      #expect(!sentence.spoken.contains(where: "~[]|".contains), "\(sentence.spoken)")
      #expect(!sentence.withDigits.contains(where: "~[]|".contains), "\(sentence.withDigits)")
    }
  }

  @Test("no sentence starts with the words of another, so a shuffle holds no restart")
  func noSentenceRestartsAnother() {
    let spoken = CleanupCorpus.all.map { Negations.tokens(in: $0.spoken) }
    for (index, earlier) in spoken.enumerated() {
      for (other, later) in spoken.enumerated() where other != index {
        #expect(!later.starts(with: earlier), "\(earlier) / \(later)")
      }
    }
  }
}
