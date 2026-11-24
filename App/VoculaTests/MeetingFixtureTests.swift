import Foundation
import Testing

@testable import Vocula
@testable import VoculaKit

@MainActor
@Suite struct MeetingFixtureTests {
  private func listed(_ parts: MeetingTranscriptionParts) async -> [MeetingListing] {
    guard case .meetings(let found) = await parts.listing(nil) else { return [] }
    return MeetingListing.ordered(found)
  }

  @Test func theFixtureListsAPinnedAWaitingAndANamedMeeting() async {
    let found = await listed(MeetingFixture().parts())
    #expect(found.count == 3)
    #expect(found[0].isPinned)
    #expect(!found[1].hasTranscript)
    #expect(found[2].title == "Weekly sync")
  }

  @Test func theFixtureRenamesAndPinsInMemory() async {
    let parts = MeetingFixture().parts()
    let named = await listed(parts)[2]
    #expect(await parts.updateHeader(named.id, false) { $0.title = "Renamed" } == .done)
    #expect(await parts.updateHeader(named.id, false) { $0.pinned = true } == .done)
    let after = await listed(parts).first { $0.id == named.id }
    #expect(after?.title == "Renamed")
    #expect(after?.isPinned == true)
  }

  @Test func theFixtureRefusesAPinnedDeleteAndDeletesTheRest() async {
    let parts = MeetingFixture().parts()
    let found = await listed(parts)
    #expect(await parts.delete(found[0].id, false) == .refused)
    #expect(await parts.delete(found[1].id, false) == .done)
    #expect(await listed(parts).count == 2)
  }

  @Test func theFixtureOpensATranscribedMeetingOnly() async {
    let parts = MeetingFixture().parts()
    let found = await listed(parts)
    guard case .transcript(let transcript) = await parts.transcript(found[2].id) else {
      Issue.record("the named meeting did not open")
      return
    }
    #expect(transcript.utterances.map(\.text).contains("The build is green."))
    #expect(await parts.transcript(found[1].id) != .transcript(transcript))
  }

  @Test func theFixtureShowsTwoNumberedSpeakers() async {
    let parts = MeetingFixture().parts()
    let named = await listed(parts)[2]
    guard case .transcript(let transcript) = await parts.transcript(named.id) else {
      Issue.record("the named meeting did not open")
      return
    }
    #expect(transcript.utterances.map(\.speaker) == [.me, .numbered(1), .numbered(2)])
    #expect(transcript.utterances.map(\.text).contains("The build is green."))
  }

  @Test func theFixtureTouchesNoDisk() async {
    #expect(
      await MeetingFixture().parts().write(Data("x".utf8), URL(fileURLWithPath: "/")) == .done)
  }
}
