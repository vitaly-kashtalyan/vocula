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
        MeetingUtterance(start: 1, end: 2, speaker: .me, text: "hello")
      ])
    let top = try object(JSONEncoder().encode(transcript))
    #expect(Set(top.keys) == ["model", "utterances"])
    let utterance = try #require((top["utterances"] as? [[String: Any]])?.first)
    #expect(Set(utterance.keys) == ["start", "end", "speaker", "text"])
    #expect(utterance["speaker"] as? String == "me")
  }

  @Test func anUnknownSpeakerDecodes() throws {
    let json = Data(
      #"{"model":"m","utterances":[{"start":0,"end":1,"speaker":"speaker-3","text":"x"}]}"#
        .utf8)
    let transcript = try JSONDecoder().decode(MeetingTranscript.self, from: json)
    #expect(transcript.utterances.first?.speaker.rawValue == "speaker-3")
  }

  @Test func aTranscriptWithoutAModelStillDecodes() throws {
    let json = Data(
      #"{"utterances":[{"start":0,"end":1,"speaker":"me","text":"x"}]}"#.utf8)
    let transcript = try JSONDecoder().decode(MeetingTranscript.self, from: json)
    #expect(transcript.model == nil)
    #expect(transcript.utterances.map(\.text) == ["x"])
  }

  @Test func aTranscriptRoundTrips() throws {
    let transcript = MeetingTranscript(
      model: "parakeetUltra",
      utterances: [
        MeetingUtterance(start: 0.5, end: 1.25, speaker: .others, text: "да"),
        MeetingUtterance(start: 2, end: 3, speaker: .me, text: "note"),
      ])
    let decoded = try JSONDecoder().decode(
      MeetingTranscript.self, from: JSONEncoder().encode(transcript))
    #expect(decoded == transcript)
  }
}
