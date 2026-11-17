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
    let status = MeetingStatus(isRecording: true, startedAt: Date(), warnings: [.noSystemAudio])
    model.update(status)
    model.update(status)
    #expect(spoken.lines == [String(localized: MenuCopy.meetingWarning(.noSystemAudio))])
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
