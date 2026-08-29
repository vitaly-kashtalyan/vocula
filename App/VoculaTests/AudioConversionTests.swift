import AVFoundation
import Testing
import VoculaKit

@testable import Vocula

@Suite("Audio conversion")
struct AudioConversionTests {
  private let target = AVAudioFormat(
    commonFormat: .pcmFormatFloat32,
    sampleRate: AudioFormat.sampleRate,
    channels: 1, interleaved: false)!

  private func source(_ rate: Double, channels: AVAudioChannelCount) -> AVAudioFormat {
    AVAudioFormat(
      commonFormat: .pcmFormatFloat32, sampleRate: rate,
      channels: channels, interleaved: false)!
  }

  private func tone(
    _ frequency: Double, seconds: Double,
    in format: AVAudioFormat
  ) -> AVAudioPCMBuffer {
    let frames = AVAudioFrameCount(format.sampleRate * seconds)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
    buffer.frameLength = frames
    for channel in 0..<Int(format.channelCount) {
      let samples = buffer.floatChannelData![channel]
      for frame in 0..<Int(frames) {
        samples[frame] = Float(
          sin(
            2 * .pi * frequency
              * Double(frame) / format.sampleRate))
      }
    }
    return buffer
  }

  private func streamed(_ whole: AVAudioPCMBuffer, in format: AVAudioFormat) throws -> [Float] {
    let converter = try #require(AudioRecorder.makeConverter(from: format, to: target))
    var result: [Float] = []
    var offset = AVAudioFrameCount(0)
    while offset < whole.frameLength {
      let size = min(1024, whole.frameLength - offset)
      let chunk = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: size)!
      chunk.frameLength = size
      for channel in 0..<Int(format.channelCount) {
        chunk.floatChannelData![channel]
          .update(
            from: whole.floatChannelData![channel] + Int(offset),
            count: Int(size))
      }
      if let converted = AudioRecorder.convert(chunk, with: converter, to: target) {
        result.append(contentsOf: converted)
      }
      offset += size
    }
    return result
  }

  private func discrete(_ rate: Double, channels: AVAudioChannelCount) throws -> AVAudioFormat {
    let tag = kAudioChannelLayoutTag_DiscreteInOrder | UInt32(channels)
    let layout = try #require(AVAudioChannelLayout(layoutTag: tag))
    return AVAudioFormat(standardFormatWithSampleRate: rate, channelLayout: layout)
  }

  @Test(
    "a discrete multichannel device is captured rather than silently zeroed",
    arguments: [AVAudioChannelCount(4), 16])
  func discreteMultichannelSurvives(channels: AVAudioChannelCount) throws {
    let format = try discrete(48_000, channels: channels)
    let samples = try streamed(tone(1_000, seconds: 1, in: format), in: format)
    #expect(samples.count > 15_000)
    #expect((samples.map { abs($0) }.max() ?? 0) > 0.5)
  }

  private func zeroCrossings(_ samples: [Float]) -> Int {
    zip(samples, samples.dropFirst()).count { ($0 < 0) != ($1 < 0) }
  }

  @Test(
    "one second of any common capture format becomes one second at 16 kHz",
    arguments: [
      (48_000.0, AVAudioChannelCount(2)), (44_100.0, 2),
      (24_000.0, 1), (16_000.0, 1),
    ])
  func oneSecondStaysOneSecond(rate: Double, channels: AVAudioChannelCount) throws {
    let format = source(rate, channels: channels)
    let samples = try streamed(tone(1_000, seconds: 1, in: format), in: format)
    #expect(abs(samples.count - 16_000) <= 16)
  }

  @Test(
    "the tone survives the conversion",
    arguments: [
      (48_000.0, AVAudioChannelCount(2)), (44_100.0, 2),
      (24_000.0, 1), (16_000.0, 1),
    ])
  func pitchIsPreserved(rate: Double, channels: AVAudioChannelCount) throws {
    let format = source(rate, channels: channels)
    let samples = try streamed(tone(1_000, seconds: 1, in: format), in: format)
    #expect(abs(zeroCrossings(samples) - 2_000) <= 5)
  }

  @Test("the converted buffer is not silence")
  func outputCarriesSignal() throws {
    let format = source(48_000, channels: 2)
    let samples = try streamed(tone(440, seconds: 0.5, in: format), in: format)
    #expect(PCMSamples.peak(samples) > 0.5)
  }

  @Test("an empty buffer converts to nothing, not to noise")
  func emptyBufferIsNil() throws {
    let format = source(48_000, channels: 2)
    let converter = try #require(AudioRecorder.makeConverter(from: format, to: target))
    let empty = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
    empty.frameLength = 0
    #expect(AudioRecorder.convert(empty, with: converter, to: target) == nil)
  }
}

@Suite("Conversion from a rendered buffer")
struct RenderedBufferConversionTests {
  private let target = AVAudioFormat(
    commonFormat: .pcmFormatFloat32,
    sampleRate: AudioFormat.sampleRate,
    channels: 1, interleaved: false)!

  private func rendered(
    channels: AVAudioChannelCount,
    frames: AVAudioFrameCount
  ) throws -> AVAudioPCMBuffer {
    let format = try #require(
      CaptureSink.floatFormat(
        rate: 48_000,
        channels: Int(channels)))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096))
    let list = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
    for index in 0..<list.count {
      list[index].mDataByteSize = buffer.frameCapacity * 4
      let samples = list[index].mData!.assumingMemoryBound(to: Float.self)
      for frame in 0..<Int(frames) {
        samples[frame] = Float(sin(2 * .pi * 1_000 * Double(frame) / 48_000))
      }
    }
    buffer.frameLength = frames
    return buffer
  }

  @Test(
    "a buffer filled through the render path converts to real audio",
    arguments: [AVAudioChannelCount(1), 4, 16])
  func renderedBufferConverts(channels: AVAudioChannelCount) throws {
    let buffer = try rendered(channels: channels, frames: 512)
    let converter = try #require(AudioRecorder.makeConverter(from: buffer.format, to: target))
    let samples = try #require(AudioRecorder.convert(buffer, with: converter, to: target))
    #expect(!samples.isEmpty)
    #expect(
      (samples.map { abs($0) }.max() ?? 0) > 0.5,
      "the rendered buffer converted to silence")
  }
}

@Suite("Waveform scroll rate")
struct WaveformScrollRateTests {
  @Test("bar pitch times levels-per-second is still the pace the strip was drawn for")
  func scrollRateHolds() {
    #expect(WaveformGeometry.pitch * CGFloat(CaptureSink.levelsPerSecond) == 19)
  }
}
