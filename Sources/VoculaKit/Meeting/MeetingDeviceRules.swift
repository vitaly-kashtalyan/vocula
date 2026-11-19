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
    let silent = among.filter { $0.outputStreams > 0 && $0.inputStreams == 0 }
    return silent.first { $0.isBuiltIn } ?? silent.first { $0.uid == defaultOutputUID }
  }
}

public enum MeetingTapStream {
  public static func index(bufferCount: Int, lastBufferChannels: UInt32) -> Int? {
    bufferCount == 1 && lastBufferChannels == 1 ? 0 : nil
  }
}
