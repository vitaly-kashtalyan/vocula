import Foundation
import Observation
import VoculaKit

enum MeetingSectionFailure: Equatable {
  case notSaved
  case exportNotWritten
  case transcriptUnreadable
}

@MainActor @Observable
final class MeetingStatusModel {
  private(set) var isRecording = false
  private(set) var startedAt: Date?
  private(set) var warnings: [MeetingWarning] = []
  private(set) var notice: MeetingNotice?
  private(set) var statusItemShown = false
  private(set) var elapsed: String?
  private(set) var transcription: MeetingTranscription?
  private(set) var speakerModel: Int?
  private(set) var copyFailed = false
  private(set) var meetings: [MeetingListing] = []
  private(set) var listingLoaded = false
  private(set) var listUnreadable = false
  private(set) var busy = false
  private(set) var passRunning = false
  private(set) var sectionFailure: MeetingSectionFailure?

  var transcripts: [MeetingListing] { MeetingListing.transcribed(meetings) }

  var sectionContent: MeetingSectionContent {
    .decide(loaded: listingLoaded, meetings: meetings, unreadable: listUnreadable)
  }

  @ObservationIgnored private let announce: @MainActor (String) -> Void
  @ObservationIgnored private var ticking: Date?
  @ObservationIgnored private var ticker: Task<Void, Never>?

  init(announce: @escaping @MainActor (String) -> Void = { Announce.say($0) }) {
    self.announce = announce
  }

  var symbol: String {
    MeetingStatusRules.symbol(
      for: status, transcription: transcription, copyFailed: copyFailed,
      downloading: speakerModel != nil)
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
      case .started: String(localized: MenuCopy.meetingItemLabel(.recording))
      case .stopped: String(localized: MenuCopy.meetingItemLabel(.idle))
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

  func update(transcription new: MeetingTranscription) {
    let old = transcription
    if transcription != new { transcription = new }
    refreshShown()
    guard let finished = MeetingStatusRules.announcements(from: old, to: new) else { return }
    announce(
      MenuCopy.meetingTranscription(finished).map { String(localized: $0) }.joined(separator: "\n"))
  }

  func update(speakerModel new: Int?) {
    if speakerModel != new { speakerModel = new }
    refreshShown()
  }

  func update(listing: MeetingListingOutcome) {
    if !listingLoaded { listingLoaded = true }
    switch listing {
    case .meetings(let found):
      if meetings != found { meetings = found }
      if listUnreadable { listUnreadable = false }
    case .noKey(holdsMeetings: false):
      if !meetings.isEmpty { meetings = [] }
      if listUnreadable { listUnreadable = false }
    case .noKey(holdsMeetings: true), .unreadable:
      guard !listUnreadable else { return }
      listUnreadable = true
      announce(String(localized: MenuCopy.meetingsListFailed))
    }
  }

  func sectionFailed(_ failure: MeetingSectionFailure) {
    sectionFailure = failure
    let line: LocalizedStringResource =
      switch failure {
      case .notSaved: MenuCopy.meetingNotSaved
      case .exportNotWritten: MenuCopy.meetingExportFailed
      case .transcriptUnreadable: MenuCopy.transcriptUnreadable
      }
    announce(String(localized: line))
  }

  func actionSucceeded() {
    if sectionFailure != nil { sectionFailure = nil }
  }

  func update(busy: Bool, passRunning: Bool) {
    if self.busy != busy { self.busy = busy }
    if self.passRunning != passRunning { self.passRunning = passRunning }
  }

  func transcriptUnreadable() {
    if !copyFailed { copyFailed = true }
    refreshShown()
    announce(String(localized: MenuCopy.transcriptUnreadable))
  }

  func transcriptCopied() {
    guard copyFailed else { return }
    copyFailed = false
    refreshShown()
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

  private var itemShouldShow: Bool {
    MeetingStatusRules.showsItem(
      status, transcription: transcription, copyFailed: copyFailed,
      downloading: speakerModel != nil)
  }

  private func refreshShown() {
    if statusItemShown != itemShouldShow { statusItemShown = itemShouldShow }
  }

  @discardableResult
  func insertionWritten(_ inserted: Bool) -> Task<Void, Never>? {
    // Workaround: SwiftUI echoes every programmatic isInserted change through the binding's setter (three times, with the value just built), so only a false while the item is shown is the user removing it.
    guard !inserted, statusItemShown else { return nil }
    return statusItemRemoved()
  }

  @discardableResult
  func statusItemRemoved() -> Task<Void, Never>? {
    switch MeetingStatusRules.removal(
      of: status, transcription: transcription, downloading: speakerModel != nil)
    {
    case .putBack:
      statusItemShown = false
      return Task { @MainActor in
        if itemShouldShow {
          statusItemShown = true
        }
      }
    case .dismiss:
      dismiss()
      return nil
    }
  }
}
