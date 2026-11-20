import Foundation
import Testing

@testable import VoculaKit

@Suite struct MeetingTranscriptBuilderTests {
  private func words(_ text: String, from start: Double, step: Double = 0.25) -> [TimedText] {
    text.split(separator: " ").enumerated().map { index, word in
      let at = start + Double(index) * step
      return TimedText(start: at, end: at + step * 0.8, text: String(word))
    }
  }

  private func build(
    me: [TimedText] = [], others: [TimedText] = [], dictations: [ClosedRange<Double>] = []
  ) -> (utterances: [MeetingUtterance], echoDropped: Int) {
    MeetingTranscriptBuilder.build(me: me, others: others, dictations: dictations)
  }

  @Test func wordsInsideASpanAreDictation() {
    let me = [
      TimedText(start: 1.85, end: 2.05, text: "a"),
      TimedText(start: 1.9, end: 2.1, text: "b"),
      TimedText(start: 2.4, end: 3.0, text: "c"),
      TimedText(start: 3.4, end: 4.6, text: "d"),
      TimedText(start: 3.95, end: 4.15, text: "e"),
    ]
    let result = build(me: me, dictations: [2.0...4.0])
    #expect(result.utterances.map(\.text) == ["a", "b c d", "e"])
    #expect(result.utterances.map(\.dictation) == [false, true, false])
  }

  @Test func aGapUnderSevenTenthsMerges() {
    let joined = build(me: [
      TimedText(start: 0, end: 0.5, text: "one"), TimedText(start: 1.19, end: 1.5, text: "two"),
    ])
    #expect(joined.utterances.map(\.text) == ["one two"])
    #expect(joined.utterances.first?.start == 0)
    #expect(joined.utterances.first?.end == 1.5)
    let split = build(me: [
      TimedText(start: 0, end: 0.5, text: "one"), TimedText(start: 1.2, end: 1.5, text: "two"),
    ])
    #expect(split.utterances.map(\.text) == ["one", "two"])
  }

  @Test func echoOfOthersIsDropped() {
    let result = build(
      me: words("the build is green", from: 10.2), others: words("the build is green", from: 10))
    #expect(result.utterances.map(\.speaker) == [.others])
    #expect(result.echoDropped == 1)
  }

  @Test func aReplyAfterTheReachSurvives() {
    let result = build(
      me: words("the build is green", from: 12.6), others: words("the build is green", from: 10))
    #expect(result.utterances.map(\.speaker) == [.others, .me])
    #expect(result.echoDropped == 0)
  }

  @Test func echoNeedsSixtyPercent() {
    let others = words("alpha beta gamma", from: 20)
    let dropped = build(me: words("alpha beta gamma delta omega", from: 20.1), others: others)
    #expect(dropped.echoDropped == 1)
    let kept = build(me: words("alpha beta delta omega sigma", from: 20.1), others: others)
    #expect(kept.echoDropped == 0)
    #expect(kept.utterances.contains { $0.speaker == .me })
  }

  @Test func oneOthersWordMatchesOnce() {
    let result = build(me: words("yes yes yes", from: 5.1), others: words("yes", from: 5))
    #expect(result.echoDropped == 0)
  }

  @Test func wordsCompareWithoutCaseAndEdgePunctuation() {
    #expect(MeetingTranscriptBuilder.normalized("Green.") == "green")
    #expect(MeetingTranscriptBuilder.normalized("«don't»") == "don't")
    #expect(MeetingTranscriptBuilder.normalized("IT") == "it")
    let result = build(me: words("Green, build!", from: 1.1), others: words("green build", from: 1))
    #expect(result.echoDropped == 1)
  }

  @Test func tracksInterleaveByStartMeFirstOnTies() {
    let result = build(
      me: [
        TimedText(start: 3, end: 3.5, text: "mine"), TimedText(start: 9, end: 9.5, text: "late"),
      ],
      others: [
        TimedText(start: 3, end: 3.5, text: "theirs"), TimedText(start: 1, end: 1.5, text: "first"),
      ])
    #expect(result.utterances.map(\.text) == ["first", "mine", "theirs", "late"])
  }

  @Test func spansBecomeSecondsFromTheAnchor() {
    let ranges = MeetingTranscriptBuilder.dictationRanges(
      [DictationSpan(start: 7_000_000_000, end: 8_500_000_000)], anchor: 5_000_000_000)
    #expect(ranges == [2.0...3.5])
  }
}
