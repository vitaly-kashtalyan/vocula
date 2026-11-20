import Foundation
import VoculaKit
import whisper

public actor WhisperMeetingRecognizer: MeetingRecognizing {
  // nonisolated(unsafe): deinit is nonisolated and cannot read an actor-isolated property.
  private nonisolated(unsafe) var context: OpaquePointer?
  private let queue = DispatchSerialQueue(label: "vocula.meeting.whisper", qos: .utility)

  public nonisolated var unownedExecutor: UnownedSerialExecutor {
    queue.asUnownedSerialExecutor()
  }

  private static var threadCount: Int32 {
    Int32(max(1, (ProcessInfo.processInfo.activeProcessorCount - 2) / 2))
  }

  private static let detectionPrefix = 5 * Int(AudioFormat.sampleRate)

  private init() {}

  deinit {
    if let context { whisper_free(context) }
  }

  public static func load(modelPath: URL) async throws -> WhisperMeetingRecognizer {
    let recognizer = WhisperMeetingRecognizer()
    try await recognizer.open(modelPath)
    return recognizer
  }

  public func recognize(_ samples: [Float], languages: LanguageSelection) async throws
    -> [TimedText]
  {
    try await run(samples, languages: languages, words: true)
  }

  func plainText(_ samples: [Float], languages: LanguageSelection) async throws -> String {
    try await run(samples, languages: languages, words: false).map(\.text).joined()
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func open(_ path: URL) throws {
    var parameters = whisper_context_default_params()
    parameters.use_gpu = true
    context = whisper_init_from_file_with_params(path.path, parameters)
    guard context != nil else { throw TranscriptionError.modelNotLoaded }
  }

  private func run(_ samples: [Float], languages: LanguageSelection, words: Bool) async throws
    -> [TimedText]
  {
    let abort = MeetingAbort()
    return try await withTaskCancellationHandler {
      try decode(samples, languages: languages, words: words, abort: abort)
    } onCancel: {
      abort.cancel()
    }
  }

  private func decode(
    _ samples: [Float], languages: LanguageSelection, words: Bool, abort: MeetingAbort
  ) throws -> [TimedText] {
    guard let context else { throw TranscriptionError.modelNotLoaded }
    guard !samples.isEmpty else { return [] }
    var parameters = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
    parameters.print_realtime = false
    parameters.print_progress = false
    parameters.print_timestamps = false
    parameters.translate = false
    parameters.no_context = true
    parameters.single_segment = false
    parameters.suppress_blank = true
    parameters.suppress_nst = true
    parameters.n_threads = Self.threadCount
    parameters.detect_language = false
    parameters.token_timestamps = words
    parameters.max_len = words ? 1 : 0
    parameters.split_on_word = words
    parameters.abort_callback = { pointer in
      guard let pointer else { return false }
      return Unmanaged<MeetingAbort>.fromOpaque(pointer).takeUnretainedValue().isCancelled
    }
    parameters.abort_callback_user_data = Unmanaged.passUnretained(abort).toOpaque()
    let language = try detectLanguage(context: context, samples: samples, languages: languages)
    let status = language.withCString { pointer -> Int32 in
      parameters.language = pointer
      return withExtendedLifetime(abort) {
        whisper_full(context, parameters, samples, Int32(samples.count))
      }
    }
    if abort.isCancelled { throw CancellationError() }
    guard status == 0 else {
      throw TranscriptionError.engineFailed("whisper_full returned \(status)")
    }
    var out: [TimedText] = []
    for index in 0..<whisper_full_n_segments(context) {
      guard let segment = whisper_full_get_segment_text(context, index) else { continue }
      let text = String(cString: segment)
      let kept = words ? text.trimmingCharacters(in: .whitespacesAndNewlines) : text
      guard !kept.isEmpty else { continue }
      out.append(
        TimedText(
          start: Double(whisper_full_get_segment_t0(context, index)) / 100,
          end: Double(whisper_full_get_segment_t1(context, index)) / 100, text: kept))
    }
    return out
  }

  private func detectLanguage(
    context: OpaquePointer, samples: [Float], languages: LanguageSelection
  ) throws -> String {
    guard languages.needsDetection else {
      return LanguagePolicy.choose(probabilities: [:], selection: languages)
    }
    let prefix = Array(samples.prefix(Self.detectionPrefix))
    guard whisper_pcm_to_mel(context, prefix, Int32(prefix.count), Self.threadCount) == 0 else {
      throw TranscriptionError.engineFailed("whisper_pcm_to_mel failed")
    }
    let count = Int(whisper_lang_max_id()) + 1
    var probabilities = [Float](repeating: 0, count: count)
    guard whisper_lang_auto_detect(context, 0, Self.threadCount, &probabilities) >= 0 else {
      throw TranscriptionError.engineFailed("whisper_lang_auto_detect failed")
    }
    var byCode: [String: Float] = [:]
    for code in languages.codes {
      let id = whisper_lang_id(code)
      byCode[code] = (id >= 0 && Int(id) < count) ? probabilities[Int(id)] : 0
    }
    return LanguagePolicy.choose(probabilities: byCode, selection: languages)
  }
}

private final class MeetingAbort: @unchecked Sendable {
  private let lock = NSLock()
  private var cancelled = false

  var isCancelled: Bool { lock.withLock { cancelled } }

  func cancel() { lock.withLock { cancelled = true } }
}
