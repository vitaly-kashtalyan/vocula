import CoreAudio
import Foundation
import Testing
import VoculaKit

@testable import Vocula

@Suite struct SystemAudioTapTests {
  @Test func aSecondCopyCreatesNoTap() async {
    let calls = MeetingCallCounter()
    let tap = SystemAudioTap(outputs: {
      calls.increment()
      return ([], nil)
    })
    await #expect(throws: MeetingFailure.secondCopy) { try await tap.start() }
    #expect(calls.value == 0)
  }

  @Test func aStartAfterStopThrowsAtOnce() async {
    let calls = MeetingCallCounter()
    let tap = SystemAudioTap(outputs: {
      calls.increment()
      return ([], nil)
    })
    tap.stop()
    await #expect(throws: MeetingFailure.failed(step: "abandoned", code: 0)) {
      try await tap.start()
    }
    #expect(calls.value == 0)
  }

  @Test func theAggregateIsNamedSoDictationNeverSeesIt() throws {
    let tapUUID = UUID()
    let composition = try #require(
      SystemAudioTap.composition(
        clockUID: "spk", tapUUID: tapUUID, aggregateUID: MeetingAggregate.uid(UUID())))
    let uid = try #require(composition[kAudioAggregateDeviceUIDKey] as? String)
    let name = try #require(composition[kAudioAggregateDeviceNameKey] as? String)
    #expect(SyntheticInputDevice.isKnownSynthetic(uid: uid, name: name))
    #expect(composition[kAudioAggregateDeviceIsPrivateKey] as? Bool == true)
    #expect(composition[kAudioAggregateDeviceIsStackedKey] as? Bool == false)
    #expect(composition[kAudioAggregateDeviceMainSubDeviceKey] as? String == "spk")
    #expect(composition[kAudioAggregateDeviceTapAutoStartKey] as? Bool == true)
    #expect(
      composition[kAudioAggregateDeviceSubDeviceListKey] as? [[String: String]] == [
        [kAudioSubDeviceUIDKey: "spk"]
      ])
    let taps = try #require(composition[kAudioAggregateDeviceTapListKey] as? [[String: Any]])
    #expect(taps.count == 1)
    #expect(taps.first?[kAudioSubTapUIDKey] as? String == tapUUID.uuidString)
    #expect(taps.first?[kAudioSubTapDriftCompensationKey] as? Bool == true)
  }

  @Test func noClockDeviceMeansNoAggregate() {
    #expect(
      SystemAudioTap.composition(
        clockUID: "", tapUUID: UUID(), aggregateUID: MeetingAggregate.uid(UUID())) == nil)
  }

  @Test func aTapThatNeverStartedDrainsNothing() {
    let tap = SystemAudioTap()
    #expect(tap.drain().runs.isEmpty)
    #expect(tap.callbacks == 0)
  }

  @Test func aStopBeforeAnyStartTearsDownNothing() async {
    let tap = SystemAudioTap()
    tap.stop()
    await tap.finished()
    #expect(tap.callbacks == 0)
  }
}
