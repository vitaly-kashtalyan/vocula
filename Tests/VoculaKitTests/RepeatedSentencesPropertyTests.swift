import Foundation
import Testing

@testable import VoculaKit

@Suite("Repeated sentences under fuzz")
struct RepeatedSentencesPropertyTests {
  private static let fragments = [".", "...", "?!", "!", "—", "…", ". . .", "?"]
  private static let decimals = [
    "Обнови до 3.5.", "Version 2.4.1 is out.", "Это 3.5 литра, а не 3.6.", "Wersja 1.0 działa.",
  ]
  private static let separators = [" ", "  ", "\n", " \t ", "\u{00A0}"]

  private static func randomText(_ rng: inout SeededRandom) -> String {
    var pieces: [String] = []
    for _ in 0..<Int.random(in: 1...6, using: &rng) {
      let sentence = CleanupCorpus.all.randomElement(using: &rng)!.spoken
      switch Int.random(in: 0..<7, using: &rng) {
      case 0:
        pieces += [sentence, sentence]
      case 1:
        let words = sentence.split(separator: " ")
        let start = words.prefix(Int.random(in: 1...words.count, using: &rng))
          .joined(separator: " ")
        pieces += [start + ["", ".", "...", "!", "?"].randomElement(using: &rng)!, sentence]
      case 2:
        pieces.append(String(sentence.dropLast()) + "?")
      case 3:
        pieces.append(decimals.randomElement(using: &rng)!)
      case 4:
        pieces.append(fragments.randomElement(using: &rng)!)
      default:
        pieces.append(sentence)
      }
    }
    return pieces.reduce("") { text, piece in
      text.isEmpty ? piece : text + separators.randomElement(using: &rng)! + piece
    }
  }

  private static func sentences(_ text: String) -> [[UInt8]] {
    text.replacingOccurrences(of: #"(?<=[.!?])\s+"#, with: "\u{0}", options: .regularExpression)
      .split(separator: "\u{0}")
      .map { Array($0.trimmingCharacters(in: .whitespacesAndNewlines).utf8) }
      .filter { !$0.isEmpty }
  }

  private static func isInOrder(_ kept: [[UInt8]], within all: [[UInt8]]) -> Bool {
    var rest = all[...]
    for sentence in kept {
      guard let found = rest.firstIndex(of: sentence) else { return false }
      rest = rest[(found + 1)...]
    }
    return true
  }

  @Test("it only removes whole sentences, never lengthens, and a second pass changes nothing")
  func invariants() {
    var rng = SeededRandom(seed: 0x5EED_0003)
    var collapsed = 0
    for _ in 0..<1_000 {
      let text = Self.randomText(&rng)
      let once = RepeatedSentences.collapse(text)
      if once != text { collapsed += 1 }
      #expect(once.utf8.count <= text.utf8.count, "\(text.debugDescription)")
      #expect(once.count <= text.count, "\(text.debugDescription)")
      #expect(RepeatedSentences.collapse(once) == once, "\(text.debugDescription)")
      #expect(
        Self.isInOrder(Self.sentences(once), within: Self.sentences(text)),
        "\(text.debugDescription)")
    }
    #expect(collapsed > 150, "only \(collapsed) texts collapsed — the fuzz checks nothing")
  }

  @Test("text holding no restart comes back byte for byte")
  func noRestartIsUntouched() {
    var rng = SeededRandom(seed: 0x5EED_0004)
    for _ in 0..<150 {
      let text = CleanupCorpus.all.map(\.spoken).shuffled(using: &rng)
        .prefix(Int.random(in: 1...CleanupCorpus.all.count, using: &rng))
        .joined(separator: Self.separators.randomElement(using: &rng)!)
      #expect(Array(RepeatedSentences.collapse(text).utf8) == Array(text.utf8))
    }
  }
}
