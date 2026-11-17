import Testing

@testable import VoculaKit

private final class Probe {
  private var liveness = MeetingLiveness()
  func sample(_ sample: MeetingSample) -> MeetingLivenessReport { liveness.sample(sample) }
  func saved(failed: Bool) -> Bool { liveness.saved(failed: failed) }
}

@Suite struct MeetingLivenessTests {
  let s: UInt64 = 1_000_000_000

  private func sample(
    _ now: UInt64, mic: MicrophoneTrackState = .running(since: 0), micCallbacks: Int? = nil,
    system: SystemTrackState = .running(since: 0), callbacks: Int? = nil, sound: UInt64? = 0,
    autoStop: Bool = false
  ) -> MeetingSample {
    MeetingSample(
      now: now, microphone: mic, microphoneCallbacks: micCallbacks ?? Int(now / s) + 1,
      system: system,
      systemCallbacks: callbacks ?? Int(now / s) + 1, lastSystemSound: sound, autoStopSoon: autoStop
    )
  }

  @Test func aPendingStartWarnsAfter15Seconds() {
    let liveness = Probe()
    #expect(liveness.sample(sample(15 * s - 1, system: .starting(at: 0))).warnings == [])
    let report = liveness.sample(sample(15 * s, system: .starting(at: 0)))
    #expect(report.raised == [.waitingForPermission])
  }

  @Test func nothingElseIsSaidWhileTheStartIsPending() {
    let liveness = Probe()
    let report = liveness.sample(
      sample(100 * s, system: .starting(at: 0), callbacks: 0, sound: nil))
    #expect(report.warnings == [.waitingForPermission])
  }

  @Test func aClockEarlierThanTheStartWarnsNothing() {
    let liveness = Probe()
    #expect(liveness.sample(sample(50 * s, system: .starting(at: 100 * s))).warnings == [])
  }

  @Test func noCallbackTenSecondsAfterStartReturned() {
    let liveness = Probe()
    let report = liveness.sample(sample(10 * s, callbacks: 0))
    #expect(report.warnings == [.noSystemAudio])
  }

  @Test func callbacksStoppingForTenSecondsWarns() {
    let liveness = Probe()
    #expect(liveness.sample(sample(1 * s, callbacks: 5)).warnings == [])
    #expect(liveness.sample(sample(10 * s, callbacks: 5)).warnings == [])
    #expect(liveness.sample(sample(11 * s, callbacks: 5)).warnings == [.noSystemAudio])
  }

  @Test func sixtySecondsOfZerosAsksTheQuestion() {
    let liveness = Probe()
    #expect(liveness.sample(sample(59 * s, callbacks: 59, sound: nil)).warnings == [])
    #expect(
      liveness.sample(sample(60 * s, callbacks: 60, sound: nil)).warnings == [.noSystemAudioYet])
  }

  @Test func soundClearsTheQuestion() {
    let liveness = Probe()
    _ = liveness.sample(sample(60 * s, callbacks: 60, sound: nil))
    #expect(liveness.sample(sample(61 * s, callbacks: 61, sound: 61 * s)).warnings == [])
  }

  @Test("LIMIT: zeros after sound are not warned about") func zerosAfterSound() {
    let liveness = Probe()
    #expect(liveness.sample(sample(200 * s, callbacks: 200, sound: 10 * s)).warnings == [])
  }

  @Test func zerosAfterSoundBeginOneEpisode() {
    let liveness = Probe()
    #expect(liveness.sample(sample(69 * s, callbacks: 69, sound: 10 * s)).systemZerosBegan == false)
    #expect(liveness.sample(sample(70 * s, callbacks: 70, sound: 10 * s)).systemZerosBegan)
    #expect(liveness.sample(sample(71 * s, callbacks: 71, sound: 10 * s)).systemZerosBegan == false)
    #expect(liveness.sample(sample(80 * s, callbacks: 80, sound: 80 * s)).systemZerosBegan == false)
    #expect(liveness.sample(sample(140 * s, callbacks: 140, sound: 80 * s)).systemZerosBegan)
  }

  @Test func aFailedTapIsNoSystemAudio() {
    let liveness = Probe()
    #expect(liveness.sample(sample(1 * s, system: .failed)).warnings == [.noSystemAudio])
  }

  @Test func anOnDemandMicrophoneIsSaidOnce() {
    let liveness = Probe()
    let raised = (1...3).map { liveness.sample(sample(UInt64($0) * s, mic: .notOpened)).raised }
    #expect(raised == [[.microphoneNotOpened], [], []])
  }

  @Test func aMicrophoneThatFailedToOpenStopped() {
    let liveness = Probe()
    #expect(liveness.sample(sample(1, mic: .failedToOpen)).warnings == [.microphoneStopped])
  }

  @Test func aLostMicrophoneIsGivenTenSeconds() {
    let liveness = Probe()
    #expect(liveness.sample(sample(10 * s - 1, mic: .lost(at: 0))).warnings == [])
    #expect(liveness.sample(sample(10 * s, mic: .lost(at: 0))).warnings == [.microphoneStopped])
  }

  @Test func aMicrophoneThatNeverDeliversReadsAsStopped() {
    let liveness = Probe()
    let report = liveness.sample(sample(10 * s, mic: .running(since: 0), micCallbacks: 0))
    #expect(report.warnings == [.microphoneStopped])
  }

  @Test("LIMIT: a device delivering only zeros goes unreported") func zerosOnTheMicrophone() {
    let liveness = Probe()
    let report = liveness.sample(sample(3_600 * s, micCallbacks: 3_600, callbacks: 3_600))
    #expect(report.warnings == [])
  }

  @Test func aWarningIsRaisedOncePerEpisode() {
    let liveness = Probe()
    #expect(liveness.sample(sample(10 * s, mic: .lost(at: 0))).raised == [.microphoneStopped])
    let again = liveness.sample(sample(11 * s, mic: .lost(at: 0)))
    #expect(again.warnings == [.microphoneStopped])
    #expect(again.raised == [])
    #expect(
      liveness.sample(sample(12 * s, mic: .running(since: 12 * s), micCallbacks: 0)).warnings == [])
    #expect(liveness.sample(sample(30 * s, mic: .lost(at: 20 * s))).raised == [.microphoneStopped])
  }

  @Test func aWriteFailureEpisodeBeginsOnce() {
    let liveness = Probe()
    #expect(liveness.saved(failed: true))
    #expect(liveness.saved(failed: true) == false)
    #expect(liveness.sample(sample(1 * s)).warnings == [.cannotSave])
    #expect(liveness.saved(failed: false) == false)
    #expect(liveness.sample(sample(2 * s)).warnings == [])
    #expect(liveness.saved(failed: true))
  }

  @Test func autoStopSoonPassesThrough() {
    let liveness = Probe()
    #expect(liveness.sample(sample(1 * s, autoStop: true)).warnings == [.autoStopSoon])
  }
}
