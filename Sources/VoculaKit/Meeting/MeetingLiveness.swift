import Foundation

public enum MeetingWarning: String, CaseIterable, Hashable, Sendable {
  case waitingForPermission, microphoneNotOpened, microphoneStopped
  case noSystemAudio, noSystemAudioYet, autoStopSoon, cannotSave
}

public enum MicrophoneTrackState: Equatable, Sendable {
  case opening, notOpened, failedToOpen
  case running(since: UInt64)
  case lost(at: UInt64)
}

public enum SystemTrackState: Equatable, Sendable {
  case starting(at: UInt64)
  case running(since: UInt64)
  case failed
}

public struct MeetingSample: Sendable {
  public var now: UInt64
  public var microphone: MicrophoneTrackState
  public var microphoneCallbacks: Int
  public var system: SystemTrackState
  public var systemCallbacks: Int
  public var lastSystemSound: UInt64?
  public var autoStopSoon: Bool

  public init(
    now: UInt64, microphone: MicrophoneTrackState, microphoneCallbacks: Int,
    system: SystemTrackState, systemCallbacks: Int, lastSystemSound: UInt64?, autoStopSoon: Bool
  ) {
    self.now = now
    self.microphone = microphone
    self.microphoneCallbacks = microphoneCallbacks
    self.system = system
    self.systemCallbacks = systemCallbacks
    self.lastSystemSound = lastSystemSound
    self.autoStopSoon = autoStopSoon
  }
}

public struct MeetingLivenessReport: Equatable, Sendable {
  public let warnings: [MeetingWarning]
  public let raised: [MeetingWarning]
  public let systemZerosBegan: Bool
}

public struct MeetingLiveness: Sendable {
  private struct Pulse: Sendable {
    var since: UInt64
    var count = 0
    var changed: UInt64

    init(since: UInt64) {
      self.since = since
      changed = since
    }

    mutating func stalled(since: UInt64, count: Int, now: UInt64) -> Bool {
      if since != self.since { self = Pulse(since: since) }
      if count != self.count {
        self.count = count
        changed = now
      }
      return HostTime.elapsed(from: changed, to: now) >= MeetingLiveness.tenSeconds
    }
  }

  private static let second: UInt64 = 1_000_000_000
  private static let tenSeconds = 10 * second
  private static let permissionLimit = 15 * second
  private static let soundLimit = 60 * second

  private var previous: [MeetingWarning] = []
  private var microphonePulse = Pulse(since: 0)
  private var systemPulse = Pulse(since: 0)
  private var zerosReportedFor: UInt64?
  private var saveFailing = false

  public init() {}

  public mutating func sample(_ sample: MeetingSample) -> MeetingLivenessReport {
    let now = sample.now
    var found: Set<MeetingWarning> = []
    var zerosBegan = false

    switch sample.microphone {
    case .opening: break
    case .notOpened: found.insert(.microphoneNotOpened)
    case .failedToOpen: found.insert(.microphoneStopped)
    case .lost(let at):
      if HostTime.elapsed(from: at, to: now) >= Self.tenSeconds { found.insert(.microphoneStopped) }
    case .running(let since):
      if microphonePulse.stalled(since: since, count: sample.microphoneCallbacks, now: now) {
        found.insert(.microphoneStopped)
      }
    }

    switch sample.system {
    case .starting(let at):
      if HostTime.elapsed(from: at, to: now) >= Self.permissionLimit {
        found.insert(.waitingForPermission)
      }
    case .failed:
      found.insert(.noSystemAudio)
    case .running(let since):
      if systemPulse.stalled(since: since, count: sample.systemCallbacks, now: now) {
        found.insert(.noSystemAudio)
      }
      if let sound = sample.lastSystemSound {
        if HostTime.elapsed(from: sound, to: now) >= Self.soundLimit, zerosReportedFor != sound {
          zerosReportedFor = sound
          zerosBegan = true
        }
      } else if HostTime.elapsed(from: since, to: now) >= Self.soundLimit {
        found.insert(.noSystemAudioYet)
      }
    }

    if found.contains(.noSystemAudio) { found.remove(.noSystemAudioYet) }
    if sample.autoStopSoon { found.insert(.autoStopSoon) }
    if saveFailing { found.insert(.cannotSave) }

    let warnings = MeetingWarning.allCases.filter(found.contains)
    let raised = warnings.filter { !previous.contains($0) }
    previous = warnings
    return MeetingLivenessReport(warnings: warnings, raised: raised, systemZerosBegan: zerosBegan)
  }

  public mutating func saved(failed: Bool) -> Bool {
    let began = failed && !saveFailing
    saveFailing = failed
    return began
  }
}
