import Foundation
import Testing

@testable import VoculaKit

private let minute: UInt64 = 60_000_000_000

@Suite struct SilenceStopTests {
  @Test func silenceWarnsAtFourteenAndStopsAtFifteen() {
    var stop = SilenceStop(startedAt: 0)
    #expect(stop.levels(micPeak: 0, systemPeak: 0, at: 14 * minute - 1) == .recording)
    #expect(stop.levels(micPeak: 0, systemPeak: 0, at: 14 * minute) == .stopsSoon)
    #expect(stop.levels(micPeak: 0, systemPeak: 0, at: 15 * minute) == .stop)
  }

  @Test func aQuietMicrophoneDoesNotResetTheClock() {
    var stop = SilenceStop(startedAt: 0)
    #expect(stop.levels(micPeak: 327, systemPeak: 0, at: 10 * minute) == .recording)
    #expect(stop.levels(micPeak: 0, systemPeak: 0, at: 15 * minute) == .stop)
  }

  @Test func soundOnTheMicrophoneResetsTheClock() {
    var stop = SilenceStop(startedAt: 0)
    _ = stop.levels(micPeak: 328, systemPeak: 0, at: 10 * minute)
    #expect(stop.levels(micPeak: 0, systemPeak: 0, at: 15 * minute) == .recording)
    #expect(stop.levels(micPeak: 0, systemPeak: 0, at: 24 * minute) == .stopsSoon)
    #expect(stop.levels(micPeak: 0, systemPeak: 0, at: 25 * minute) == .stop)
  }

  @Test func anyOtherAppSoundResetsTheClock() {
    var stop = SilenceStop(startedAt: 0)
    _ = stop.levels(micPeak: 0, systemPeak: 1, at: 5 * minute)
    #expect(stop.levels(micPeak: 0, systemPeak: 0, at: 15 * minute) == .recording)
  }

  @Test func anEarlierClockKeepsRecording() {
    var stop = SilenceStop(startedAt: 10 * minute)
    #expect(stop.levels(micPeak: 0, systemPeak: 0, at: 1 * minute) == .recording)
  }
}

@Suite struct MicReopenScheduleTests {
  private let second: UInt64 = 1_000_000_000

  @Test func theDelayDoublesToAMinute() {
    var schedule = MicReopenSchedule()
    #expect(schedule.lost(at: 0) == 5 * second)
    #expect(schedule.timerAttemptFailed(at: 5 * second) == 15 * second)
    #expect(schedule.timerAttemptFailed(at: 15 * second) == 35 * second)
    #expect(schedule.timerAttemptFailed(at: 35 * second) == 75 * second)
    #expect(schedule.timerAttemptFailed(at: 75 * second) == 135 * second)
    #expect(schedule.timerAttemptFailed(at: 135 * second) == 195 * second)
  }

  @Test func aDeviceListAttemptDoesNotMoveTheTimer() {
    var schedule = MicReopenSchedule()
    _ = schedule.lost(at: 0)
    schedule.deviceListAttemptFailed()
    #expect(schedule.timerAttemptFailed(at: 5 * second) == 15 * second)
  }

  @Test func aReopenReportsAttemptsAndResets() {
    var schedule = MicReopenSchedule()
    _ = schedule.lost(at: 0)
    _ = schedule.timerAttemptFailed(at: 5 * second)
    _ = schedule.timerAttemptFailed(at: 15 * second)
    schedule.deviceListAttemptFailed()
    #expect(schedule.reopened() == 4)
    #expect(schedule.attempts == 0)
    #expect(schedule.lost(at: 1_000 * second) == 1_005 * second)
  }
}

@Suite(.timeLimit(.minutes(1))) struct MeetingBoundTests {
  private let bound = Duration.seconds(3)

  @Test func aQuickWorkIsAwaited() async {
    let clock = TestClock()
    let start = clock.now()
    let latch = Latch()
    let work = Task { await latch.wait() }
    let result = Task {
      await MeetingBound.wait(for: work, atMost: bound, sleep: { try await clock.sleep(for: $0) })
    }
    await clock.untilSleeping()
    latch.open()
    #expect(await result.value == true)
    #expect(clock.now() == start)
  }

  @Test func aHungWorkIsAbandonedAtTheBound() async {
    let clock = TestClock()
    let latch = Latch()
    let work = Task { await latch.wait() }
    let result = Task {
      await MeetingBound.wait(for: work, atMost: bound, sleep: { try await clock.sleep(for: $0) })
    }
    await clock.untilSleeping()
    clock.advance(by: .seconds(2))
    await clock.untilSleeping()
    clock.advance(by: .seconds(1))
    #expect(await result.value == false)
    #expect(work.isCancelled == false)
    latch.open()
    await work.value
  }
}
