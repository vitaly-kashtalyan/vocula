import Testing

@testable import VoculaKit

@Suite struct MeetingStatusTests {
  @Test func aQuietMeetingShowsTheRecordSymbol() {
    let status = MeetingStatus(isRecording: true)
    #expect(MeetingStatusRules.symbol(for: status) == MeetingStatusRules.recordingSymbol)
    #expect(MeetingStatusRules.showsItem(status))
  }

  @Test func aWarningSwitchesTheSymbol() {
    let status = MeetingStatus(isRecording: true, warnings: [.noSystemAudio])
    #expect(MeetingStatusRules.symbol(for: status) == MeetingStatusRules.warningSymbol)
  }

  @Test func aNoticeKeepsTheItemAfterTheMeeting() {
    #expect(MeetingStatusRules.showsItem(MeetingStatus(notice: .autoStopped)))
  }

  @Test(arguments: [MeetingNotice.autoStopped, .endedBySleep])
  func aMeetingThatEndedByItselfShowsTheCalmSymbol(_ notice: MeetingNotice) {
    let status = MeetingStatus(notice: notice)
    #expect(MeetingStatusRules.symbol(for: status) == MeetingStatusRules.endedSymbol)
  }

  @Test func aMeetingThatCouldNotStartShowsTheWarningSymbol() {
    let status = MeetingStatus(notice: .cannotStart)
    #expect(MeetingStatusRules.symbol(for: status) == MeetingStatusRules.warningSymbol)
  }

  @Test func anIdleStatusHidesTheItem() {
    #expect(!MeetingStatusRules.showsItem(MeetingStatus()))
  }

  @Test func onlyRaisedWarningsAreAnnounced() {
    let old = MeetingStatus(isRecording: true, warnings: [.noSystemAudio])
    let new = MeetingStatus(isRecording: true, warnings: [.microphoneStopped, .noSystemAudio])
    #expect(MeetingStatusRules.announcements(from: old, to: new) == [.warning(.microphoneStopped)])
  }

  @Test func theSameNoticeIsAnnouncedOnce() {
    let shown = MeetingStatus(notice: .cannotStart)
    #expect(MeetingStatusRules.announcements(from: shown, to: shown).isEmpty)
    #expect(
      MeetingStatusRules.announcements(from: MeetingStatus(), to: shown) == [
        .notice(.cannotStart)
      ])
  }

  @Test(arguments: [
    (MeetingStatus(), MeetingStatus(isRecording: true), [MeetingAnnouncement.started]),
    (
      MeetingStatus(), MeetingStatus(isRecording: true, warnings: [.waitingForPermission]),
      [.started, .warning(.waitingForPermission)]
    ),
    (MeetingStatus(isRecording: true), MeetingStatus(), [.stopped]),
    (
      MeetingStatus(isRecording: true, warnings: [.noSystemAudio]),
      MeetingStatus(notice: .autoStopped), [.notice(.autoStopped)]
    ),
    (MeetingStatus(isRecording: true), MeetingStatus(isRecording: true), []),
    (MeetingStatus(), MeetingStatus(), []),
  ])
  func recordingStartsAndStopsAreAnnounced(
    old: MeetingStatus, new: MeetingStatus, announced: [MeetingAnnouncement]
  ) {
    #expect(MeetingStatusRules.announcements(from: old, to: new) == announced)
  }

  @Test func aRemovedItemComesBackWhileRecording() {
    #expect(MeetingStatusRules.removal(of: MeetingStatus(isRecording: true)) == .putBack)
    #expect(MeetingStatusRules.removal(of: MeetingStatus(notice: .endedBySleep)) == .dismiss)
  }
}

@Suite struct MeetingSwitchTests {
  @Test func aPressStartsThenStops() {
    var meeting = MeetingSwitch()
    let r1 = meeting.pressed()
    #expect(r1 == .start(meeting: 1, recover: true))
    meeting.began(1)
    let r2 = meeting.pressed()
    #expect(r2 == .stop(meeting: 1))
    #expect(!meeting.isCurrent(1))
  }

  @Test func aPressWhileStartingIsIgnored() {
    var meeting = MeetingSwitch()
    let r3 = meeting.pressed()
    #expect(r3 == .start(meeting: 1, recover: true))
    let r4 = meeting.pressed()
    #expect(r4 == .ignore)
    let r5 = meeting.pressed()
    #expect(r5 == .ignore)
  }

  @Test func onlyAMeetingThatRecordedEndsRecovery() {
    var meeting = MeetingSwitch()
    let r6 = meeting.pressed()
    #expect(r6 == .start(meeting: 1, recover: true))
    let r7 = meeting.ended(1)
    #expect(r7)
    let r8 = meeting.pressed()
    #expect(r8 == .start(meeting: 2, recover: true))
    meeting.began(2)
    let r9 = meeting.pressed()
    #expect(r9 == .stop(meeting: 2))
    let r10 = meeting.pressed()
    #expect(r10 == .start(meeting: 3, recover: false))
  }

  @Test func aStaleMeetingChangesNothing() {
    var meeting = MeetingSwitch()
    _ = meeting.pressed()
    meeting.began(1)
    _ = meeting.pressed()
    let r11 = meeting.pressed()
    #expect(r11 == .start(meeting: 2, recover: false))
    #expect(!meeting.isCurrent(1))
    let r12 = meeting.ended(1)
    #expect(!r12)
    let r13 = meeting.pressed()
    #expect(r13 == .ignore)
  }
}
