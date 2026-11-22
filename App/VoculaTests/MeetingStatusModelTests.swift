import Foundation
import Testing

@testable import Vocula
@testable import VoculaKit

@MainActor
@Suite("The meeting's status item shows what the meeting is doing")
struct MeetingStatusModelTests {
  private final class Spoken { var lines: [String] = [] }
  private final class Flag: @unchecked Sendable { var raised = false }

  private func make() -> (MeetingStatusModel, Spoken) {
    let spoken = Spoken()
    return (MeetingStatusModel(announce: { spoken.lines.append($0) }), spoken)
  }

  private func english(_ resource: LocalizedStringResource) -> String {
    var resource = resource
    resource.locale = Locale(identifier: "en")
    return String(localized: resource)
  }

  @Test func recordingShowsTheItemWithItsStartTime() {
    let (model, _) = make()
    let start = Date(timeIntervalSince1970: 1_000)
    model.update(MeetingStatus(isRecording: true, startedAt: start))
    #expect(model.isRecording)
    #expect(model.statusItemShown)
    #expect(model.startedAt == start)
    #expect(model.symbol == "record.circle.fill")
  }

  private func shown(_ model: MeetingStatusModel) async -> String? {
    for _ in 0..<100 where model.elapsed == nil { try? await Task.sleep(for: .milliseconds(10)) }
    return model.elapsed
  }

  @Test func theTimerCountsFromTheStartAndStopsWithTheRecording() async throws {
    let (model, _) = make()
    model.update(MeetingStatus(isRecording: true, startedAt: Date(timeIntervalSinceNow: -65)))
    let first = await shown(model)
    #expect(first == MeetingStatusRules.elapsed(65) || first == MeetingStatusRules.elapsed(66))
    model.update(MeetingStatus(isRecording: true, startedAt: Date(timeIntervalSinceNow: -5)))
    let restarted = await shown(model)
    #expect(
      restarted == MeetingStatusRules.elapsed(5) || restarted == MeetingStatusRules.elapsed(6))
    model.update(MeetingStatus())
    #expect(model.elapsed == nil)
    try await Task.sleep(for: .milliseconds(1_200))
    #expect(model.elapsed == nil)
  }

  @Test func theMenuObservesOnlyRecording() {
    let (model, _) = make()
    model.update(MeetingStatus(isRecording: true, startedAt: Date()))
    let fired = Flag()
    withObservationTracking({ _ = model.isRecording }) { fired.raised = true }
    model.update(
      MeetingStatus(isRecording: true, startedAt: model.startedAt, warnings: [.noSystemAudio]))
    #expect(!fired.raised)
    model.update(MeetingStatus(isRecording: false))
    #expect(fired.raised)
  }

  @Test func aWarningIsAnnouncedOnce() {
    let (model, spoken) = make()
    let start = Date()
    model.update(MeetingStatus(isRecording: true, startedAt: start))
    let status = MeetingStatus(isRecording: true, startedAt: start, warnings: [.noSystemAudio])
    model.update(status)
    model.update(status)
    #expect(
      spoken.lines.dropFirst() == [String(localized: MenuCopy.meetingWarning(.noSystemAudio))])
  }

  @Test func aStartAndAStopAreAnnounced() {
    let (model, spoken) = make()
    model.update(MeetingStatus(isRecording: true, startedAt: Date()))
    model.update(MeetingStatus())
    #expect(
      spoken.lines == [
        String(localized: MenuCopy.meetingItemLabel(.recording)),
        String(localized: MenuCopy.meetingItemLabel(.idle)),
      ])
  }

  @Test func aMeetingThatEndsWithANoticeSpeaksOnlyTheNotice() {
    let (model, spoken) = make()
    model.update(MeetingStatus(isRecording: true, startedAt: Date()))
    model.update(MeetingStatus(notice: .autoStopped))
    #expect(spoken.lines.dropFirst() == [String(localized: MenuCopy.meetingNotice(.autoStopped))])
  }

  @Test func oneUpdateIsSpokenAsOneAnnouncement() {
    let (model, spoken) = make()
    model.update(
      MeetingStatus(isRecording: true, startedAt: Date(), warnings: [.waitingForPermission]))
    #expect(
      spoken.lines == [
        String(localized: MenuCopy.meetingItemLabel(.recording)) + "\n"
          + String(localized: MenuCopy.meetingWarning(.waitingForPermission))
      ])
  }

  @Test(arguments: [(true, false, false), (false, true, false), (false, false, true)])
  func onlyAUsersRemovalOfAShownItemActs(hiddenFirst: Bool, written: Bool, removes: Bool) async {
    let (model, _) = make()
    model.update(MeetingStatus(isRecording: true, startedAt: Date()))
    let putBack = hiddenFirst ? model.statusItemRemoved() : nil
    let shownBefore = model.statusItemShown
    let removal = model.insertionWritten(written)
    #expect((removal != nil) == removes)
    #expect(model.statusItemShown == (shownBefore && !removes))
    await putBack?.value
    await removal?.value
    #expect(model.statusItemShown)
  }

  @Test func aRemovedItemComesBackWhileRecording() async {
    let (model, _) = make()
    model.update(MeetingStatus(isRecording: true, startedAt: Date()))
    let task = model.statusItemRemoved()
    #expect(!model.statusItemShown)
    await task?.value
    #expect(model.statusItemShown)
  }

  @Test func aMeetingThatEndedWhileTheItemWasRemovedStaysHidden() async {
    let (model, _) = make()
    model.update(MeetingStatus(isRecording: true, startedAt: Date()))
    let task = model.statusItemRemoved()
    model.update(MeetingStatus())
    await task?.value
    #expect(!model.statusItemShown)
  }

  @Test func removingTheItemDismissesANotice() {
    let (model, _) = make()
    model.update(MeetingStatus(notice: .autoStopped))
    #expect(model.statusItemShown)
    #expect(model.statusItemRemoved() == nil)
    #expect(model.notice == nil)
    #expect(!model.statusItemShown)
  }

  @Test func aNoticeStaysUntilDismissed() {
    let (model, _) = make()
    model.update(MeetingStatus(notice: .cannotStart))
    #expect(model.statusItemShown)
    #expect(model.notice == .cannotStart)
    model.dismiss()
    #expect(model.notice == nil)
    #expect(!model.statusItemShown)
  }

  @Test func theNoticeLabelDoesNotSayRecording() {
    let recording = english(MenuCopy.meetingItemLabel(.recording))
    let notice = english(MenuCopy.meetingItemLabel(.idle))
    #expect(recording == "Vocula is recording a meeting")
    #expect(notice != recording)
  }

  @Test func aPassIsShownAndItsEndAnnouncedOnce() {
    let (model, spoken) = make()
    model.update(transcription: .running(percent: 10))
    #expect(model.statusItemShown)
    #expect(model.label == .transcribing)
    #expect(model.symbol == MeetingStatusRules.transcribingSymbol)
    #expect(spoken.lines.isEmpty)
    model.update(transcription: .finished(transcribed: 1, failed: 0))
    model.update(transcription: .finished(transcribed: 1, failed: 0))
    #expect(
      spoken.lines == [
        String(localized: MenuCopy.meetingTranscription(.finished(transcribed: 1, failed: 0))[0])
      ])
    #expect(model.canDismiss)
  }

  @Test func theRecorderCannotClearTheTranscriptionState() {
    let (model, _) = make()
    model.update(transcription: .finished(transcribed: 2, failed: 0))
    model.update(MeetingStatus())
    #expect(model.transcription == .finished(transcribed: 2, failed: 0))
    #expect(model.statusItemShown)
  }

  @Test func dismissClearsTheFinishedPass() {
    let (model, _) = make()
    model.update(transcription: .finished(transcribed: 1, failed: 1))
    model.dismiss()
    #expect(model.transcription == nil)
    #expect(!model.statusItemShown)
  }

  @Test func aRunningPassSurvivesDismiss() {
    let (model, _) = make()
    model.update(transcription: .running(percent: 3))
    model.dismiss()
    #expect(model.transcription == .running(percent: 3))
    #expect(model.statusItemShown)
  }

  @Test func everyUnreadableCopyIsAnnounced() {
    let (model, spoken) = make()
    model.transcriptUnreadable()
    model.transcriptUnreadable()
    #expect(
      spoken.lines == Array(repeating: String(localized: MenuCopy.transcriptUnreadable), count: 2))
    #expect(model.statusItemShown)
    #expect(model.symbol == MeetingStatusRules.warningSymbol)
    model.dismiss()
    #expect(!model.copyFailed)
    #expect(!model.statusItemShown)
  }

  @Test func theMainMenuIgnoresProgress() {
    let (model, _) = make()
    let fired = Flag()
    withObservationTracking({
      _ = model.isRecording
      _ = model.transcripts
    }) { fired.raised = true }
    model.update(transcription: .running(percent: 5))
    model.update(transcription: .running(percent: 6))
    #expect(!fired.raised)
    model.update(
      listing: .meetings([
        MeetingListing(id: UUID(), startedAt: Date(timeIntervalSince1970: 0), duration: 60)
      ]))
    #expect(fired.raised)
  }

  @Test func theSubmenuSeesOnlyTranscribedMeetings() {
    let (model, _) = make()
    let done = MeetingListing(id: UUID(), startedAt: Date(timeIntervalSince1970: 0), duration: 6)
    let waiting = MeetingListing(
      id: UUID(), startedAt: Date(timeIntervalSince1970: 9), duration: 6, hasTranscript: false)
    model.update(listing: .meetings([waiting, done]))
    #expect(model.transcripts == [done])
    #expect(model.meetings.count == 2)
  }

  @Test func readingUntilTheFirstListingThenTheLineAloneWhenItFails() {
    let (model, spoken) = make()
    #expect(model.sectionContent == .reading)
    model.update(listing: .unreadable(step: "key", code: -25308))
    #expect(model.sectionContent == .lineAlone)
    model.update(listing: .unreadable(step: "key", code: -25308))
    #expect(spoken.lines.count == 1)
  }

  @Test func anUnreadableListingKeepsTheLastListAndClearsOnSuccess() {
    let (model, _) = make()
    let done = MeetingListing(id: UUID(), startedAt: Date(timeIntervalSince1970: 0), duration: 6)
    model.update(listing: .meetings([done]))
    model.update(listing: .noKey(holdsMeetings: true))
    #expect(model.meetings == [done])
    #expect(model.listUnreadable)
    model.update(listing: .meetings([done]))
    #expect(!model.listUnreadable)
  }
}
