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
  case started, stopped
  case warning(MeetingWarning)
  case notice(MeetingNotice)
}

public enum MeetingStatusRules {
  static let recordingSymbol = "record.circle.fill"
  public static let warningSymbol = "exclamationmark.circle.fill"
  static let endedSymbol = "record.circle"

  public static func symbol(for status: MeetingStatus) -> String {
    guard status.warnings.isEmpty else { return warningSymbol }
    switch status.notice {
    case nil: return recordingSymbol
    case .cannotStart: return warningSymbol
    case .autoStopped, .endedBySleep: return endedSymbol
    }
  }

  public static func elapsed(_ seconds: Int, locale: Locale = .interface) -> String {
    let pattern: Duration.TimeFormatStyle.Pattern =
      seconds < 3600 ? .minuteSecond(padMinuteToLength: 2) : .hourMinuteSecond
    return Duration.seconds(max(seconds, 0)).formatted(
      Duration.TimeFormatStyle(pattern: pattern, locale: locale))
  }

  public static func showsItem(_ status: MeetingStatus) -> Bool {
    status.isRecording || status.notice != nil
  }

  public static func announcements(from old: MeetingStatus, to new: MeetingStatus)
    -> [MeetingAnnouncement]
  {
    var announced: [MeetingAnnouncement] = []
    if new.isRecording && !old.isRecording { announced.append(.started) }
    if old.isRecording && !new.isRecording && new.notice == nil { announced.append(.stopped) }
    announced += new.warnings.filter { !old.warnings.contains($0) }.map {
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

extension MeetingStatusRules {
  public static let transcribingSymbol = "text.bubble"

  public enum Label: Equatable, Sendable { case recording, transcribing, idle }

  public static func symbol(
    for status: MeetingStatus, transcription: MeetingTranscription?, copyFailed: Bool
  ) -> String {
    if status.isRecording || !status.warnings.isEmpty { return symbol(for: status) }
    if case .running = transcription { return transcribingSymbol }
    if status.notice != nil { return symbol(for: status) }
    if copyFailed { return warningSymbol }
    if case .finished(_, let failed) = transcription {
      return failed > 0 ? warningSymbol : endedSymbol
    }
    return symbol(for: status)
  }

  public static func showsItem(
    _ status: MeetingStatus, transcription: MeetingTranscription?, copyFailed: Bool
  ) -> Bool {
    showsItem(status) || transcription != nil || copyFailed
  }

  public static func label(for status: MeetingStatus, transcription: MeetingTranscription?)
    -> Label
  {
    if status.isRecording { return .recording }
    if case .running = transcription { return .transcribing }
    return .idle
  }

  public static func announcements(
    from old: MeetingTranscription?, to new: MeetingTranscription?
  ) -> MeetingTranscription? {
    guard let new, case .finished = new, new != old else { return nil }
    return new
  }

  public static func removal(of status: MeetingStatus, transcription: MeetingTranscription?)
    -> Removal
  {
    if case .running = transcription { return .putBack }
    return removal(of: status)
  }
}
