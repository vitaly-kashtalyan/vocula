import Foundation
import VoculaKit
import whisper

public actor WhisperEngine: Transcribing {
  // nonisolated(unsafe): deinit is nonisolated and cannot read an actor-isolated property.
  private nonisolated(unsafe) var context: OpaquePointer?
  private let modelPath: URL

  private static let warmUpDeadline: Duration = .seconds(60)

  private static var workerThreadCount: Int32 {
    Int32(max(1, ProcessInfo.processInfo.activeProcessorCount - 2))
  }

  public init(modelPath: URL) { self.modelPath = modelPath }

  deinit {
    if let context { whisper_free(context) }
  }

  public func warmUp() async {
    _ = try? await transcribe(
      [Float](repeating: 0, count: Int(AudioFormat.sampleRate)),
      languages: .pinned(LanguageSelection.fallbackCode),
      deadline: Self.warmUpDeadline)
  }

  public func transcribe(
    _ samples: [Float], languages: LanguageSelection,
    deadline: Duration
  ) async throws -> Transcription {
    try load()
    guard let context else { throw TranscriptionError.modelNotLoaded }
    guard !samples.isEmpty else {
      return Transcription(text: "", language: languages.codes[0])
    }

    let expiry = ContinuousClock.now + deadline
    let abortBox = AbortBox(expiry: expiry)

    var parameters = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
    parameters.print_realtime = false
    parameters.print_progress = false
    parameters.print_timestamps = false
    parameters.translate = false
    parameters.no_context = true
    parameters.single_segment = false
    parameters.suppress_blank = true
    parameters.n_threads = Self.workerThreadCount
    parameters.detect_language = false
    parameters.abort_callback = { pointer in
      guard let pointer else { return false }
      return Unmanaged<AbortBox>.fromOpaque(pointer)
        .takeUnretainedValue().shouldAbort()
    }

    let (requested, scores) = try detectLanguage(
      context: context, samples: samples,
      languages: languages)
    parameters.abort_callback_user_data = Unmanaged.passUnretained(abortBox).toOpaque()
    let status = requested.withCString { languagePointer -> Int32 in
      parameters.language = languagePointer
      return withExtendedLifetime(abortBox) {
        whisper_full(context, parameters, samples, Int32(samples.count))
      }
    }
    if abortBox.didAbort { throw TranscriptionError.timedOut }
    guard status == 0 else {
      dropContext()
      throw TranscriptionError.engineFailed("whisper_full returned \(status)")
    }

    var text = ""
    for index in 0..<whisper_full_n_segments(context) {
      guard let segment = whisper_full_get_segment_text(context, index) else { continue }
      text += String(cString: segment)
    }
    return Transcription(
      text: text.trimmingCharacters(in: .whitespacesAndNewlines),
      language: requested,
      firstTokenProbability: Self.firstTextTokenProbability(context),
      languageScores: scores)
  }

  private static func firstTextTokenProbability(_ context: OpaquePointer) -> Float? {
    let firstSpecial = whisper_token_eot(context)
    for segment in 0..<whisper_full_n_segments(context) {
      for token in 0..<whisper_full_n_tokens(context, segment)
      where whisper_full_get_token_id(context, segment, token) < firstSpecial {
        return whisper_full_get_token_data(context, segment, token).p
      }
    }
    return nil
  }

  private static let detectionPrefix = 5 * Int(AudioFormat.sampleRate)

  private func detectLanguage(
    context: OpaquePointer, samples: [Float],
    languages: LanguageSelection
  ) throws -> (String, [String: Float]) {
    guard languages.needsDetection else {
      return (LanguagePolicy.choose(probabilities: [:], selection: languages), [:])
    }
    let prefix = Array(samples.prefix(Self.detectionPrefix))
    let threads = Self.workerThreadCount
    guard whisper_pcm_to_mel(context, prefix, Int32(prefix.count), threads) == 0 else {
      throw TranscriptionError.engineFailed("whisper_pcm_to_mel failed")
    }
    let count = Int(whisper_lang_max_id()) + 1
    var probabilities = [Float](repeating: 0, count: count)
    let detected = whisper_lang_auto_detect(context, 0, threads, &probabilities)
    guard detected >= 0 else {
      throw TranscriptionError.engineFailed("whisper_lang_auto_detect failed")
    }
    var byCode: [String: Float] = [:]
    for code in languages.codes {
      let id = whisper_lang_id(code)
      // Zero, never absent: a code whisper does not know would otherwise drop
      // out of the count and the sum, and `langs` would not mean what it says.
      byCode[code] = (id >= 0 && Int(id) < count) ? probabilities[Int(id)] : 0
    }
    return (LanguagePolicy.choose(probabilities: byCode, selection: languages), byCode)
  }

  var isLoaded: Bool { context != nil }

  func dropContext() {
    if let context { whisper_free(context) }
    context = nil
  }

  private func load() throws {
    guard context == nil else { return }
    var parameters = whisper_context_default_params()
    parameters.use_gpu = true
    context = whisper_init_from_file_with_params(modelPath.path, parameters)
    guard context != nil else { throw TranscriptionError.modelNotLoaded }
  }
}

private final class AbortBox: @unchecked Sendable {
  let expiry: ContinuousClock.Instant
  private let lock = NSLock()
  private var didAbortStorage = false

  init(expiry: ContinuousClock.Instant) { self.expiry = expiry }

  var didAbort: Bool {
    lock.lock()
    defer { lock.unlock() }
    return didAbortStorage
  }

  func shouldAbort() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    if ContinuousClock.now >= expiry { didAbortStorage = true }
    return didAbortStorage
  }
}
