import Foundation

public enum MeetingListingStatus: Equatable, Sendable {
  case transcribed
  case recording
  case waiting
}

public enum MeetingAction: CaseIterable, Sendable {
  case open
  case rename
  case pin
  case export
  case copy
  case delete
}

public struct MeetingListing: Equatable, Sendable, Identifiable {
  public let id: UUID
  public let startedAt: Date
  public let duration: TimeInterval
  public let hasEnd: Bool
  public let title: String?
  public let isPinned: Bool
  public let isRecordingState: Bool
  public let hasTranscript: Bool

  public init(
    id: UUID, startedAt: Date, duration: TimeInterval, hasEnd: Bool = true,
    title: String? = nil, isPinned: Bool = false, isRecordingState: Bool = false,
    hasTranscript: Bool = true
  ) {
    self.id = id
    self.startedAt = startedAt
    self.duration = duration
    self.hasEnd = hasEnd
    self.title = title
    self.isPinned = isPinned
    self.isRecordingState = isRecordingState
    self.hasTranscript = hasTranscript
  }

  public func status(busy: Bool) -> MeetingListingStatus {
    if hasTranscript { return .transcribed }
    return isRecordingState && busy ? .recording : .waiting
  }

  public func allows(_ action: MeetingAction, busy: Bool, passRunning: Bool) -> Bool {
    let status = status(busy: busy)
    switch action {
    case .open, .export, .copy: return status == .transcribed
    case .rename, .pin: return status != .recording
    case .delete: return status != .recording && !isPinned && !passRunning
    }
  }

  public static func ordered(_ listings: [MeetingListing]) -> [MeetingListing] {
    listings.sorted { a, b in
      a.isPinned != b.isPinned ? a.isPinned : a.startedAt > b.startedAt
    }
  }

  public static func transcribed(_ listings: [MeetingListing]) -> [MeetingListing] {
    listings.filter(\.hasTranscript).sorted { $0.startedAt > $1.startedAt }
  }
}

public enum MeetingListingOutcome: Equatable, Sendable {
  case meetings([MeetingListing])
  case noKey(holdsMeetings: Bool)
  case unreadable(step: String, code: Int)

  public var isUnreadable: Bool {
    switch self {
    case .meetings, .noKey(holdsMeetings: false): false
    case .noKey(holdsMeetings: true), .unreadable: true
    }
  }

  public static func failed(_ error: any Error, holdsMeetings: () -> Bool) -> MeetingListingOutcome
  {
    switch error {
    case MeetingFailure.failed(let step, let code)
    where step == "key"
      && code == MeetingKeyRule.itemNotFound:
      return .noKey(holdsMeetings: holdsMeetings())
    case MeetingFailure.failed(let step, let code):
      return .unreadable(step: step, code: Int(code))
    case MeetingStoreError.failed(let step, let code):
      return .unreadable(step: step, code: code)
    default:
      return .unreadable(step: "list", code: 0)
    }
  }
}

public enum MeetingSectionContent: Equatable, Sendable {
  case reading
  case empty
  case list
  case lineAlone

  public static func decide(loaded: Bool, meetings: [MeetingListing], unreadable: Bool)
    -> MeetingSectionContent
  {
    if !loaded { return .reading }
    if meetings.isEmpty { return unreadable ? .lineAlone : .empty }
    return .list
  }
}
