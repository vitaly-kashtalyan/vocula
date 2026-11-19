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
        String(localized: MenuCopy.meetingStatusLabel(recording: true)),
        String(localized: MenuCopy.meetingStatusLabel(recording: false)),
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
        String(localized: MenuCopy.meetingStatusLabel(recording: true)) + "\n"
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
    let recording = english(MenuCopy.meetingStatusLabel(recording: true))
    let notice = english(MenuCopy.meetingStatusLabel(recording: false))
    #expect(recording == "Vocula is recording a meeting")
    #expect(notice != recording)
  }
}
