import Foundation

enum MeetingTranscriptBuilder {
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
    me: [TimedText], others: [(word: TimedText, speaker: MeetingSpeaker)],
    dictations: [ClosedRange<Double>]
  ) -> (utterances: [MeetingUtterance], echoDropped: Int) {
    let spoken = me.sorted { $0.start < $1.start }.filter { word in
      let middle = (word.start + word.end) / 2
      return !dictations.contains { $0.contains(middle) }
    }
    let theirs = others.sorted { $0.word.start < $1.word.start }
    let (kept, dropped) = withoutEcho(spoken, of: theirs.map(\.word))
    let words = (kept.map { (word: $0, speaker: MeetingSpeaker.me) } + theirs).enumerated().sorted {
      ($0.element.word.start, $0.element.speaker == .me ? 0 : 1, $0.offset)
        < ($1.element.word.start, $1.element.speaker == .me ? 0 : 1, $1.offset)
    }
    return (lines(words.map(\.element)), dropped)
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

  private static func lines(_ words: [(word: TimedText, speaker: MeetingSpeaker)])
    -> [MeetingUtterance]
  {
    var out: [(start: Double, end: Double, speaker: MeetingSpeaker, texts: [String])] = []
    var open: [MeetingSpeaker: (line: Int, word: Int)] = [:]
    for (index, said) in words.enumerated() {
      if let at = open[said.speaker] {
        let lastEnd = out[at.line].end
        let replied = words[(at.word + 1)..<index].contains {
          $0.word.start >= lastEnd && $0.word.end <= said.word.start
        }
        if !replied {
          out[at.line].end = max(lastEnd, said.word.end)
          out[at.line].texts.append(said.word.text)
          open[said.speaker] = (at.line, index)
          continue
        }
      }
      open[said.speaker] = (out.count, index)
      out.append((said.word.start, said.word.end, said.speaker, [said.word.text]))
    }
    return out.map {
      MeetingUtterance(
        start: $0.start, end: $0.end, speaker: $0.speaker, text: $0.texts.joined(separator: " "))
    }
  }

  private static func seconds(_ nanos: UInt64) -> Double {
    Double(nanos) / 1_000_000_000
  }
}
