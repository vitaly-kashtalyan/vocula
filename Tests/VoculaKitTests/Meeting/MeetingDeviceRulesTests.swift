import Testing

@testable import VoculaKit

@Suite struct MeetingMicrophoneRuleTests {
  @Test func aWiredMicrophoneIsOpened() {
    let among = [MeetingInputCandidate(id: 7, opensOnDemandOnly: false)]
    #expect(MeetingMicrophoneRule.device(resolved: 7, among: among) == 7)
  }

  @Test func anOnDemandMicrophoneIsNotOpened() {
    let among = [
      MeetingInputCandidate(id: 7, opensOnDemandOnly: true),
      MeetingInputCandidate(id: 8, opensOnDemandOnly: false),
    ]
    #expect(MeetingMicrophoneRule.device(resolved: 7, among: among) == nil)
  }

  @Test func noDeviceMeansNone() {
    let among = [MeetingInputCandidate(id: 7, opensOnDemandOnly: false)]
    #expect(MeetingMicrophoneRule.device(resolved: nil, among: among) == nil)
  }

  @Test func anUnlistedDeviceIsNotOpened() {
    let among = [MeetingInputCandidate(id: 7, opensOnDemandOnly: false)]
    #expect(MeetingMicrophoneRule.device(resolved: 9, among: among) == nil)
  }
}

@Suite struct MeetingClockDeviceTests {
  let usb = MeetingOutputCandidate(uid: "usb", isBuiltIn: false, outputStreams: 1, inputStreams: 0)
  let headset = MeetingOutputCandidate(
    uid: "headset", isBuiltIn: false, outputStreams: 1, inputStreams: 1)
  let speakers = MeetingOutputCandidate(
    uid: "spk", isBuiltIn: true, outputStreams: 1, inputStreams: 0)
  let builtInWithInput = MeetingOutputCandidate(
    uid: "bi", isBuiltIn: true, outputStreams: 1, inputStreams: 1)
  let mic = MeetingOutputCandidate(uid: "mic", isBuiltIn: true, outputStreams: 0, inputStreams: 1)

  @Test func theBuiltInSpeakersClockTheAggregate() {
    #expect(MeetingClockDevice.choose(among: [usb, speakers], defaultOutputUID: "usb") == speakers)
  }

  @Test func withoutBuiltInOutputTheDefaultClocksIt() {
    #expect(MeetingClockDevice.choose(among: [usb], defaultOutputUID: "usb") == usb)
  }

  @Test func aBuiltInMicrophoneIsNotAnOutput() {
    #expect(MeetingClockDevice.choose(among: [mic, usb], defaultOutputUID: "usb") == usb)
  }

  @Test func aBuiltInOutputWithInputsIsNotChosen() {
    #expect(MeetingClockDevice.choose(among: [builtInWithInput], defaultOutputUID: "bi") == nil)
    #expect(
      MeetingClockDevice.choose(among: [builtInWithInput, usb], defaultOutputUID: "usb") == usb)
  }

  @Test func aDefaultOutputWithInputsIsNotChosen() {
    #expect(MeetingClockDevice.choose(among: [headset], defaultOutputUID: "headset") == nil)
  }

  @Test func noOutputMeansNoClock() {
    #expect(MeetingClockDevice.choose(among: [], defaultOutputUID: nil) == nil)
    #expect(MeetingClockDevice.choose(among: [mic], defaultOutputUID: "mic") == nil)
    #expect(MeetingClockDevice.choose(among: [usb], defaultOutputUID: "gone") == nil)
  }
}

@Suite struct MeetingTapStreamTests {
  @Test func oneMonoBufferIsTheTap() {
    #expect(MeetingTapStream.index(bufferCount: 1, lastBufferChannels: 1) == 0)
  }

  @Test func anyOtherLayoutRecordsNothing() {
    #expect(MeetingTapStream.index(bufferCount: 1, lastBufferChannels: 2) == nil)
    #expect(MeetingTapStream.index(bufferCount: 2, lastBufferChannels: 1) == nil)
    #expect(MeetingTapStream.index(bufferCount: 0, lastBufferChannels: 0) == nil)
  }
}
