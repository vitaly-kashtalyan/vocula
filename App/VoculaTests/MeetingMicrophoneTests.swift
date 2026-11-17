import AudioToolbox
import CoreAudio
import Foundation
import Testing
import VoculaKit

@testable import Vocula

final class MeetingCallCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0

  func increment() { lock.withLock { count += 1 } }
  var value: Int { lock.withLock { count } }
}

private func fill(_ list: UnsafeMutablePointer<AudioBufferList>, channel: Int, _ values: [Float]) {
  let buffers = UnsafeMutableAudioBufferListPointer(list)
  let samples = buffers[channel].mData!.assumingMemoryBound(to: Float.self)
  samples.update(from: values, count: values.count)
}

@Suite struct MeetingMicrophoneTests {
  @Test func aSecondCopyOpensNothing() async {
    let chosen = MeetingCallCounter()
    let mic = MeetingMicrophone(
      onEnded: {},
      chooseDevice: {
        chosen.increment()
        return kAudioObjectUnknown
      })
    await #expect(throws: MeetingFailure.secondCopy) { try await mic.start() }
    #expect(chosen.value == 0)
    #expect(mic.callbacks == 0)
    #expect(mic.drain().runs.isEmpty)
  }

  @Test func aStartAfterStopThrowsAtOnce() async {
    let chosen = MeetingCallCounter()
    let mic = MeetingMicrophone(
      onEnded: {},
      chooseDevice: {
        chosen.increment()
        return kAudioObjectUnknown
      })
    mic.stop()
    await #expect(throws: MeetingFailure.failed(step: "stopped", code: 0)) {
      try await mic.start()
    }
    #expect(chosen.value == 0)
  }

  @Test func onlyChannelZeroIsKept() throws {
    let capture = try #require(
      MeetingMicrophone.Capture(channels: 2, maximumFrames: 512, rate: 16_000))
    let ramp = (0..<256).map { Float($0) / 1000 }
    let status = capture.deliver(frames: 256, hostNanos: 1_000_000_000) { list in
      fill(list, channel: 0, ramp)
      fill(list, channel: 1, [Float](repeating: 0.9, count: 256))
      return noErr
    }
    #expect(status == noErr)
    let runs = capture.buffer.drain { samples, _ in Array(samples) }.runs
    #expect(runs.map(\.samples) == [ramp.map(MeetingRun.sample)])
  }

  @Test func anOversizedBufferIsRefused() throws {
    let capture = try #require(
      MeetingMicrophone.Capture(channels: 1, maximumFrames: 512, rate: 16_000))
    let status = capture.deliver(frames: 1_024, hostNanos: 1_000_000_000) { _ in noErr }
    #expect(status == kAudio_ParamError)
    #expect(capture.buffer.callbacks == 0)
  }

  @Test func aFailedRenderWritesNothing() throws {
    let capture = try #require(
      MeetingMicrophone.Capture(channels: 1, maximumFrames: 512, rate: 16_000))
    let status = capture.deliver(frames: 256, hostNanos: 1_000_000_000) { _ in -10863 }
    #expect(status == -10863)
    #expect(capture.buffer.callbacks == 0)
  }
}
