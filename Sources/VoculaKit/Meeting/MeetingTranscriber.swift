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
    public var diarization: MeetingDiarization
    public var now: @Sendable () -> UInt64
    public var sleep: @Sendable (Duration) async throws -> Void
    public var publish: @Sendable (MeetingTranscription) async -> Void
    public var log: DiagnosticLog?

    public init(
      store: MeetingStore,
      cipher: @escaping @Sendable () async throws -> any HistoryCipher,
      model: @escaping @Sendable () async -> MeetingModel?,
      makeRecognizer: @escaping @Sendable (MeetingModel) async throws -> any MeetingRecognizing,
      makeDetector: @escaping @Sendable () -> any SpeechDetecting,
      diarization: MeetingDiarization,
      now: @escaping @Sendable () -> UInt64,
      sleep: @escaping @Sendable (Duration) async throws -> Void,
      publish: @escaping @Sendable (MeetingTranscription) async -> Void,
      log: DiagnosticLog?
    ) {
      self.store = store
      self.cipher = cipher
      self.model = model
      self.makeRecognizer = makeRecognizer
      self.makeDetector = makeDetector
      self.diarization = diarization
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
  }

  private struct Carry {
    var samples: [Float] = []
    var start = 0
  }

  private let deps: Dependencies
  private var recognizer: (any MeetingRecognizing)?
  private var detector: (any SpeechDetecting)?
  private var diarizer: (any MeetingDiarizing)?
  private enum Split { case on, waited, unloadable }

  private var split = Split.on
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
    switch outcome {
    case .cancelled:
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
    let recognizing = await waitingForTheDiarizer(pending)
    guard !recognizing.isEmpty else { return }
    total = recognizing.reduce(0) { sum, item in
      let seconds = max(0, item.header.end?.timeIntervalSince(item.header.startedAt) ?? 0)
      return sum + 2 * Int(seconds * AudioFormat.sampleRate)
    }
    await progress()
    guard let chosen = await deps.model() else { throw Stop.pass(step: "model", code: 0) }
    try checkCancelled()
    do { recognizer = try await deps.makeRecognizer(chosen) } catch {
      throw Stop.pass(step: "model", code: Self.code(of: error))
    }
    model = chosen.model
    detector = deps.makeDetector()
    for item in recognizing {
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

  private func waitingForTheDiarizer(_ pending: [MeetingWork]) async -> [MeetingWork] {
    guard !(await deps.diarization.isInstalled()) else { return pending }
    split = .waited
    let now = deps.diarization.wallClock()
    let waited = pending.filter { item in
      item.header.end.map { now.timeIntervalSince($0) >= MeetingDiarizationRules.maxWait } ?? false
    }
    let fresh = pending.count - waited.count
    if fresh > 0 {
      failed(step: "diarizer", code: 0)
      tally.failed += fresh
      remaining -= fresh
    }
    return waited
  }

  private func transcribe(
    _ header: MeetingHeader, model: MeetingModel, cipher: any HistoryCipher
  ) async throws -> MeetingTranscript {
    guard let end = header.endHost else { throw Stop.meeting(step: "open", code: 0) }
    let mic = try await words(
      of: .mic, in: header, end: end, model: model, cipher: cipher, gather: false)
    let refused = await splitRefusal(header)
    let system = try await words(
      of: .system, in: header, end: end, model: model, cipher: cipher,
      gather: split == .on && refused == nil)
    let speakers = try await speakers(of: system.words, in: system.track, refused: refused)
    let built = MeetingTranscriptBuilder.build(
      me: mic.words,
      others: zip(system.words, speakers).map { (word: $0, speaker: $1) },
      dictations: MeetingTranscriptBuilder.dictationRanges(
        header.dictations, anchor: header.anchor))
    tally.echoDropped += built.echoDropped
    return MeetingTranscript(model: model.model.rawValue, utterances: built.utterances)
  }

  private func speakers(of words: [TimedText], in track: [Int16], refused: String?) async throws
    -> [MeetingSpeaker]
  {
    guard !words.isEmpty else { return [] }
    let others = words.map { _ in MeetingSpeaker.others }
    if split == .waited { diarizeFailed(step: "waited", code: 0) }
    if let refused {
      diarizeFailed(step: refused, code: 0)
      return others
    }
    guard split == .on, let diarizer = try await loadedDiarizer() else { return others }
    try checkCancelled()
    let state = deps.diarization.state
    guard await state.begin() else {
      diarizeFailed(step: "busy", code: 0)
      return others
    }
    let work = Self.split(track, with: diarizer, releasing: state)
    let deadline = MeetingDiarizationRules.deadline(
      forTrackSeconds: Double(track.count) / AudioFormat.sampleRate)
    let sleep = deps.sleep
    let finished = await withTaskCancellationHandler {
      await MeetingBound.wait(for: work, atMost: deadline, sleep: sleep)
    } onCancel: {
      work.cancel()
    }
    guard finished else {
      work.cancel()
      try checkCancelled()
      diarizeFailed(step: "deadline", code: 0)
      return others
    }
    switch await work.value {
    case .success(let turns):
      return MeetingSpeakerAssignment.assign(words, turns: turns)
    case .failure(let error):
      try Self.throwIfCancelled(error)
      let fromTheModel = if case MeetingDiarizerError.model = error { true } else { false }
      await failedSplit(step: "diarize", error, discarding: fromTheModel)
      return others
    }
  }

  private func splitRefusal(_ header: MeetingHeader) async -> String? {
    guard split == .on else { return nil }
    let length = header.end?.timeIntervalSince(header.startedAt) ?? 0
    if length > deps.diarization.maxTrackSeconds { return "length" }
    if await deps.diarization.state.isBusy { return "busy" }
    return nil
  }

  private static func split(
    _ track: [Int16], with diarizer: any MeetingDiarizing, releasing state: MeetingDiarizerState
  ) -> Task<Result<[SpeakerTurn], any Error>, Never> {
    Task {
      let result: Result<[SpeakerTurn], any Error>
      do { result = .success(try await diarizer.turns(in: track)) } catch {
        result = .failure(error)
      }
      await state.end()
      return result
    }
  }

  private func loadedDiarizer() async throws -> (any MeetingDiarizing)? {
    if let diarizer { return diarizer }
    do { diarizer = try await deps.diarization.load() } catch {
      try Self.throwIfCancelled(error)
      split = .unloadable
      await failedSplit(step: "load", error, discarding: true)
    }
    return diarizer
  }

  private func failedSplit(step: String, _ error: any Error, discarding: Bool) async {
    let code =
      switch error {
      case MeetingDiarizerError.model(let code), MeetingDiarizerError.failed(let code): code
      default: 0
      }
    diarizeFailed(step: step, code: code)
    guard discarding, await deps.diarization.state.mayDiscard() else { return }
    await deps.diarization.discard()
  }

  private func words(
    of track: MeetingTrack, in header: MeetingHeader, end: UInt64, model: MeetingModel,
    cipher: any HistoryCipher, gather: Bool
  ) async throws -> (words: [TimedText], track: [Int16]) {
    let names: [String]
    do { names = try await deps.store.chunkNames(of: header.id, track: track) } catch {
      throw Self.meetingStop(error)
    }
    var windows = MeetingTrackWindows(anchor: header.anchor, end: end)
    var opened = 0
    var carry = Carry()
    var out: [TimedText] = []
    var gathered: [Int16] = []
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
        if gather { gathered += window.samples }
        out += try await handle(window, isLast: false, carry: &carry, model: model)
      }
    }
    if !names.isEmpty && opened == 0 { throw Stop.meeting(step: "open", code: 0) }
    var next = windows.next(final: true)
    while let window = next {
      next = windows.next(final: true)
      if gather { gathered += window.samples }
      out += try await handle(window, isLast: next == nil, carry: &carry, model: model)
    }
    if !carry.samples.isEmpty {
      out += try await recognize(carry.samples, at: carry.start, model: model)
    }
    return (out, gathered)
  }

  private func handle(
    _ window: MeetingWindow, isLast: Bool, carry: inout Carry, model: MeetingModel
  ) async throws -> [TimedText] {
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

  private func diarizeFailed(step: String, code: Int) {
    deps.log?.record("meeting.diarizeFailed", "step=\(step) code=\(code)")
  }

  private func summarize(took: UInt64) {
    var fields = [
      "meetings=\(tally.transcribed)",
      "audioSeconds=\(read / Int(AudioFormat.sampleRate))",
      "pieces=\(tally.pieces)",
      "utterances=\(tally.utterances)",
      "echoDropped=\(tally.echoDropped)",
      "skippedChunks=\(tally.skipped)",
      "tookSeconds=\(took / 1_000_000_000)",
    ]
    if let model { fields.append("model=\(model.rawValue)") }
    deps.log?.record("meeting.transcribed", fields.joined(separator: " "))
  }

  private static func throwIfCancelled(_ error: any Error) throws {
    if Task.isCancelled || error is CancellationError { throw Stop.cancelled }
  }

  private static func meetingStop(_ error: any Error) -> Stop {
    if Task.isCancelled { return .cancelled }
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
