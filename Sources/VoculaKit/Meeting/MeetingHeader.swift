import Foundation

public enum HostTime {
  public static func elapsed(from start: UInt64, to end: UInt64) -> UInt64 {
    let (value, overflow) = end.subtractingReportingOverflow(start)
    return overflow ? 0 : value
  }

  public static func adding(_ a: UInt64, _ b: UInt64) -> UInt64 {
    let (value, overflow) = a.addingReportingOverflow(b)
    return overflow ? .max : value
  }

  public static func nanos(_ seconds: Double) -> UInt64 {
    guard !seconds.isNaN, seconds > 0 else { return 0 }
    let value = seconds * 1_000_000_000
    return value >= 18_446_744_073_709_551_616.0 ? .max : UInt64(value)
  }
}

public enum MeetingFailure: Error, Equatable, Sendable {
  case secondCopy
  case notOpened
  case failed(step: String, code: Int32)
}

public enum MeetingTrack: String, Codable, CaseIterable, Sendable {
  case mic
  case system

  public var soundFloor: Int16 {
    switch self {
    case .mic: 328
    case .system: 1
    }
  }
}

public enum MeetingState: String, Codable, Sendable {
  case recording
  case recorded
}

public enum MeetingEnd: String, Codable, CaseIterable, Sendable {
  case stopped
  case autoStopped
  case sleep
  case quit
  case interrupted
}

public struct DictationSpan: Codable, Equatable, Sendable {
  public let start: UInt64
  public let end: UInt64

  public init(start: UInt64, end: UInt64) {
    self.start = start
    self.end = end
  }
}

public struct MeetingHeader: Codable, Equatable, Sendable {
  public let id: UUID
  public let startedAt: Date
  public let anchor: UInt64
  public var end: Date?
  public var state: MeetingState
  public var endedBy: MeetingEnd?
  public var dictations: [DictationSpan]

  public init(id: UUID, startedAt: Date, anchor: UInt64) {
    self.id = id
    self.startedAt = startedAt
    self.anchor = anchor
    self.end = nil
    self.state = .recording
    self.endedBy = nil
    self.dictations = []
  }

  public func date(atHost host: UInt64) -> Date {
    let nanos = HostTime.elapsed(from: anchor, to: host)
    return startedAt.addingTimeInterval(Double(nanos) / 1_000_000_000)
  }
}

public enum MeetingAggregate {
  public static let name = "CADefaultDeviceAggregate-Vocula"

  public static func uid(_ id: UUID) -> String {
    "CADefaultDeviceAggregate-Vocula-\(id.uuidString)"
  }
}
