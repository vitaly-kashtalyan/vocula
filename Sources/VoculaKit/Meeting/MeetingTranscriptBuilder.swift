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

  static func build(
    me: [TimedText], others: [TimedText], dictations: [ClosedRange<Double>]
  ) -> (utterances: [MeetingUtterance], echoDropped: Int) {
    let spoken = me.sorted { $0.start < $1.start }.filter { word in
      let middle = (word.start + word.end) / 2
      return !dictations.contains { $0.contains(middle) }
    }
    let theirs = others.sorted { $0.start < $1.start }
    let (kept, dropped) = withoutEcho(spoken, of: theirs)
    let mine = merge(kept, speaker: .me, breaks: [])
    let all = (mine + merge(theirs, speaker: .others, breaks: mine.map(\.start)))
      .enumerated().sorted { a, b in
        if a.element.start != b.element.start { return a.element.start < b.element.start }
        if a.element.speaker != b.element.speaker { return a.element.speaker == .me }
        return a.offset < b.offset
      }
    return (all.map(\.element), dropped)
  }

  static func normalized(_ word: String) -> String {
    word.lowercased(with: .invariant).trimmingCharacters(in: trimmed)
  }

  private static func withoutEcho(_ mine: [TimedText], of theirs: [TimedText])
    -> (kept: [TimedText], dropped: Int)
  {
    var used = Set<Int>()
    let echo = mine.map { word -> Bool in
      let text = normalized(word.text)
      guard !text.isEmpty else { return false }
      let reach = (word.start - echoReach)...(word.end + echoReach)
      guard
        let match = theirs.indices.first(where: {
          !used.contains($0) && reach.contains((theirs[$0].start + theirs[$0].end) / 2)
            && normalized(theirs[$0].text) == text
        })
      else { return false }
      used.insert(match)
      return true
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

  private static func merge(_ words: [TimedText], speaker: MeetingSpeaker, breaks: [Double])
    -> [MeetingUtterance]
  {
    var out: [MeetingUtterance] = []
    var previousStart = -Double.infinity
    for word in words {
      let interrupted = breaks.contains { $0 > previousStart && $0 <= word.start }
      if let last = out.last, word.start - last.end < pause, !interrupted {
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
