import Foundation
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

  @Test(arguments: [
    (0, "00:00"), (13, "00:13"), (754, "12:34"), (3599, "59:59"), (3723, "1:02:03"), (-5, "00:00"),
  ])
  func theTimerKeepsItsWidthUntilTheFirstHour(_ seconds: Int, _ shown: String) {
    #expect(MeetingStatusRules.elapsed(seconds, locale: Locale(identifier: "en_US_POSIX")) == shown)
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

@Suite struct MeetingTranscriptionStatusTests {
  private typealias Rules = MeetingStatusRules
  private let idle = MeetingStatus()

  @Test func recordingWinsTheSymbol() {
    let recording = MeetingStatus(isRecording: true)
    #expect(
      Rules.symbol(for: recording, transcription: .running(percent: 5), copyFailed: true)
        == Rules.recordingSymbol)
    #expect(Rules.label(for: recording, transcription: .running(percent: 5)) == .recording)
  }

  @Test func aRunningPassShowsItsSymbol() {
    #expect(
      Rules.symbol(for: idle, transcription: .running(percent: 40), copyFailed: false)
        == Rules.transcribingSymbol)
    #expect(Rules.showsItem(idle, transcription: .running(percent: 40), copyFailed: false))
    #expect(Rules.label(for: idle, transcription: .running(percent: 40)) == .transcribing)
  }

  @Test func aRecorderNoticeOutranksAFinishedPass() {
    let ended = MeetingStatus(notice: .cannotStart)
    #expect(
      Rules.symbol(
        for: ended, transcription: .finished(transcribed: 1, failed: 0), copyFailed: false)
        == Rules.symbol(for: ended))
  }

  @Test func aFinishedPassShowsTheItem() {
    let ready = MeetingTranscription.finished(transcribed: 2, failed: 0)
    #expect(Rules.showsItem(idle, transcription: ready, copyFailed: false))
    #expect(Rules.symbol(for: idle, transcription: ready, copyFailed: false) == Rules.endedSymbol)
    #expect(Rules.label(for: idle, transcription: ready) == .idle)
  }

  @Test func failuresAskForAttention() {
    #expect(
      Rules.symbol(
        for: idle, transcription: .finished(transcribed: 1, failed: 1), copyFailed: false)
        == Rules.warningSymbol)
    #expect(Rules.symbol(for: idle, transcription: nil, copyFailed: true) == Rules.warningSymbol)
    #expect(Rules.showsItem(idle, transcription: nil, copyFailed: true))
  }

  @Test func nothingToShowHidesTheItem() {
    #expect(!Rules.showsItem(idle, transcription: nil, copyFailed: false))
  }

  @Test func progressIsNotAnnounced() {
    #expect(Rules.announcements(from: nil, to: .running(percent: 0)).isEmpty)
    #expect(Rules.announcements(from: .running(percent: 0), to: .running(percent: 50)).isEmpty)
  }

  @Test func aFinishedPassIsAnnouncedOnce() {
    let ready = MeetingTranscription.finished(transcribed: 1, failed: 0)
    #expect(Rules.announcements(from: .running(percent: 99), to: ready) == [ready])
    #expect(Rules.announcements(from: ready, to: ready).isEmpty)
    #expect(Rules.announcements(from: ready, to: nil).isEmpty)
  }

  @Test func removingDuringAPassPutsItBack() {
    #expect(Rules.removal(of: idle, transcription: .running(percent: 1)) == .putBack)
    #expect(
      Rules.removal(of: idle, transcription: .finished(transcribed: 1, failed: 0)) == .dismiss)
    #expect(Rules.removal(of: MeetingStatus(isRecording: true), transcription: nil) == .putBack)
  }
}
