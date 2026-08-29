import Foundation
import VoculaKit
import whisper

public actor WhisperVADDetector: SpeechDetecting {
  // nonisolated(unsafe): deinit is nonisolated and cannot read an actor-isolated property.
  private nonisolated(unsafe) var context: OpaquePointer?
  private let modelPath: URL
  private let thresholds: SpeechThresholds

  public init(modelPath: URL, thresholds: SpeechThresholds = .default) {
    self.modelPath = modelPath
    self.thresholds = thresholds
  }

  deinit {
    if let context { whisper_vad_free(context) }
  }

  public func markup(_ samples: [Float]) async throws -> SpeechMarkup {
    try load()
    guard let context else { throw SpeechDetectorError.modelNotLoaded }

    var parameters = whisper_vad_default_params()
    parameters.threshold = thresholds.vadFrameThreshold
    parameters.min_speech_duration_ms = Int32(thresholds.minSegmentDuration.milliseconds)

    guard whisper_vad_detect_speech(context, samples, Int32(samples.count)) else {
      dropContext()
      throw SpeechDetectorError.failed("whisper_vad_detect_speech returned false")
    }
    guard let timestamps = whisper_vad_segments_from_probs(context, parameters) else {
      dropContext()
      throw SpeechDetectorError.failed("no segments returned")
    }
    defer { whisper_vad_free_segments(timestamps) }

    let probabilityCount = Int(whisper_vad_n_probs(context))
    let probabilities: [Float]
    if probabilityCount > 0, let pointer = whisper_vad_probs(context) {
      probabilities = Array(
        UnsafeBufferPointer(
          start: pointer,
          count: probabilityCount))
    } else {
      probabilities = []
    }
    let millisecondsPerFrame = 512.0 / AudioFormat.sampleRate * 1000

    var segments: [SpeechSegment] = []
    for index in 0..<whisper_vad_segments_n_segments(timestamps) {
      let start = Int(whisper_vad_segments_get_segment_t0(timestamps, index) * 10)
      let end = Int(whisper_vad_segments_get_segment_t1(timestamps, index) * 10)
      let first = Int(Double(start) / millisecondsPerFrame)
      let last = min(
        probabilities.count,
        Int(ceil(Double(end) / millisecondsPerFrame)))
      let window = first < last ? probabilities[first..<last] : []
      let mean =
        window.isEmpty
        ? thresholds.minProbability
        : window.reduce(0, +) / Float(window.count)
      segments.append(
        SpeechSegment(
          start: .milliseconds(start),
          end: .milliseconds(end),
          probability: mean))
    }
    return SpeechMarkup(
      segments: segments,
      totalDuration: PCMSamples.duration(sampleCount: samples.count),
      frameProbabilities: probabilities,
      thresholds: thresholds)
  }

  var isLoaded: Bool { context != nil }

  func dropContext() {
    if let context { whisper_vad_free(context) }
    context = nil
  }

  private func load() throws {
    guard context == nil else { return }
    var parameters = whisper_vad_default_context_params()
    // Metal aborts the process on a graph this small, so the VAD stays on the CPU.
    parameters.use_gpu = false
    context = whisper_vad_init_from_file_with_params(modelPath.path, parameters)
    guard context != nil else { throw SpeechDetectorError.modelNotLoaded }
  }
}
