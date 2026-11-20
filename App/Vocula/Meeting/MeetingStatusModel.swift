import Foundation
import Observation
import VoculaKit

@MainActor @Observable
final class MeetingStatusModel {
  private(set) var isRecording = false
  private(set) var startedAt: Date?
  private(set) var warnings: [MeetingWarning] = []
  private(set) var notice: MeetingNotice?
  private(set) var statusItemShown = false
  private(set) var elapsed: String?
  private(set) var transcription: MeetingTranscription?
  private(set) var copyFailed = false
  private(set) var transcripts: [MeetingListing] = []

  @ObservationIgnored private let announce: @MainActor (String) -> Void
  @ObservationIgnored private var ticking: Date?
  @ObservationIgnored private var ticker: Task<Void, Never>?

  init(announce: @escaping @MainActor (String) -> Void = { Announce.say($0) }) {
    self.announce = announce
  }

  var symbol: String {
    MeetingStatusRules.symbol(for: status, transcription: transcription, copyFailed: copyFailed)
  }

  var label: MeetingStatusRules.Label {
    MeetingStatusRules.label(for: status, transcription: transcription)
  }

  var canDismiss: Bool {
    if notice != nil || copyFailed { return true }
    if case .finished = transcription { return true }
    return false
  }

  private var status: MeetingStatus {
    MeetingStatus(
      isRecording: isRecording, startedAt: startedAt, warnings: warnings, notice: notice)
  }

  func update(_ new: MeetingStatus) {
    let old = status
    if isRecording != new.isRecording { isRecording = new.isRecording }
    if startedAt != new.startedAt { startedAt = new.startedAt }
    if warnings != new.warnings { warnings = new.warnings }
    if notice != new.notice { notice = new.notice }
    refreshShown()
    tick(from: new.isRecording ? new.startedAt : nil)
    let spoken = MeetingStatusRules.announcements(from: old, to: new).map { announcement in
      switch announcement {
      case .started: String(localized: MenuCopy.meetingStatusLabel(recording: true))
      case .stopped: String(localized: MenuCopy.meetingStatusLabel(recording: false))
      case .warning(let warning): String(localized: MenuCopy.meetingWarning(warning))
      case .notice(let notice): String(localized: MenuCopy.meetingNotice(notice))
      }
    }
    if !spoken.isEmpty { announce(spoken.joined(separator: "\n")) }
  }

  private func tick(from since: Date?) {
    guard since != ticking else { return }
    ticking = since
    ticker?.cancel()
    if elapsed != nil { elapsed = nil }
    guard let since else { return }
    ticker = Task { [weak self] in
      while !Task.isCancelled {
        let text = MeetingStatusRules.elapsed(Int(Date().timeIntervalSince(since)))
        if self?.elapsed != text { self?.elapsed = text }
        try? await Task.sleep(for: .seconds(1))
      }
    }
  }

  func update(transcription new: MeetingTranscription?) {
    let old = transcription
    if transcription != new { transcription = new }
    refreshShown()
    let spoken = MeetingStatusRules.announcements(from: old, to: new).flatMap {
      MenuCopy.meetingTranscription($0).map { String(localized: $0) }
    }
    if !spoken.isEmpty { announce(spoken.joined(separator: "\n")) }
  }

  func update(transcripts new: [MeetingListing]) {
    if transcripts != new { transcripts = new }
  }

  func transcriptUnreadable() {
    guard !copyFailed else { return }
    copyFailed = true
    refreshShown()
    announce(String(localized: MenuCopy.transcriptUnreadable))
  }

  func clearTranscriptionOutcome() {
    if case .finished = transcription { transcription = nil }
    if copyFailed { copyFailed = false }
    refreshShown()
  }

  func dismiss() {
    if notice != nil { notice = nil }
    clearTranscriptionOutcome()
  }

  private func refreshShown() {
    let shown = MeetingStatusRules.showsItem(
      status, transcription: transcription, copyFailed: copyFailed)
    if statusItemShown != shown { statusItemShown = shown }
  }

  @discardableResult
  func insertionWritten(_ inserted: Bool) -> Task<Void, Never>? {
    // Workaround: SwiftUI echoes every programmatic isInserted change through the binding's setter (three times, with the value just built), so only a false while the item is shown is the user removing it.
    guard !inserted, statusItemShown else { return nil }
    return statusItemRemoved()
  }

  @discardableResult
  func statusItemRemoved() -> Task<Void, Never>? {
    switch MeetingStatusRules.removal(of: status, transcription: transcription) {
    case .putBack:
      statusItemShown = false
      return Task { @MainActor in
        if MeetingStatusRules.showsItem(
          status, transcription: transcription, copyFailed: copyFailed)
        {
          statusItemShown = true
        }
      }
    case .dismiss:
      dismiss()
      return nil
    }
  }
}
