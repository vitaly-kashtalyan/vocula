import Testing

@testable import VoculaKit

@Suite struct MeetingPowerSequenceTests {
  @Test func canSleepIsAllowedAtOnce() {
    var sequence = MeetingPowerSequence()
    #expect(
      sequence.received(MeetingPowerSequence.canSystemSleep, notification: 7) == [
        .allow(notification: 7)
      ])
  }

  @Test func willSleepStopsTheMeetingFirst() {
    var sequence = MeetingPowerSequence()
    #expect(
      sequence.received(MeetingPowerSequence.systemWillSleep, notification: 9) == [.stopMeeting])
    #expect(sequence.meetingStopped() == [.allow(notification: 9)])
  }

  @Test func theAllowPrecedesTheDeregistration() {
    var sequence = MeetingPowerSequence()
    _ = sequence.received(MeetingPowerSequence.systemWillSleep, notification: 9)
    #expect(sequence.releaseRequested() == [])
    #expect(sequence.meetingStopped() == [.allow(notification: 9), .deregister])
  }

  @Test func theBoundAllowsOnlyOnce() {
    var sequence = MeetingPowerSequence()
    _ = sequence.received(MeetingPowerSequence.systemWillSleep, notification: 9)
    #expect(sequence.meetingStopped() == [.allow(notification: 9)])
    #expect(sequence.meetingStopped() == [])
  }

  @Test func aReleaseWhileIdleDeregisters() {
    var sequence = MeetingPowerSequence()
    #expect(sequence.releaseRequested() == [.deregister])
    #expect(sequence.releaseRequested() == [])
    #expect(sequence.received(MeetingPowerSequence.canSystemSleep, notification: 1) == [])
  }

  @Test func otherMessagesDoNothing() {
    var sequence = MeetingPowerSequence()
    #expect(sequence.received(0xE000_0300, notification: 1) == [])
  }
}
