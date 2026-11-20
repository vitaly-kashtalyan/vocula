import Testing

@testable import VoculaKit

@Suite struct MeetingPassScheduleTests {
  @Test func aRequestStartsAPassWhenIdle() {
    var schedule = MeetingPassSchedule()
    let started = schedule.requested()
    let again = schedule.passEnded()
    #expect(started)
    #expect(!again)
  }

  @Test func aRequestDuringAPassRunsOnceMore() {
    var schedule = MeetingPassSchedule()
    _ = schedule.requested()
    let during = [schedule.requested(), schedule.requested()]
    let ends = [schedule.passEnded(), schedule.passEnded()]
    #expect(during == [false, false])
    #expect(ends == [true, false])
  }

  @Test func noPassAfterTerminate() {
    var schedule = MeetingPassSchedule()
    schedule.terminate()
    let started = schedule.requested()
    #expect(!started)
  }

  @Test func aTerminateDuringAPassDropsTheRerun() {
    var schedule = MeetingPassSchedule()
    _ = schedule.requested()
    _ = schedule.requested()
    schedule.terminate()
    let rerun = schedule.passEnded()
    #expect(!rerun)
  }
}
