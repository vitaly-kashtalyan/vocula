import Testing

@testable import VoculaKit

@Suite struct MeetingPassScheduleTests {
  @Test func aRequestStartsAPassWhenIdle() {
    var schedule = MeetingPassSchedule()
    #expect(schedule.isIdle)
    #expect(schedule.requested(recording: false) == .start)
    #expect(schedule.running)
    #expect(!schedule.isIdle)
  }

  @Test func aRequestDuringAPassRunsOnceMore() {
    var schedule = MeetingPassSchedule()
    _ = schedule.requested(recording: false)
    #expect(schedule.requested(recording: false) == .none)
    #expect(schedule.requested(recording: false) == .none)
    #expect(schedule.passEnded(recording: false) == .start)
    #expect(schedule.passEnded(recording: false) == .none)
    #expect(schedule.isIdle)
  }

  @Test func noPassWhileRecording() {
    var schedule = MeetingPassSchedule()
    #expect(schedule.requested(recording: true) == .none)
    #expect(!schedule.isIdle)
    #expect(schedule.requested(recording: false) == .start)
  }

  @Test func recordingCancelsARunningPassAndWantsAnother() {
    var schedule = MeetingPassSchedule()
    _ = schedule.requested(recording: false)
    #expect(schedule.recordingStarted() == .cancel)
    #expect(schedule.passEnded(recording: true) == .none)
    #expect(schedule.requested(recording: false) == .start)
  }

  @Test func recordingWithNoPassCancelsNothing() {
    var schedule = MeetingPassSchedule()
    #expect(schedule.recordingStarted() == .none)
    #expect(schedule.isIdle)
  }

  @Test func noPassAfterTerminate() {
    var schedule = MeetingPassSchedule()
    schedule.terminate()
    #expect(schedule.requested(recording: false) == .none)
    #expect(schedule.isIdle)
  }
}
