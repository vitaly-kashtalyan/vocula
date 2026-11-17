import AVFoundation
import VoculaKit

final class MeetingResampler: @unchecked Sendable {
  private let target: AVAudioFormat?
  private let converters: ConverterCache?

  init() {
    target = AVAudioFormat(
      commonFormat: .pcmFormatFloat32, sampleRate: AudioFormat.sampleRate, channels: 1,
      interleaved: false)
    converters = target.map(ConverterCache.init(target:))
  }

  func drain(_ buffer: TrackBuffer) -> TrackDrain {
    buffer.drain { samples, rate in self.resample(samples, rate: rate) }
  }

  private func resample(_ samples: UnsafeBufferPointer<Float>, rate: Double) -> [Float]? {
    guard let target, let base = samples.baseAddress,
      let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false),
      let wrapped = AVAudioPCMBuffer(
        pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
      let channel = wrapped.floatChannelData?[0],
      let converter = converters?.converter(for: format)
    else { return nil }
    channel.update(from: base, count: samples.count)
    wrapped.frameLength = AVAudioFrameCount(samples.count)
    return AudioRecorder.convert(wrapped, with: converter, to: target)
  }
}
