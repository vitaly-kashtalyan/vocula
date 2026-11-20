import Foundation

public enum MeetingTranscriptBuilder {
  public static let pause = 0.7
  public static let echoShare = 0.6
  public static let echoReach = 1.5

  private static let trimmed = CharacterSet.punctuationCharacters.union(.symbols)

  public static func dictationRanges(_ spans: [DictationSpan], anchor: UInt64)
    -> [ClosedRange<Double>]
  {
    spans.map { span in
      seconds(
        HostTime.elapsed(from: anchor, to: span.start))...seconds(
          HostTime.elapsed(from: anchor, to: span.end))
    }
  }

  public static func build(
    me: [TimedText], others: [TimedText], dictations: [ClosedRange<Double>]
  ) -> (utterances: [MeetingUtterance], echoDropped: Int) {
    let mine = merge(me, speaker: .me) { word in
      let middle = (word.start + word.end) / 2
      return dictations.contains { $0.contains(middle) }
    }
    let theirs = merge(others, speaker: .others) { _ in false }
    let kept = mine.filter { !isEcho($0, of: others) }
    let all = (kept + theirs).enumerated().sorted { a, b in
      if a.element.start != b.element.start { return a.element.start < b.element.start }
      if a.element.speaker != b.element.speaker { return a.element.speaker == .me }
      return a.offset < b.offset
    }
    return (all.map(\.element), mine.count - kept.count)
  }

  static func normalized(_ word: String) -> String {
    word.lowercased(with: .invariant).trimmingCharacters(in: trimmed)
  }

  private static func merge(
    _ words: [TimedText], speaker: MeetingSpeaker, isDictation: (TimedText) -> Bool
  ) -> [MeetingUtterance] {
    var out: [MeetingUtterance] = []
    for word in words.sorted(by: { $0.start < $1.start }) {
      let dictation = isDictation(word)
      if let last = out.last, last.dictation == dictation, word.start - last.end < pause {
        out[out.count - 1] = MeetingUtterance(
          start: last.start, end: max(last.end, word.end), speaker: speaker,
          text: last.text + " " + word.text, dictation: dictation)
      } else {
        out.append(
          MeetingUtterance(
            start: word.start, end: word.end, speaker: speaker, text: word.text,
            dictation: dictation))
      }
    }
    return out
  }

  private static func isEcho(_ utterance: MeetingUtterance, of others: [TimedText]) -> Bool {
    let words = utterance.text.split(separator: " ").map { normalized(String($0)) }.filter {
      !$0.isEmpty
    }
    guard !words.isEmpty else { return false }
    let reach = (utterance.start - echoReach)...(utterance.end + echoReach)
    var available: [String: Int] = [:]
    for word in others where reach.contains((word.start + word.end) / 2) {
      available[normalized(word.text), default: 0] += 1
    }
    var matched = 0
    for word in words where (available[word] ?? 0) > 0 {
      available[word, default: 0] -= 1
      matched += 1
    }
    return Double(matched) >= echoShare * Double(words.count)
  }

  private static func seconds(_ nanos: UInt64) -> Double {
    Double(nanos) / 1_000_000_000
  }
}
