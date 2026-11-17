import Foundation

public enum MeetingNotice: String, CaseIterable, Hashable, Sendable {
  case cannotStart, autoStopped, endedBySleep
}

public struct MeetingStatus: Equatable, Sendable {
  public var isRecording: Bool
  public var startedAt: Date?
  public var warnings: [MeetingWarning]
  public var notice: MeetingNotice?

  public init(
    isRecording: Bool = false, startedAt: Date? = nil, warnings: [MeetingWarning] = [],
    notice: MeetingNotice? = nil
  ) {
    self.isRecording = isRecording
    self.startedAt = startedAt
    self.warnings = warnings
    self.notice = notice
  }
}

public enum MeetingAnnouncement: Equatable, Sendable {
  case warning(MeetingWarning)
  case notice(MeetingNotice)
}

public enum MeetingStatusRules {
  public static let recordingSymbol = "record.circle.fill"
  public static let warningSymbol = "exclamationmark.circle.fill"

  public static func symbol(for status: MeetingStatus) -> String {
    status.warnings.isEmpty && status.notice == nil ? recordingSymbol : warningSymbol
  }

  public static func showsItem(_ status: MeetingStatus) -> Bool {
    status.isRecording || status.notice != nil
  }

  public static func announcements(from old: MeetingStatus, to new: MeetingStatus)
    -> [MeetingAnnouncement]
  {
    var announced = new.warnings.filter { !old.warnings.contains($0) }.map {
      MeetingAnnouncement.warning($0)
    }
    if let notice = new.notice, notice != old.notice { announced.append(.notice(notice)) }
    return announced
  }

  public enum Removal: Equatable, Sendable { case putBack, dismiss }

  public static func removal(of status: MeetingStatus) -> Removal {
    status.isRecording ? .putBack : .dismiss
  }
}

public struct MeetingSwitch: Sendable {
  public enum Press: Equatable, Sendable {
    case start(meeting: Int, recover: Bool)
    case stop(meeting: Int)
    case ignore
  }

  private enum Phase: Sendable {
    case idle
    case starting(Int)
    case recording(Int)
  }

  private var phase = Phase.idle
  private var last = 0
  private var recovered = false

  public init() {}

  public mutating func pressed() -> Press {
    switch phase {
    case .idle:
      last += 1
      phase = .starting(last)
      return .start(meeting: last, recover: !recovered)
    case .starting:
      return .ignore
    case .recording(let meeting):
      phase = .idle
      return .stop(meeting: meeting)
    }
  }

  public mutating func began(_ meeting: Int) {
    guard case .starting(meeting) = phase else { return }
    phase = .recording(meeting)
    recovered = true
  }

  public mutating func ended(_ meeting: Int) -> Bool {
    guard isCurrent(meeting) else { return false }
    phase = .idle
    return true
  }

  public func isCurrent(_ meeting: Int) -> Bool {
    switch phase {
    case .idle: false
    case .starting(let current), .recording(let current): current == meeting
    }
  }
}
