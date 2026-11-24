import Foundation

enum MeetingPieces {
  static let maxPiece = 480_000
  static let joinGap = 16_000
  static let carryReach = 16_000
  static let minPiece = 8_000

  struct Plan: Equatable, Sendable {
    let pieces: [Range<Int>]
    let carryFrom: Int?
  }

  public static func buffer(carry: [Float], window: [Int16]) -> [Float] {
    carry + PCMSamples.boostedIfQuiet(window.map { Float($0) / 32767 })
  }

  public static func plan(segments: [SpeechSegment], count: Int, isLast: Bool) -> Plan {
    let ranges = segments.map { segment -> Range<Int> in
      let from = min(count, max(0, PCMSamples.sampleCount(inLeading: segment.start.milliseconds)))
      return
        from..<min(count, max(from, PCMSamples.sampleCount(inLeading: segment.end.milliseconds)))
    }
    .filter { !$0.isEmpty }
    .sorted { $0.lowerBound < $1.lowerBound }
    .flatMap { range in
      stride(from: range.lowerBound, to: range.upperBound, by: maxPiece).map {
        $0..<min($0 + maxPiece, range.upperBound)
      }
    }
    var pieces: [Range<Int>] = []
    for range in ranges {
      if let last = pieces.last, range.lowerBound - last.upperBound < joinGap,
        max(range.upperBound, last.upperBound) - last.lowerBound <= maxPiece
      {
        pieces[pieces.count - 1] = last.lowerBound..<max(range.upperBound, last.upperBound)
      } else {
        pieces.append(range)
      }
    }
    if !isLast, let last = pieces.last, count - last.upperBound < carryReach,
      last.count < maxPiece
    {
      pieces.removeLast()
      return Plan(pieces: pieces, carryFrom: last.lowerBound)
    }
    return Plan(pieces: pieces, carryFrom: nil)
  }

  static func clamped(_ words: [TimedText], to speech: [ClosedRange<Double>]) -> [TimedText] {
    guard !speech.isEmpty else { return words }
    return words.map { word in
      let start =
        speech.contains { $0.contains(word.start) }
        ? word.start : speech.first { $0.lowerBound > word.start }?.lowerBound
      let end =
        speech.contains { $0.contains(word.end) }
        ? word.end : speech.last { $0.upperBound < word.end }?.upperBound
      if let start, let end, start <= end {
        return TimedText(start: start, end: end, text: word.text)
      }
      let middle = (word.start + word.end) / 2
      let at =
        [start, end].compactMap { $0 }.min { abs($0 - middle) < abs($1 - middle) } ?? word.start
      return TimedText(start: at, end: at, text: word.text)
    }
  }

  static func padded(_ samples: [Float]) -> [Float] {
    samples.count >= minPiece
      ? samples : samples + [Float](repeating: 0, count: minPiece - samples.count)
  }
}
