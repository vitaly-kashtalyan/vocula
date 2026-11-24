import Foundation

enum MeetingSpeakerAssignment {
  static let pointSpan = 0.05
  static let minCoverage = 0.5
  static let overlapCoverage = 0.3

  private enum Found: Equatable {
    case speaker(String)
    case pause
    case overlap

    var speaker: String? {
      if case .speaker(let speaker) = self { speaker } else { nil }
    }
  }

  static func assign(_ words: [TimedText], turns: [SpeakerTurn]) -> [MeetingSpeaker] {
    let found = words.map { attribution(of: $0, turns: turns) }
    let inOrder = words.indices.sorted { (words[$0].start, $0) < (words[$1].start, $1) }
    var chosen = found.map(\.speaker)
    for (position, speaker) in pauseFills(found, inOrder: inOrder) {
      chosen[inOrder[position]] = speaker
    }
    var numbers: [String: Int] = [:]
    for index in inOrder {
      if let speaker = chosen[index], numbers[speaker] == nil {
        numbers[speaker] = numbers.count + 1
      }
    }
    return chosen.map { $0.flatMap { numbers[$0] }.map(MeetingSpeaker.numbered) ?? .others }
  }

  private static func pauseFills(_ found: [Found], inOrder: [Int]) -> [(Int, String)] {
    var before: [String?] = []
    var last: String?
    for index in inOrder {
      before.append(last)
      last = found[index].speaker ?? last
    }
    var fills: [(Int, String)] = []
    var next: String?
    for position in inOrder.indices.reversed() {
      let here = found[inOrder[position]]
      if here == .pause, let speaker = before[position], speaker == next {
        fills.append((position, speaker))
      }
      next = here.speaker ?? next
    }
    return fills
  }

  private static func attribution(of word: TimedText, turns: [SpeakerTurn]) -> Found {
    let span = word.end - word.start
    var coverage: [String: Double] = [:]
    if span < pointSpan {
      let point = (word.start + word.end) / 2
      for turn in turns where turn.start <= point && point < turn.end { coverage[turn.speaker] = 1 }
    } else {
      for turn in turns {
        let inside = min(word.end, turn.end) - max(word.start, turn.start)
        if inside > 0 { coverage[turn.speaker, default: 0] += inside / span }
      }
    }
    let ranked = coverage.values.sorted(by: >)
    guard let best = ranked.first, best >= minCoverage else { return .pause }
    guard ranked.count < 2 || ranked[1] < overlapCoverage else { return .overlap }
    return coverage.first { $0.value == best }.map { .speaker($0.key) } ?? .pause
  }
}
