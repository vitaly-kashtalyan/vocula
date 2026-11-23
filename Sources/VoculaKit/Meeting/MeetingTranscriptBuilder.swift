import Foundation

enum MeetingTranscriptBuilder {
  static let pause = 0.7
  static let echoReach = 1.5
  static let echoRun = 2

  private static let trimmed = CharacterSet.punctuationCharacters.union(.symbols)

  static func dictationRanges(_ spans: [DictationSpan], anchor: UInt64) -> [ClosedRange<Double>] {
    spans.map { span in
      seconds(
        HostTime.elapsed(from: anchor, to: span.start))...seconds(
          HostTime.elapsed(from: anchor, to: span.end))
    }
  }

  typealias Line = (start: Double, speaker: MeetingSpeaker, offset: Int)

  static func build(
    me: [TimedText], others: [(word: TimedText, speaker: MeetingSpeaker)],
    dictations: [ClosedRange<Double>]
  ) -> (utterances: [MeetingUtterance], echoDropped: Int) {
    let spoken = me.sorted { $0.start < $1.start }.filter { word in
      let middle = (word.start + word.end) / 2
      return !dictations.contains { $0.contains(middle) }
    }
    let theirs = others.sorted { $0.word.start < $1.word.start }
    let (kept, dropped) = withoutEcho(spoken, of: theirs.map(\.word))
    let mine = merge(kept.map { (word: $0, speaker: .me) }, breaks: [])
    let all = (mine + merge(theirs, breaks: mine.map(\.start))).enumerated().sorted {
      precedes(
        (start: $0.element.start, speaker: $0.element.speaker, offset: $0.offset),
        (start: $1.element.start, speaker: $1.element.speaker, offset: $1.offset))
    }
    return (all.map(\.element), dropped)
  }

  static func precedes(_ a: Line, _ b: Line) -> Bool {
    if a.start != b.start { return a.start < b.start }
    if (a.speaker == .me) != (b.speaker == .me) { return a.speaker == .me }
    return a.offset < b.offset
  }

  static func normalized(_ word: String) -> String {
    word.lowercased(with: .invariant).trimmingCharacters(in: trimmed)
  }

  private static func withoutEcho(_ mine: [TimedText], of theirs: [TimedText])
    -> (kept: [TimedText], dropped: Int)
  {
    let texts = theirs.map { normalized($0.text) }
    var used = Set<Int>()
    var low = 0
    let echo = mine.map { word -> Bool in
      let text = normalized(word.text)
      let reach = (word.start - echoReach)...(word.end + echoReach)
      while low < theirs.count && theirs[low].end < reach.lowerBound { low += 1 }
      guard !text.isEmpty else { return false }
      var index = low
      while index < theirs.count && theirs[index].start <= reach.upperBound {
        let other = theirs[index]
        if !used.contains(index), texts[index] == text,
          reach.contains((other.start + other.end) / 2)
        {
          used.insert(index)
          return true
        }
        index += 1
      }
      return false
    }
    var kept: [TimedText] = []
    var index = 0
    while index < mine.count {
      var run = index
      while run < mine.count && echo[run] { run += 1 }
      if run - index >= echoRun {
        index = run
        continue
      }
      kept.append(mine[index])
      index += 1
    }
    return (kept, mine.count - kept.count)
  }

  private static func merge(
    _ words: [(word: TimedText, speaker: MeetingSpeaker)], breaks: [Double]
  ) -> [MeetingUtterance] {
    var out: [MeetingUtterance] = []
    var previousStart = -Double.infinity
    for (word, speaker) in words {
      let interrupted = breaks.contains { $0 > previousStart && $0 <= word.start }
      if let last = out.last, last.speaker == speaker, word.start - last.end < pause, !interrupted {
        out[out.count - 1] = MeetingUtterance(
          start: last.start, end: max(last.end, word.end), speaker: speaker,
          text: last.text + " " + word.text)
      } else {
        out.append(
          MeetingUtterance(start: word.start, end: word.end, speaker: speaker, text: word.text))
      }
      previousStart = word.start
    }
    return out
  }

  private static func seconds(_ nanos: UInt64) -> Double {
    Double(nanos) / 1_000_000_000
  }
}
