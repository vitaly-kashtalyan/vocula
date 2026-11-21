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

  @Test func aDeleteIsRefusedDuringAPass() {
    var schedule = MeetingPassSchedule()
    _ = schedule.requested()
    let began = schedule.deleteBegan()
    #expect(!began)
  }

  @Test func aPassRequestedDuringADeleteStartsWhenItEnds() {
    var schedule = MeetingPassSchedule()
    let began = schedule.deleteBegan()
    let requested = schedule.requested()
    let ended = schedule.deleteEnded()
    #expect(began)
    #expect(!requested)
    #expect(ended)
  }

  @Test func twoDeletesHoldThePassUntilBothEnd() {
    var schedule = MeetingPassSchedule()
    let first = schedule.deleteBegan()
    let second = schedule.deleteBegan()
    let requested = schedule.requested()
    let firstEnd = schedule.deleteEnded()
    let secondEnd = schedule.deleteEnded()
    #expect(first && second)
    #expect(!requested)
    #expect(!firstEnd)
    #expect(secondEnd)
  }

  @Test func aDeleteAfterTerminateIsRefused() {
    var schedule = MeetingPassSchedule()
    schedule.terminate()
    let began = schedule.deleteBegan()
    #expect(!began)
  }

  @Test func aDeleteWithNoPassWantedStartsNone() {
    var schedule = MeetingPassSchedule()
    _ = schedule.deleteBegan()
    let ended = schedule.deleteEnded()
    #expect(!ended)
  }
}
