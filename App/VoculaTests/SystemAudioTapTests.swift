import CoreAudio
import Foundation
import Testing
import VoculaKit

@testable import Vocula

private func pcm(rate: Double, channels: UInt32 = 1, float: Bool = true, bits: UInt32 = 32)
  -> AudioStreamBasicDescription
{
  let flags = float ? kAudioFormatFlagIsFloat : kAudioFormatFlagIsSignedInteger
  return AudioStreamBasicDescription(
    mSampleRate: rate, mFormatID: kAudioFormatLinearPCM,
    mFormatFlags: flags | kAudioFormatFlagIsPacked, mBytesPerPacket: bits / 8 * channels,
    mFramesPerPacket: 1, mBytesPerFrame: bits / 8 * channels, mChannelsPerFrame: channels,
    mBitsPerChannel: bits, mReserved: 0)
}

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
    #expect(composition[kAudioAggregateDeviceTapAutoStartKey] == nil)
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

  @Test func theRateIsTheSingleInputStreamsVirtualFormat() {
    var asked: [AudioStreamID] = []
    let rate = SystemAudioTap.captureRate(
      inputStreams: [42],
      format: { stream in
        asked.append(stream)
        return pcm(rate: 24_000)
      })
    #expect(rate == 24_000)
    #expect(asked == [42])
  }

  @Test func anythingButOneMonoFloatStreamGivesNoRate() {
    let mono = pcm(rate: 48_000)
    #expect(SystemAudioTap.captureRate(inputStreams: [], format: { _ in mono }) == nil)
    #expect(SystemAudioTap.captureRate(inputStreams: [1, 2], format: { _ in mono }) == nil)
    #expect(SystemAudioTap.captureRate(inputStreams: [1], format: { _ in nil }) == nil)
    #expect(
      SystemAudioTap.captureRate(
        inputStreams: [1], format: { _ in pcm(rate: 48_000, channels: 2) }) == nil)
    #expect(
      SystemAudioTap.captureRate(
        inputStreams: [1], format: { _ in pcm(rate: 48_000, float: false, bits: 16) }) == nil)
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
