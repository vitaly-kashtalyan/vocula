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

  @ObservationIgnored private let announce: @MainActor (String) -> Void

  init(announce: @escaping @MainActor (String) -> Void = { Announce.say($0) }) {
    self.announce = announce
  }

  var symbol: String { MeetingStatusRules.symbol(for: status) }

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
    let shown = MeetingStatusRules.showsItem(new)
    if statusItemShown != shown { statusItemShown = shown }
    for announcement in MeetingStatusRules.announcements(from: old, to: new) {
      switch announcement {
      case .warning(let warning): announce(String(localized: MenuCopy.meetingWarning(warning)))
      case .notice(let notice): announce(String(localized: MenuCopy.meetingNotice(notice)))
      }
    }
  }

  func dismiss() {
    if notice != nil { notice = nil }
    let shown = MeetingStatusRules.showsItem(status)
    if statusItemShown != shown { statusItemShown = shown }
  }

  @discardableResult
  func statusItemRemoved() -> Task<Void, Never>? {
    switch MeetingStatusRules.removal(of: status) {
    case .putBack:
      statusItemShown = false
      return Task { @MainActor in
        if MeetingStatusRules.showsItem(status) { statusItemShown = true }
      }
    case .dismiss:
      dismiss()
      return nil
    }
  }
}
