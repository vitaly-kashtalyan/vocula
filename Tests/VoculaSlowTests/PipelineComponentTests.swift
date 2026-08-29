import Foundation
import Testing
import VoculaKit

@testable import VoculaWhisper

private let modelDirectory = FileManager.default
  .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
  .appendingPathComponent("app.vocula.mac/Models")
private let detectorModel = modelDirectory.appendingPathComponent("ggml-silero-v5.1.2.bin")
private let transcriptionModel = modelDirectory.appendingPathComponent("ggml-large-v3-turbo.bin")
private let fixtureDirectory = URL(fileURLWithPath: "Tests/VoculaSlowTests/Fixtures")

private let modelsReady =
  FileManager.default.fileExists(atPath: detectorModel.path)
  && FileManager.default.fileExists(atPath: transcriptionModel.path)
  && ["es-phrase.f32", "en-phrase.f32"].allSatisfy {
    FileManager.default.fileExists(atPath: fixtureDirectory.appendingPathComponent($0).path)
  }

private final class CountingEngine: Transcribing, @unchecked Sendable {
  private let engine = WhisperEngine(modelPath: transcriptionModel)
  private let lock = NSLock()
  private var count = 0
  var passes: Int { lock.withLock { count } }

  func transcribe(
    _ samples: [Float], languages: LanguageSelection,
    deadline: Duration
  ) async throws -> Transcription {
    lock.withLock { count += 1 }
    return try await engine.transcribe(samples, languages: languages, deadline: deadline)
  }
}

private func fixture(_ name: String) throws -> [Float] {
  let data = try Data(contentsOf: fixtureDirectory.appendingPathComponent(name))
  guard data.count.isMultiple(of: MemoryLayout<Float>.stride) else {
    throw CocoaError(.fileReadCorruptFile)
  }
  var samples = [Float](repeating: 0, count: data.count / MemoryLayout<Float>.stride)
  _ = samples.withUnsafeMutableBytes { data.copyBytes(to: $0) }
  return samples
}

private struct SeededNoise {
  private var state: UInt64 = 0x9E37_79B9_7F4A_7C15
  mutating func nextUnit() -> Float {
    state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    return Float(Int32(truncatingIfNeeded: state >> 32)) / Float(Int32.max)
  }
}

private func roomFloor(count: Int, peak: Float) -> [Float] {
  var noise = SeededNoise()
  return (0..<count).map { _ in noise.nextUnit() * peak }
}

private func speechShapedNoise(_ voiced: [Float], peak: Float) -> [Float] {
  var noise = SeededNoise()
  let modulated = voiced.map { $0 * noise.nextUnit() }
  let current = PCMSamples.peak(modulated)
  guard current > 0 else { return modulated }
  let gain = peak / current
  return modulated.map { $0 * gain }
}

private func levinson(_ r: [Double], order: Int) -> (a: [Double], error: Double) {
  var a = [Double](repeating: 0, count: order + 1)
  var error = r[0]
  guard error > 0 else { return (a, 0) }
  for i in 1...order {
    var acc = r[i]
    for j in 1..<i { acc -= a[j] * r[i - j] }
    let k = acc / error
    var updated = a
    updated[i] = k
    for j in 1..<i { updated[j] = a[j] - k * a[i - j] }
    a = updated
    error *= (1 - k * k)
    if error <= 0 { break }
  }
  return (a, max(error, 0))
}

private func unvoiced(
  _ voiced: [Float], order: Int = 20,
  frame: Int = 1024, hop: Int = 512
) -> [Float] {
  guard voiced.count > frame else { return voiced }
  var noise = SeededNoise()
  var out = [Float](repeating: 0, count: voiced.count)
  var history = [Double](repeating: 0, count: order)

  var position = 0
  while position + frame <= voiced.count {
    var windowed = [Double](repeating: 0, count: frame)
    for n in 0..<frame {
      let w = 0.5 - 0.5 * cos(2 * Double.pi * Double(n) / Double(frame - 1))
      windowed[n] = Double(voiced[position + n]) * w
    }
    var r = [Double](repeating: 0, count: order + 1)
    for lag in 0...order {
      var acc = 0.0
      for n in lag..<frame { acc += windowed[n] * windowed[n - lag] }
      r[lag] = acc
    }
    let (a, residual) = levinson(r, order: order)
    let gain = (residual / Double(frame)).squareRoot()

    for n in 0..<hop where position + n < out.count {
      var value = Double(noise.nextUnit()) * gain
      for k in 1...order { value += a[k] * history[k - 1] }
      if !value.isFinite { value = 0 }
      value = max(-4, min(4, value))
      history.removeLast()
      history.insert(value, at: 0)
      out[position + n] = Float(value)
    }
    position += hop
  }
  return out
}

private func scaled(_ samples: [Float], toPeak peak: Float) -> [Float] {
  let current = PCMSamples.peak(samples)
  guard current > 0 else { return samples }
  let gain = peak / current
  return samples.map { $0 * gain }
}

private actor FixtureMicrophone: AudioRecording {
  private let samples: [Float]
  private(set) var isRunning = false
  private let levels = StreamFanout<Float>()
  private let devices = StreamFanout<Void>()

  init(_ samples: [Float]) { self.samples = samples }

  nonisolated func levelUpdates() -> AsyncStream<Float> { levels.subscribe() }
  nonisolated func deviceChangeEvents() -> AsyncStream<Void> { devices.subscribe() }
  func start() async throws { isRunning = true }
  func stop() async -> [Float] {
    isRunning = false
    return samples
  }
  func discard() async { isRunning = false }
}

private struct AllowingProbe: TargetProbing {
  private let snapshotValue = TargetSnapshot(pid: 501, secureInputWasUp: false)
  func snapshot(budget: Duration) async -> (TargetSnapshot, FocusedSubrole) {
    (snapshotValue, .other("AXTextArea"))
  }
  func compare(_ snapshot: TargetSnapshot, budget: Duration) async -> TargetComparison {
    TargetComparison(
      pid: 501, sameWindow: true, sameElement: true,
      subrole: .other("AXTextArea"), secureInputIsUp: false)
  }
  func release(_ snapshot: TargetSnapshot) async {}
}

private final class RecordingClipboard: Clipboard, @unchecked Sendable {
  private let lock = NSLock()
  private var count = 1
  private var written: [String] = []
  var changeCount: Int { lock.withLock { count } }
  var writes: [String] { lock.withLock { written } }

  func snapshot() -> ClipboardSnapshot {
    ClipboardSnapshot(items: [], changeCount: changeCount)
  }
  func write(_ text: String, concealed: Bool, transient: Bool) -> ClipboardWriteOutcome {
    lock.withLock {
      written.append(text)
      count += 1
      return .written(changeCount: count)
    }
  }
  @discardableResult func restore(_ snapshot: ClipboardSnapshot) -> Int? {
    lock.withLock {
      count += 1
      return count
    }
  }
}

private struct SucceedingPaste: PasteSending {
  func sendPaste() -> Bool { true }
}

private actor OutcomeLog: SessionRecording {
  var states: [(SessionState, String?)] = []
  var metrics: SpeechMetrics?
  var rawText: String?
  var finalText: String?

  func createDraft(
    session: Int, startedAt: Date, durationMilliseconds: Int,
    targetBundleID: String?, modelID: String?
  ) async -> UUID? { UUID() }
  func markTruncated(_ id: UUID) async {}
  func attachMetrics(_ id: UUID, _ value: SpeechMetrics) async { metrics = value }
  func attachRawText(_ id: UUID, _ text: String, language: String) async { rawText = text }
  func attachFinalText(_ id: UUID, _ text: String) async { finalText = text }
  func setState(_ id: UUID, _ state: SessionState, reason: String?) async {
    states.append((state, reason))
  }

  var terminal: (SessionState, String?)? {
    states.last { [.sent, .rejected, .failed, .noSpeech].contains($0.0) }
  }
}

private let spanishOnly = LanguageSelection.pinned("es")

private struct Run {
  let outcome: SessionState
  let reason: String?
  let inserted: [String]
  let passes: Int
  let metrics: SpeechMetrics?
  let rawText: String?
}

private func dictate(
  _ capture: [Float],
  languages: LanguageSelection = .default
) async -> Run {
  let clipboard = RecordingClipboard()
  let engine = CountingEngine()
  let log = OutcomeLog()
  let controller = DictationController(
    dependencies: .init(
      audio: FixtureMicrophone(capture),
      detector: WhisperVADDetector(modelPath: detectorModel),
      engine: engine,
      probe: AllowingProbe(),
      inserter: TextInserter(
        clipboard: clipboard, paste: SucceedingPaste(),
        timings: .default, sleep: { _ in }),
      filter: TextFilter(),
      history: log,
      modelID: "largeV3Turbo",
      timings: .default,
      languages: { languages }))

  await controller.handle(.start(session: 1))
  await controller.handle(.stop(session: 1, reason: .releasedHold))
  await controller.drain()

  let terminal = await log.terminal
  return Run(
    outcome: terminal?.0 ?? .recorded, reason: terminal?.1,
    inserted: clipboard.writes, passes: engine.passes,
    metrics: await log.metrics, rawText: await log.rawText)
}

@Suite("Pipeline on the real models", .serialized, .enabled(if: modelsReady))
struct PipelineComponentTests {
  @Test("a spoken phrase reaches the clipboard as text")
  func voicedPhraseIsInserted() async throws {
    let run = await dictate(try fixture("es-phrase.f32"), languages: spanishOnly)
    #expect(run.outcome == .sent)
    #expect(run.passes == 1)
    #expect(run.inserted.count == 1)
    #expect(run.inserted.first?.lowercased().contains("hola") == true)
  }

  @Test("the English fixture is inserted too, with the language detected")
  func englishPhraseIsInserted() async throws {
    let run = await dictate(try fixture("en-phrase.f32"))
    #expect(run.outcome == .sent)
    #expect(run.inserted.first?.lowercased().contains("hello") == true)
  }

  @Test("a capture 300x too quiet produces the same text as the loud one")
  func quietCaptureIsLevelInvariant() async throws {
    let phrase = try fixture("es-phrase.f32")
    let loud = await dictate(phrase, languages: spanishOnly)
    let quiet = await dictate(phrase.map { $0 * 0.003 }, languages: spanishOnly)
    #expect(quiet.outcome == .sent)
    #expect(quiet.inserted == loud.inserted)
  }

  @Test("the stored peak is the microphone's, not the boosted buffer's")
  func storedPeakIsTheMicrophones() async throws {
    let quiet = try fixture("es-phrase.f32").map { $0 * 0.003 }
    let run = await dictate(quiet, languages: spanishOnly)
    let peak = try #require(run.metrics?.peakLevel)
    #expect(abs(peak - PCMSamples.peak(quiet)) < 1e-6)
    #expect(peak < 0.05)
  }

  @Test("a buffer of pure zeros is silentInput, and never reaches whisper")
  func deadInputIsDiagnosed() async {
    let run = await dictate([Float](repeating: 0, count: 32_000))
    #expect(run.outcome == .failed)
    #expect(run.reason == SessionFailure.silentInput.rawValue)
    #expect(run.passes == 0)
  }

  @Test("a live microphone in a silent room is noSpeech, and never reaches whisper")
  func roomFloorNeverReachesWhisper() async {
    let run = await dictate(roomFloor(count: 32_000, peak: 0.001))
    #expect(run.outcome == .noSpeech)
    #expect(run.passes == 0)
    #expect(run.inserted.isEmpty)
    #expect(run.rawText == nil)
  }

  @Test("an empty capture is noSpeech, not a dead input")
  func emptyCaptureIsNoSpeech() async {
    let run = await dictate([])
    #expect(run.outcome == .noSpeech)
    #expect(run.reason == nil)
    #expect(run.passes == 0)
  }

  @Test(
    "unvoiced speech is recognised and inserted",
    arguments: [Float(0.4), 0.02, 0.003])
  func unvoicedSpeechIsInserted(peak: Float) async throws {
    let run = await dictate(
      scaled(unvoiced(try fixture("es-phrase.f32")), toPeak: peak),
      languages: spanishOnly)
    #expect(run.outcome == .sent)
    #expect(run.inserted.first?.lowercased().contains("prueba") == true)
  }

  @Test(
    "speech-shaped noise stays below the salvage floor",
    arguments: [Float(0.58), 0.02, 0.003])
  func speechShapedNoiseStaysBelowTheSalvageFloor(peak: Float) async throws {
    let run = await dictate(speechShapedNoise(try fixture("es-phrase.f32"), peak: peak))
    #expect(run.outcome == .noSpeech)
    #expect(run.passes == 0)
    let maxFrame = try #require(run.metrics?.maxFrameProbability)
    #expect(maxFrame < SpeechThresholds.default.minSalvageFrameProbability)
  }
}
