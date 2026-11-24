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
    me: [TimedText] = [], others: [TimedText] = [],
    said: [(word: TimedText, speaker: MeetingSpeaker)] = [], dictations: [ClosedRange<Double>] = []
  ) -> (utterances: [MeetingUtterance], echoDropped: Int) {
    MeetingTranscriptBuilder.build(
      me: me, others: others.map { (word: $0, speaker: .others) } + said, dictations: dictations)
  }

  private func said(_ text: String, by number: Int, from start: Double)
    -> [(word: TimedText, speaker: MeetingSpeaker)]
  {
    words(text, from: start).map { (word: $0, speaker: .numbered(number)) }
  }

  @Test func dictationIsLeftOut() {
    let me = [
      TimedText(start: 1.85, end: 2.05, text: "kept"),
      TimedText(start: 1.9, end: 2.1, text: "dictated"),
      TimedText(start: 3.4, end: 4.6, text: "dictated"),
      TimedText(start: 3.95, end: 4.15, text: "after"),
    ]
    let result = build(me: me, dictations: [2.0...4.0])
    #expect(result.utterances.map(\.text) == ["kept", "after"])
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
    #expect(result.echoDropped == 4)
  }

  @Test func echoIsCutOutAndMyWordsStay() {
    let result = build(
      me: words("radio electronic warfare right now I am speaking", from: 0.1),
      others: words("radio electronic warfare saved the bridge", from: 0))
    #expect(result.utterances.first { $0.speaker == .me }?.text == "right now I am speaking")
    #expect(result.echoDropped == 3)
  }

  @Test func aLoneMatchingWordStays() {
    let result = build(me: words("yes I agree", from: 5.1), others: words("yes", from: 5))
    #expect(result.utterances.first { $0.speaker == .me }?.text == "yes I agree")
    #expect(result.echoDropped == 0)
  }

  @Test func aReplyAfterTheReachSurvives() {
    let result = build(
      me: words("the build is green", from: 12.6), others: words("the build is green", from: 10))
    #expect(result.utterances.map(\.speaker) == [.others, .me])
    #expect(result.echoDropped == 0)
  }

  @Test func echoIsFoundLateInALongMeetingAndOnlyNearItsTime() {
    let others = (0..<200).map { i in
      TimedText(start: Double(i) * 0.5, end: Double(i) * 0.5 + 0.4, text: "w\(i)")
    }
    let me = [
      TimedText(start: 75.1, end: 75.3, text: "w150"),
      TimedText(start: 75.6, end: 75.8, text: "w151"),
      TimedText(start: 80, end: 80.2, text: "w10"),
      TimedText(start: 80.3, end: 80.5, text: "w11"),
    ]
    let result = build(me: me, others: others)
    #expect(result.echoDropped == 2)
    #expect(result.utterances.first { $0.speaker == .me }?.text == "w10 w11")
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
    #expect(result.echoDropped == 2)
  }

  @Test func othersAreSplitWhereIStartSpeaking() {
    let result = build(
      me: [TimedText(start: 4.05, end: 4.4, text: "question")],
      others: words("one two three four five six seven eight nine ten", from: 2, step: 0.5))
    #expect(result.utterances.map(\.speaker) == [.others, .me, .others])
    #expect(result.utterances.first?.text == "one two three four five")
    #expect(result.utterances.last?.text == "six seven eight nine ten")
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

  @Test func aSpeakerChangeStartsALine() {
    let result = build(said: said("a b", by: 1, from: 0) + said("c", by: 2, from: 0.5))
    #expect(result.utterances.map(\.speaker) == [.numbered(1), .numbered(2)])
    #expect(result.utterances.map(\.text) == ["a b", "c"])
  }

  @Test func sameSpeakerAcrossAShortGapIsOneLine() {
    let result = build(said: said("one", by: 1, from: 0) + said("two", by: 1, from: 0.75))
    #expect(result.utterances.map(\.speaker) == [.numbered(1)])
    #expect(result.utterances.map(\.text) == ["one two"])
  }

  @Test func linesAtOneStartPutMeFirstThenTheirBuildOrder() {
    let at = { (speaker: MeetingSpeaker) in
      (word: TimedText(start: 2, end: 2.25, text: "w"), speaker: speaker)
    }
    let result = build(
      me: [TimedText(start: 2, end: 2.25, text: "m")],
      said: [
        at(.numbered(2)), at(.numbered(1)),
        (word: TimedText(start: 1, end: 1.25, text: "e"), speaker: .numbered(1)),
      ])
    #expect(result.utterances.map(\.speaker) == [.numbered(1), .me, .numbered(2), .numbered(1)])
  }

  @Test func echoStillMatchesNumberedWords() {
    let result = build(me: words("yes go", from: 5.1), said: said("yes go", by: 1, from: 5))
    #expect(result.echoDropped == 2)
    #expect(result.utterances.map(\.speaker) == [.numbered(1)])
  }

  @Test func spansBecomeSecondsFromTheAnchor() {
    let ranges = MeetingTranscriptBuilder.dictationRanges(
      [DictationSpan(start: 7_000_000_000, end: 8_500_000_000)], anchor: 5_000_000_000)
    #expect(ranges == [2.0...3.5])
  }
}
