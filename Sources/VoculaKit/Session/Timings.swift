import Foundation

public struct Timings: Sendable, Equatable {
  public var minRecording: Duration

  public static let implausibleHold: Duration = .seconds(30)
  public static let implausibleRetap: Duration = .milliseconds(400)
  public var maxRecording: Duration
  public var whisperPass: Duration
  public var queueWait: Duration
  public var maxPending: Int
  public var clipboardRestore: Duration
  public var roleQuery: Duration

  public init(
    minRecording: Duration = .milliseconds(300),
    maxRecording: Duration = .seconds(180),
    whisperPass: Duration = .seconds(30),
    queueWait: Duration = .seconds(120),
    maxPending: Int = 8,
    clipboardRestore: Duration = .seconds(1),
    roleQuery: Duration = .milliseconds(150)
  ) {
    self.minRecording = minRecording
    self.maxRecording = maxRecording
    self.whisperPass = whisperPass
    self.queueWait = queueWait
    self.maxPending = maxPending
    self.clipboardRestore = clipboardRestore
    self.roleQuery = roleQuery
  }

  public func passDeadline(forAudio duration: Duration) -> Duration {
    max(whisperPass, duration)
  }

  public static let `default` = Timings()
}

extension Duration {
  public var milliseconds: Int {
    let c = components
    return Int(c.seconds) * 1000 + Int(c.attoseconds / 1_000_000_000_000_000)
  }
}
