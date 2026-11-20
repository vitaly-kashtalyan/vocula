import Foundation
import Testing

@testable import VoculaKit

@Suite struct MeetingTranscriptTests {
  private func object(_ data: Data) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  @Test func transcriptEncodesTheStoredFieldNames() throws {
    let transcript = MeetingTranscript(
      model: "largeV3Turbo",
      utterances: [
        MeetingUtterance(start: 1, end: 2, speaker: .me, text: "hello", dictation: false)
      ])
    let top = try object(JSONEncoder().encode(transcript))
    #expect(Set(top.keys) == ["model", "utterances"])
    let utterance = try #require((top["utterances"] as? [[String: Any]])?.first)
    #expect(Set(utterance.keys) == ["start", "end", "speaker", "text", "dictation"])
    #expect(utterance["speaker"] as? String == "me")
  }

  @Test func anUnknownSpeakerDecodes() throws {
    let json = Data(
      #"{"model":"m","utterances":[{"start":0,"end":1,"speaker":"speaker-3","text":"x","dictation":false}]}"#
        .utf8)
    let transcript = try JSONDecoder().decode(MeetingTranscript.self, from: json)
    #expect(transcript.utterances.first?.speaker.rawValue == "speaker-3")
  }

  @Test func utterancesWithoutAModelDoNotDecode() {
    let json = Data(
      #"{"utterances":[{"start":0,"end":1,"speaker":"me","text":"x","dictation":false}]}"#.utf8)
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(MeetingTranscript.self, from: json)
    }
    #expect(
      (try? JSONDecoder().decode(MeetingTranscript.self, from: Data(#"{"utterances":[]}"#.utf8)))
        == .empty)
  }

  @Test func utterancesAreKeptInTimeOrder() {
    let late = MeetingUtterance(start: 5, end: 6, speaker: .others, text: "b", dictation: false)
    let early = MeetingUtterance(start: 1, end: 2, speaker: .me, text: "a", dictation: false)
    let tieMe = MeetingUtterance(start: 5, end: 6, speaker: .me, text: "c", dictation: false)
    let transcript = MeetingTranscript.recognized(
      by: .largeV3Turbo, utterances: [late, early, tieMe])
    #expect(transcript.utterances.map(\.text) == ["a", "b", "c"])
  }

  @Test func aTranscriptRoundTrips() throws {
    let transcript = MeetingTranscript(
      model: "parakeetUltra",
      utterances: [
        MeetingUtterance(start: 0.5, end: 1.25, speaker: .others, text: "да", dictation: false),
        MeetingUtterance(start: 2, end: 3, speaker: .me, text: "note", dictation: true),
      ])
    let decoded = try JSONDecoder().decode(
      MeetingTranscript.self, from: JSONEncoder().encode(transcript))
    #expect(decoded == transcript)
  }
}
