import Testing

@testable import VoculaKit

@Suite("Synthetic input device")
struct SyntheticInputDeviceTests {
  @Test("a known auto-generated aggregate uid is synthetic")
  func aggregateUIDIsSynthetic() {
    #expect(
      SyntheticInputDevice.isKnownSynthetic(
        uid: "CADefaultDeviceAggregate-68644-0",
        name: "CADefaultDeviceAggregate-68644-0"))
  }

  @Test("a known auto-generated aggregate name is synthetic even if the uid alone would not match")
  func aggregateNameAloneIsSynthetic() {
    #expect(
      SyntheticInputDevice.isKnownSynthetic(
        uid: "some-other-uid",
        name: "CADefaultDeviceAggregate-1-0"))
  }

  @Test(
    "real devices, including virtual microphones a person installs on purpose, are not synthetic")
  func realDevicesAreNotSynthetic() {
    #expect(
      !SyntheticInputDevice.isKnownSynthetic(
        uid: "BuiltInMicrophoneDevice",
        name: "MacBook Pro Microphone"))
    #expect(
      !SyntheticInputDevice.isKnownSynthetic(
        uid: "52574BF4-0425-44F0-B504-152000000003",
        name: "wunzi Microphone"))
    #expect(
      !SyntheticInputDevice.isKnownSynthetic(
        uid: "com.existential.audio.blackhole2ch",
        name: "BlackHole 2ch"))
  }
}
