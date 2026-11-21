import Foundation
import Testing

@testable import VoculaKit

@Suite struct MeetingListingTests {
  private func listing(
    at seconds: TimeInterval = 0, pinned: Bool = false, recording: Bool = false,
    transcript: Bool = true
  ) -> MeetingListing {
    MeetingListing(
      id: UUID(), startedAt: Date(timeIntervalSinceReferenceDate: seconds), duration: 60,
      hasEnd: !recording, isPinned: pinned, isRecordingState: recording,
      hasTranscript: transcript)
  }

  @Test func statusFollowsTranscriptStateAndBusy() {
    #expect(listing().status(busy: true) == .transcribed)
    #expect(listing(recording: true, transcript: false).status(busy: true) == .recording)
    #expect(listing(recording: true, transcript: false).status(busy: false) == .waiting)
    #expect(listing(transcript: false).status(busy: true) == .waiting)
  }

  @Test func actionsFollowTheTable() {
    let transcribed = listing()
    for action in MeetingAction.allCases {
      #expect(transcribed.allows(action, busy: false, passRunning: false))
    }
    #expect(!transcribed.allows(.delete, busy: false, passRunning: true))
    #expect(!listing(pinned: true).allows(.delete, busy: false, passRunning: false))
    #expect(listing(pinned: true).allows(.pin, busy: false, passRunning: false))

    let waiting = listing(transcript: false)
    #expect(!waiting.allows(.open, busy: false, passRunning: false))
    #expect(!waiting.allows(.export, busy: false, passRunning: false))
    #expect(!waiting.allows(.copy, busy: false, passRunning: false))
    #expect(waiting.allows(.rename, busy: false, passRunning: false))
    #expect(waiting.allows(.delete, busy: false, passRunning: false))

    let live = listing(recording: true, transcript: false)
    for action in MeetingAction.allCases {
      #expect(!live.allows(action, busy: true, passRunning: false))
    }
    #expect(live.allows(.delete, busy: false, passRunning: false))
  }

  @Test func pinnedFirstThenNewest() {
    let p1 = listing(at: 1, pinned: true)
    let n2 = listing(at: 2)
    let p3 = listing(at: 3, pinned: true)
    let n4 = listing(at: 4)
    #expect(MeetingListing.ordered([p1, n2, p3, n4]).map(\.id) == [p3, p1, n4, n2].map(\.id))
  }

  @Test func theSubmenuListsTranscribedNewestFirst() {
    let old = listing(at: 1)
    let new = listing(at: 5)
    let waiting = listing(at: 9, pinned: true, transcript: false)
    #expect(MeetingListing.transcribed([old, waiting, new]).map(\.id) == [new, old].map(\.id))
  }

  @Test func noKeyWithoutMeetingsIsEmpty() {
    let error = MeetingFailure.failed(step: "key", code: MeetingKeyRule.itemNotFound)
    #expect(MeetingListingOutcome.failed(error) { false } == .noKey(holdsMeetings: false))
  }

  @Test func noKeyWithMeetingsIsUnreadable() {
    let error = MeetingFailure.failed(step: "key", code: MeetingKeyRule.itemNotFound)
    let outcome = MeetingListingOutcome.failed(error) { true }
    #expect(outcome == .noKey(holdsMeetings: true))
    #expect(outcome.isUnreadable)
  }

  @Test func otherFailuresAreUnreadableWithTheirStep() {
    #expect(
      MeetingListingOutcome.failed(MeetingFailure.failed(step: "key", code: -25308)) { true }
        == .unreadable(step: "key", code: -25308))
    #expect(
      MeetingListingOutcome.failed(MeetingStoreError.failed(step: "list", code: 1)) { true }
        == .unreadable(step: "list", code: 1))
    #expect(
      MeetingListingOutcome.failed(CancellationError()) { true }
        == .unreadable(step: "list", code: 0))
    #expect(!MeetingListingOutcome.noKey(holdsMeetings: false).isUnreadable)
  }

  @Test func sectionContentFollowsLoadingAndFailure() {
    #expect(
      MeetingSectionContent.decide(loaded: false, meetings: [], unreadable: false) == .reading)
    #expect(
      MeetingSectionContent.decide(loaded: true, meetings: [], unreadable: true) == .lineAlone)
    #expect(MeetingSectionContent.decide(loaded: true, meetings: [], unreadable: false) == .empty)
    #expect(
      MeetingSectionContent.decide(loaded: true, meetings: [listing()], unreadable: true) == .list)
  }
}
