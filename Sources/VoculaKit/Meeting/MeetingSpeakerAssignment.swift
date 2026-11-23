import Foundation

enum MeetingSpeakerAssignment {
  static let pointSpan = 0.05
  static let minCoverage = 0.5
  static let overlapCoverage = 0.3

  static func assign(_ words: [TimedText], turns: [SpeakerTurn]) -> [MeetingSpeaker] {
    let chosen = words.map { speaker(of: $0, turns: turns) }
    var numbers: [String: Int] = [:]
    let inOrder = words.indices.sorted { (words[$0].start, $0) < (words[$1].start, $1) }
    for index in inOrder {
      if let speaker = chosen[index], numbers[speaker] == nil {
        numbers[speaker] = numbers.count + 1
      }
    }
    return chosen.map { $0.flatMap { numbers[$0] }.map(MeetingSpeaker.numbered) ?? .others }
  }

  private static func speaker(of word: TimedText, turns: [SpeakerTurn]) -> String? {
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
    guard let best = ranked.first, best >= minCoverage else { return nil }
    guard ranked.count < 2 || ranked[1] < overlapCoverage else { return nil }
    return coverage.first { $0.value == best }?.key
  }
}
