import Foundation

public struct MeetingInputCandidate: Equatable, Sendable {
  public let id: UInt32
  public let opensOnDemandOnly: Bool

  public init(id: UInt32, opensOnDemandOnly: Bool) {
    self.id = id
    self.opensOnDemandOnly = opensOnDemandOnly
  }
}

public enum MeetingMicrophoneRule {
  public static func device(resolved: UInt32?, among: [MeetingInputCandidate]) -> UInt32? {
    guard let resolved, among.contains(where: { $0.id == resolved && !$0.opensOnDemandOnly })
    else { return nil }
    return resolved
  }
}

public struct MeetingOutputCandidate: Equatable, Sendable {
  public let uid: String
  public let isBuiltIn: Bool
  public let outputStreams: Int
  public let inputStreams: Int

  public init(uid: String, isBuiltIn: Bool, outputStreams: Int, inputStreams: Int) {
    self.uid = uid
    self.isBuiltIn = isBuiltIn
    self.outputStreams = outputStreams
    self.inputStreams = inputStreams
  }
}

public enum MeetingClockDevice {
  public static func choose(
    among: [MeetingOutputCandidate], defaultOutputUID: String?
  ) -> MeetingOutputCandidate? {
    among.first { $0.isBuiltIn && $0.outputStreams > 0 }
      ?? among.first { $0.uid == defaultOutputUID && $0.outputStreams > 0 }
  }
}

public enum MeetingTapStream {
  public static func index(bufferCount: Int, lastBufferChannels: UInt32, outputInputStreams: Int)
    -> Int?
  {
    guard bufferCount == outputInputStreams + 1, lastBufferChannels == 1 else { return nil }
    return outputInputStreams
  }
}
