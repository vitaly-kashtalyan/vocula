import Foundation
import Testing

@testable import VoculaKit

@Suite struct MeetingHeaderNameTests {
  private struct ShippedHeader: Decodable {
    let id: UUID
    let startedAt: Date
    let anchor: UInt64
    let end: Date?
    let state: MeetingState
    let endedBy: MeetingEnd?
    let dictations: [DictationSpan]
  }

  private let shipped = Data(
    #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","startedAt":0,"anchor":5,"state":"recorded","dictations":[]}"#
      .utf8)

  @Test func aShippedHeaderDecodesWithNoNameUnpinned() throws {
    let header = try JSONDecoder().decode(MeetingHeader.self, from: shipped)
    #expect(header.title == nil)
    #expect(!header.isPinned)
  }

  @Test func aNamedHeaderDecodesInTheShippedShape() throws {
    var header = try JSONDecoder().decode(MeetingHeader.self, from: shipped)
    header.title = "x"
    header.pinned = true
    let old = try JSONDecoder().decode(ShippedHeader.self, from: JSONEncoder().encode(header))
    #expect(old.id == header.id)
  }

  @Test func nameIsTrimmedAndFlattened() {
    #expect(MeetingHeader.name(from: "  Weekly\tsync \n") == "Weekly sync")
    #expect(MeetingHeader.name(from: "a\u{7}b") == "a b")
    #expect(MeetingHeader.name(from: "a\u{200B}b") == "a\u{200B}b")
    #expect(MeetingHeader.name(from: "a\u{2028}b\u{2029}c") == "a b c")
  }

  @Test func nameOfOnlyBlanksIsNoName() {
    #expect(MeetingHeader.name(from: " \n\t ") == nil)
    #expect(MeetingHeader.name(from: "\u{1}\u{2}") == nil)
  }

  @Test func nameIsCutAtOneHundredCharacters() {
    #expect(MeetingHeader.name(from: String(repeating: "ж", count: 150))?.count == 100)
    let family = "👨‍👩‍👧"
    let cut = MeetingHeader.name(from: String(repeating: family, count: 120))
    #expect(cut?.count == 100)
    #expect(cut?.last.map(String.init) == family)
  }
}
