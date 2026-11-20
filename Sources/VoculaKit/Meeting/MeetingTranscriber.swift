import Foundation

public protocol MeetingRecognizing: Sendable {
  func recognize(_ samples: [Float], languages: LanguageSelection) async throws -> [TimedText]
}

public struct MeetingModel: Equatable, Sendable {
  public let model: ModelID
  public let languages: LanguageSelection

  public init?(model: ModelID, languages: LanguageSelection) {
    guard ModelManifest.transcriptionModels.contains(model) else { return nil }
    self.model = model
    self.languages = languages
  }

  public var family: ModelFamily { ModelManifest.descriptor(for: model).family }

  public static func choose(
    selected: ModelID, languages: LanguageSelection, isReady: (ModelID) -> Bool
  ) -> MeetingModel? {
    guard isReady(.speechDetector),
      let model = EngineFallback.running(
        selected: selected, languages: languages.codes, isReady: isReady)
    else { return nil }
    return MeetingModel(model: model, languages: languages)
  }
}

public enum MeetingTranscription: Equatable, Sendable {
  case running(percent: Int)
  case finished(transcribed: Int, failed: Int)
}

public actor MeetingTranscriber {
  public struct Dependencies: Sendable {
    public var store: MeetingStore
    public var cipher: @Sendable () async throws -> any HistoryCipher
    public var model: @Sendable () async -> MeetingModel?
    public var makeRecognizer: @Sendable (MeetingModel) async throws -> any MeetingRecognizing
    public var makeDetector: @Sendable () -> any SpeechDetecting
    public var hold: MeetingHoldGate
    public var now: @Sendable () -> UInt64
    public var sleep: @Sendable (Duration) async throws -> Void
    public var publish: @Sendable (MeetingTranscription?) async -> Void
    public var log: DiagnosticLog?

    public init(
      store: MeetingStore,
      cipher: @escaping @Sendable () async throws -> any HistoryCipher,
      model: @escaping @Sendable () async -> MeetingModel?,
      makeRecognizer: @escaping @Sendable (MeetingModel) async throws -> any MeetingRecognizing,
      makeDetector: @escaping @Sendable () -> any SpeechDetecting,
      hold: MeetingHoldGate,
      now: @escaping @Sendable () -> UInt64,
      sleep: @escaping @Sendable (Duration) async throws -> Void,
      publish: @escaping @Sendable (MeetingTranscription?) async -> Void,
      log: DiagnosticLog?
    ) {
      self.store = store
      self.cipher = cipher
      self.model = model
      self.makeRecognizer = makeRecognizer
      self.makeDetector = makeDetector
      self.hold = hold
      self.now = now
      self.sleep = sleep
      self.publish = publish
      self.log = log
    }
  }

  private enum Stop: Error {
    case meeting(step: String, code: Int)
    case pass(step: String, code: Int)
    case cancelled
  }

  private struct Tally {
    var transcribed = 0
    var failed = 0
    var pieces = 0
    var utterances = 0
    var echoDropped = 0
    var skipped = 0
    var paused = Duration.zero
  }

  private struct Carry {
    var samples: [Float] = []
    var start = 0
  }

  private let deps: Dependencies
  private var recognizer: (any MeetingRecognizing)?
  private var detector: (any SpeechDetecting)?
  private var tally = Tally()
  private var remaining = 0
  private var total = 0
  private var read = 0
  private var percent: Int?
  private var model: ModelID?

  public init(_ dependencies: Dependencies) {
    deps = dependencies
  }

  public func run() async {
    let began = deps.now()
    var outcome: Stop?
    do { try await pass() } catch let stop as Stop { outcome = stop } catch {
      outcome = .pass(step: "pass", code: 0)
    }
    if Task.isCancelled { outcome = .cancelled }
    if tally.pieces > 0 || tally.transcribed > 0 {
      summarize(took: HostTime.elapsed(from: began, to: deps.now()))
    }
    if recognizer != nil || detector != nil {
      let hold = deps.hold
      tally.paused += await Task.detached { await hold.waitUntilClear() }.value
      recognizer = nil
      detector = nil
    }
    switch outcome {
    case .cancelled:
      if percent != nil { await deps.publish(nil) }
      return
    case .pass(let step, let code):
      failed(step: step, code: code)
      tally.failed += max(1, remaining)
    case .meeting, nil:
      break
    }
    guard tally.transcribed + tally.failed > 0 else { return }
    await deps.publish(.finished(transcribed: tally.transcribed, failed: tally.failed))
  }

  private func pass() async throws {
    let cipher: any HistoryCipher
    do { cipher = try await deps.cipher() } catch {
      throw Stop.pass(step: "key", code: Self.code(of: error))
    }
    let work: [MeetingWork]
    do { work = try await deps.store.work(cipher: cipher) } catch {
      throw Stop.pass(step: "list", code: Self.code(of: error))
    }
    for item in work where item.kind == .removeAudio { await removeAudio(of: item.header.id) }
    let empty = work.filter { $0.kind == .emptyTranscript }
    let pending = work.filter { $0.kind == .recognize }
    remaining = empty.count + pending.count
    for item in empty {
      try checkCancelled()
      await keep(.empty, of: item.header.id, cipher: cipher)
    }
    guard !pending.isEmpty else { return }
    total = pending.reduce(0) { sum, item in
      let seconds = max(0, item.header.end?.timeIntervalSince(item.header.startedAt) ?? 0)
      return sum + 2 * Int(seconds * AudioFormat.sampleRate)
    }
    await progress()
    guard let chosen = await deps.model() else { throw Stop.pass(step: "model", code: 0) }
    tally.paused += await deps.hold.waitUntilClear()
    try checkCancelled()
    do { recognizer = try await deps.makeRecognizer(chosen) } catch {
      throw Stop.pass(step: "model", code: Self.code(of: error))
    }
    model = chosen.model
    detector = deps.makeDetector()
    for item in pending {
      try checkCancelled()
      do {
        let transcript = try await transcribe(item.header, model: chosen, cipher: cipher)
        try checkCancelled()
        await keep(transcript, of: item.header.id, cipher: cipher)
      } catch Stop.meeting(let step, let code) {
        failed(step: step, code: code)
        tally.failed += 1
        remaining -= 1
      }
    }
  }

  private func transcribe(
    _ header: MeetingHeader, model: MeetingModel, cipher: any HistoryCipher
  ) async throws -> MeetingTranscript {
    guard let end = header.endHost else { throw Stop.meeting(step: "open", code: 0) }
    var heard: [MeetingTrack: [TimedText]] = [:]
    for track in MeetingTrack.allCases {
      heard[track] = try await words(
        of: track, in: header, end: end, model: model, cipher: cipher)
    }
    let built = MeetingTranscriptBuilder.build(
      me: heard[.mic] ?? [], others: heard[.system] ?? [],
      dictations: MeetingTranscriptBuilder.dictationRanges(
        header.dictations, anchor: header.anchor))
    tally.echoDropped += built.echoDropped
    return .recognized(by: model.model, utterances: built.utterances)
  }

  private func words(
    of track: MeetingTrack, in header: MeetingHeader, end: UInt64, model: MeetingModel,
    cipher: any HistoryCipher
  ) async throws -> [TimedText] {
    let names: [String]
    do { names = try await deps.store.chunkNames(of: header.id, track: track) } catch {
      throw Self.meetingStop(error)
    }
    var windows = MeetingTrackWindows(anchor: header.anchor, end: end)
    var opened = 0
    var carry = Carry()
    var out: [TimedText] = []
    for name in names {
      try checkCancelled()
      let chunk: MeetingChunk?
      do {
        chunk = try await deps.store.readChunk(
          of: header.id, track: track, name: name, cipher: cipher)
      } catch {
        throw Self.meetingStop(error)
      }
      if let chunk {
        opened += 1
        do { try windows.add(chunk) } catch { throw Stop.meeting(step: "open", code: 0) }
      } else {
        tally.skipped += 1
      }
      while let window = windows.next(final: false) {
        out += try await handle(window, isLast: false, carry: &carry, model: model)
      }
    }
    if !names.isEmpty && opened == 0 { throw Stop.meeting(step: "open", code: 0) }
    var next = windows.next(final: true)
    while let window = next {
      next = windows.next(final: true)
      out += try await handle(window, isLast: next == nil, carry: &carry, model: model)
    }
    if !carry.samples.isEmpty {
      out += try await recognize(carry.samples, at: carry.start, model: model)
    }
    return out
  }

  private func handle(
    _ window: MeetingWindow, isLast: Bool, carry: inout Carry, model: MeetingModel
  ) async throws -> [TimedText] {
    tally.paused += await deps.hold.waitUntilClear()
    try checkCancelled()
    guard let detector else { throw Stop.pass(step: "vad", code: 0) }
    let buffer = MeetingPieces.buffer(carry: carry.samples, window: window.samples)
    let start = carry.samples.isEmpty ? window.start : carry.start
    let markup: SpeechMarkup
    do { markup = try await detector.markup(buffer) } catch SpeechDetectorError.modelNotLoaded {
      throw Stop.pass(step: "vad", code: 0)
    } catch {
      if Task.isCancelled { throw Stop.cancelled }
      throw Stop.meeting(step: "vad", code: 0)
    }
    let plan = MeetingPieces.plan(segments: markup.segments, count: buffer.count, isLast: isLast)
    var out: [TimedText] = []
    for piece in plan.pieces {
      out += try await recognize(Array(buffer[piece]), at: start + piece.lowerBound, model: model)
    }
    carry =
      plan.carryFrom.map { Carry(samples: Array(buffer[$0...]), start: start + $0) } ?? Carry()
    read += window.samples.count
    await progress()
    return out
  }

  private func recognize(_ samples: [Float], at offset: Int, model: MeetingModel) async throws
    -> [TimedText]
  {
    tally.paused += await deps.hold.waitUntilClear()
    try checkCancelled()
    guard let recognizer else { throw Stop.pass(step: "model", code: 0) }
    let padded = MeetingPieces.padded(samples)
    let deadline = Timings.default.passDeadline(
      forAudio: PCMSamples.duration(sampleCount: samples.count))
    let sleep = deps.sleep
    let languages = model.languages
    let words: [TimedText]?
    do {
      words = try await withThrowingTaskGroup(of: [TimedText]?.self) { group in
        group.addTask { try await recognizer.recognize(padded, languages: languages) }
        group.addTask {
          try await sleep(deadline)
          return nil
        }
        defer { group.cancelAll() }
        return try await group.next() ?? nil
      }
    } catch {
      if Task.isCancelled { throw Stop.cancelled }
      throw Stop.meeting(step: "recognize", code: Self.code(of: error))
    }
    guard let words else { throw Stop.meeting(step: "recognize", code: 0) }
    tally.pieces += 1
    let shift = Double(offset) / AudioFormat.sampleRate
    return words.map { TimedText(start: $0.start + shift, end: $0.end + shift, text: $0.text) }
  }

  private func keep(_ transcript: MeetingTranscript, of meeting: UUID, cipher: any HistoryCipher)
    async
  {
    remaining -= 1
    do {
      try await deps.store.writeTranscript(transcript, of: meeting, cipher: cipher)
    } catch {
      let stop = Self.meetingStop(error)
      if case .meeting(let step, let code) = stop { failed(step: step, code: code) }
      tally.failed += 1
      return
    }
    tally.transcribed += 1
    tally.utterances += transcript.utterances.count
    guard !Task.isCancelled else { return }
    await removeAudio(of: meeting)
  }

  private func removeAudio(of meeting: UUID) async {
    do { try await deps.store.removeAudio(of: meeting) } catch {
      if case .meeting(let step, let code) = Self.meetingStop(error) {
        failed(step: step, code: code)
      }
    }
  }

  private func progress() async {
    let value = total > 0 ? min(100, read * 100 / total) : 0
    guard value != percent else { return }
    percent = value
    await deps.publish(.running(percent: value))
  }

  private func checkCancelled() throws {
    if Task.isCancelled { throw Stop.cancelled }
  }

  private func failed(step: String, code: Int) {
    deps.log?.record("meeting.transcribeFailed", "step=\(step) code=\(code)")
  }

  private func summarize(took: UInt64) {
    var fields = [
      "meetings=\(tally.transcribed)",
      "audioSeconds=\(read / Int(AudioFormat.sampleRate))",
      "pieces=\(tally.pieces)",
      "utterances=\(tally.utterances)",
      "echoDropped=\(tally.echoDropped)",
      "skippedChunks=\(tally.skipped)",
      "pausedSeconds=\(tally.paused.components.seconds)",
      "tookSeconds=\(took / 1_000_000_000)",
    ]
    if let model { fields.append("model=\(model.rawValue)") }
    deps.log?.record("meeting.transcribed", fields.joined(separator: " "))
  }

  private static func meetingStop(_ error: any Error) -> Stop {
    if case MeetingStoreError.failed(let step, let code) = error {
      return .meeting(step: step, code: code)
    }
    return .meeting(step: "read", code: 0)
  }

  private static func code(of error: any Error) -> Int {
    switch error {
    case MeetingStoreError.failed(_, let code): code
    case MeetingFailure.failed(_, let code): Int(code)
    default: 0
    }
  }
}
