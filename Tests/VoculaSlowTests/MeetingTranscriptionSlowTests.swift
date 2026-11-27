import Foundation
import Testing
import VoculaKit

@testable import VoculaParakeet
@testable import VoculaWhisper

private let models = FileManager.default.homeDirectoryForCurrentUser
  .appendingPathComponent("Library/Application Support/app.vocula.mac/Models")
private let whisperModel = models.appendingPathComponent("ggml-large-v3-turbo.bin")
private let detectorModel = models.appendingPathComponent("ggml-silero-v5.1.2.bin")
private let parakeetModel = models.appendingPathComponent("parakeet-ultra-95eaa59")
private let diarizerModel =
  ProcessInfo.processInfo.environment["VOCULA_DIARIZER_MODEL"].map(URL.init(fileURLWithPath:))
  ?? models.appendingPathComponent("speaker-diarizer-df2625a")

private func fixture(_ name: String) throws -> [Float] {
  let url = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures/\(name).f32")
  let data = try Data(contentsOf: url)
  return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
}

private func samples(_ count: Int) -> [Float] {
  (0..<count).map { i in Float(sin(Double(i) * 0.05)) * 0.05 }
}

private func ready(_ urls: URL...) -> Bool {
  urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) }
}

@Suite(
  "A recorded meeting becomes Me and Others",
  .enabled(if: ready(whisperModel, detectorModel, parakeetModel)))
struct MeetingTranscriptionSlowTests {
  private let s: UInt64 = 1_000_000_000

  private func plantMeeting(in store: MeetingStore) async throws -> MeetingHeader {
    let cipher = PassthroughCipher()
    var header = MeetingHeader(id: UUID(), startedAt: Date(), anchor: s)
    _ = try await store.begin(header, cipher: cipher, recovering: false)
    let mic = try fixture("en-phrase").map(MeetingRun.sample)
    let system = try fixture("ru-phrase").map(MeetingRun.sample)
    try await store.write(
      MeetingChunk(track: .mic, sequence: 0, runs: [MeetingRun(start: 2 * s, samples: mic)]),
      of: header.id, cipher: cipher)
    try await store.write(
      MeetingChunk(
        track: .system, sequence: 0, runs: [MeetingRun(start: 7 * s, samples: system)]),
      of: header.id, cipher: cipher)
    header.finish(atHost: 10 * s, by: .stopped)
    try await store.update(header, cipher: cipher)
    return header
  }

  private func transcribe(
    with recognizer: @escaping @Sendable () async throws -> any MeetingRecognizing
  ) async throws -> MeetingTranscript {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("vocula-meeting-slow-\(UUID().uuidString)")
    let store = MeetingStore(directory: root)
    let header = try await plantMeeting(in: store)
    let languages = LanguageSelection(codes: ["en", "ru"], autoDetect: true)
    let transcriber = MeetingTranscriber(
      MeetingTranscriber.Dependencies(
        store: store,
        cipher: { PassthroughCipher() },
        model: { MeetingModel(model: .largeV3Turbo, languages: languages) },
        makeRecognizer: { _ in try await recognizer() },
        makeDetector: { WhisperVADDetector(modelPath: detectorModel) },
        diarization: MeetingDiarization(
          state: MeetingDiarizerState(), isInstalled: { true }, load: { NoTurns() },
          discard: {}, wallClock: { Date() }),
        now: { DispatchTime.now().uptimeNanoseconds },
        sleep: { try await Task.sleep(for: $0) },
        publish: { _ in },
        log: nil))
    await transcriber.run()
    #expect(
      !FileManager.default.fileExists(
        atPath: root.appendingPathComponent("\(header.id.uuidString)/audio").path))
    return try await store.transcript(of: header.id, cipher: PassthroughCipher())
  }

  @Test func whisperTurnsItIntoMeThenOthers() async throws {
    let transcript = try await transcribe {
      try await WhisperMeetingRecognizer.load(modelPath: whisperModel)
    }
    #expect(transcript.utterances.map(\.speaker) == [.me, .others])
    #expect(transcript.utterances.allSatisfy { !$0.text.isEmpty })
    #expect(transcript.utterances.first.map { $0.start >= 1 && $0.start < 3 } == true)
    #expect(transcript.utterances.last.map { $0.start >= 5.9 && $0.start < 8 } == true)
    #expect(transcript.utterances.first.map { latin($0.text) } == true)
    #expect(transcript.utterances.last.map { cyrillic($0.text) } == true)
  }

  private func latin(_ text: String) -> Bool {
    text.unicodeScalars.contains { ("a"..."z").contains($0) || ("A"..."Z").contains($0) }
  }

  private func cyrillic(_ text: String) -> Bool {
    text.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) }
  }

  @Test func parakeetTurnsItIntoMeThenOthers() async throws {
    let transcript = try await transcribe {
      try await ParakeetMeetingRecognizer.load(modelDirectory: parakeetModel)
    }
    #expect(transcript.utterances.map(\.speaker) == [.me, .others])
    #expect(transcript.utterances.allSatisfy { !$0.text.isEmpty })
    #expect(transcript.utterances.first.map { latin($0.text) } == true)
    #expect(transcript.utterances.last.map { cyrillic($0.text) } == true)
  }
}

@Suite(
  "Meeting recognisers beside dictation's engines",
  .enabled(if: ready(whisperModel, detectorModel, parakeetModel)))
struct MeetingBesideDictationTests {
  @Test func meetingWhisperBesideDictationWhisper() async throws {
    let audio = samples(16_000 * 3)
    let languages = LanguageSelection.pinned("ru")
    let engine = WhisperEngine(modelPath: whisperModel)
    let meeting = try await WhisperMeetingRecognizer.load(modelPath: whisperModel)
    for _ in 1...4 {
      async let piece: Void = { _ = try? await meeting.recognize(audio, languages: languages) }()
      async let dictation: Void = {
        _ = try? await engine.transcribe(audio, languages: languages, deadline: .seconds(30))
      }()
      _ = await (piece, dictation)

      async let loadAndFree: Void = {
        let doomed = try? await WhisperMeetingRecognizer.load(modelPath: whisperModel)
        _ = try? await doomed?.recognize(audio, languages: languages)
      }()
      async let during: Void = {
        _ = try? await engine.transcribe(audio, languages: languages, deadline: .seconds(30))
      }()
      _ = await (loadAndFree, during)

      async let restart: Void = {
        let fresh = WhisperEngine(modelPath: whisperModel)
        await fresh.warmUp()
      }()
      async let meetingPiece: Void = {
        _ = try? await meeting.recognize(audio, languages: languages)
      }()
      _ = await (restart, meetingPiece)
    }
  }

  @Test func twoDetectorsMarkAtOnce() async throws {
    let audio = samples(16_000 * 60)
    for _ in 1...4 {
      let first = WhisperVADDetector(modelPath: detectorModel)
      let second = WhisperVADDetector(modelPath: detectorModel)
      async let a = first.markup(audio)
      async let b = second.markup(audio)
      _ = try await (a, b)
    }
  }

  @Test func meetingParakeetBesideDictationParakeet() async throws {
    let audio = try fixture("ru-phrase")
    let languages = LanguageSelection(codes: ["ru"], autoDetect: true)
    let engine = ParakeetEngine(modelDirectory: parakeetModel)
    let meeting = try await ParakeetMeetingRecognizer.load(modelDirectory: parakeetModel)
    for _ in 1...4 {
      async let piece = meeting.recognize(audio, languages: languages)
      async let dictation = engine.transcribe(audio, languages: languages, deadline: .seconds(30))
      let (words, text) = try await (piece, dictation)
      #expect(!words.isEmpty)
      #expect(!text.text.isEmpty)
    }
  }
}

private func collapsed(_ text: String) -> String {
  text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
}

@Suite(
  "Meeting recognisers on the recorded fixtures",
  .enabled(if: FileManager.default.fileExists(atPath: whisperModel.path)))
struct MeetingRecognizerTests {
  @Test(arguments: [("ru-phrase", "ru"), ("en-phrase", "en")])
  func whisperWordsJoinToItsText(fixtureName: String, code: String) async throws {
    let audio = try fixture(fixtureName)
    let languages = LanguageSelection(codes: [code], autoDetect: false, pinned: code)
    let recognizer = try await WhisperMeetingRecognizer.load(modelPath: whisperModel)
    let words = try await recognizer.recognize(audio, languages: languages)
    let plain = try await recognizer.plainText(audio, languages: languages)
    #expect(words.count > 1)
    #expect(collapsed(words.map(\.text).joined(separator: " ")) == collapsed(plain))
    let clip = Double(audio.count) / 16_000
    #expect(zip(words, words.dropFirst()).allSatisfy { $0.start <= $1.start })
    #expect(words.allSatisfy { $0.start >= 0 && $0.end <= clip + 0.05 })
  }
}

@Suite(
  "Parakeet meeting recogniser on the recorded fixtures",
  .enabled(if: FileManager.default.fileExists(atPath: parakeetModel.path)))
struct ParakeetMeetingRecognizerTests {
  @Test(arguments: [("ru-phrase", "ru"), ("en-phrase", "en")])
  func parakeetWordsJoinToItsText(fixtureName: String, code: String) async throws {
    let audio = try fixture(fixtureName)
    let languages = LanguageSelection(codes: [code], autoDetect: true)
    let recognizer = try await ParakeetMeetingRecognizer.load(modelDirectory: parakeetModel)
    let (words, text) = try await recognizer.recognizeWithText(audio, languages: languages)
    #expect(words.count > 1)
    #expect(collapsed(words.map(\.text).joined(separator: " ")) == collapsed(text))
    #expect(zip(words, words.dropFirst()).allSatisfy { $0.start <= $1.start })
  }
}

private struct NoTurns: MeetingDiarizing {
  func turns(in samples: [Int16]) async throws -> [SpeakerTurn] { [] }
}

@Suite(
  "Two voices on a meeting's call track become two speakers",
  .enabled(if: ready(detectorModel, parakeetModel, diarizerModel)))
struct MeetingDiarizationSlowTests {
  private let s: UInt64 = 1_000_000_000
  private let callStart = 1.0

  private func turns(of audio: [Float]) -> [ClosedRange<Double>] {
    let gap = 12_800
    var spans: [ClosedRange<Double>] = []
    var start: Int?
    var zeros = 0
    for (index, sample) in (audio + Array(repeating: 0, count: gap)).enumerated() {
      if sample != 0 {
        if start == nil { start = index }
        zeros = 0
        continue
      }
      zeros += 1
      guard zeros == gap, let from = start else { continue }
      spans.append(Double(from) / 16_000...Double(index - gap + 1) / 16_000)
      start = nil
    }
    return spans.map { ($0.lowerBound + callStart)...($0.upperBound + callStart) }
  }

  @Test func twoVoicesBecomeTwoSpeakers() async throws {
    let audio = try fixture("two-voices")
    let spans = turns(of: audio)
    try #require(spans.count == 6)

    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("vocula-diarization-slow-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = MeetingStore(directory: root)
    let cipher = PassthroughCipher()
    var header = MeetingHeader(id: UUID(), startedAt: Date(), anchor: s)
    _ = try await store.begin(header, cipher: cipher, recovering: false)
    try await store.write(
      MeetingChunk(
        track: .system, sequence: 0,
        runs: [MeetingRun(start: s + s, samples: audio.map(MeetingRun.sample))]),
      of: header.id, cipher: cipher)
    header.finish(atHost: s + UInt64(Double(audio.count) / 16_000 * 1e9) + 2 * s, by: .stopped)
    try await store.update(header, cipher: cipher)

    let languages = LanguageSelection(codes: ["en"], autoDetect: true)
    let transcriber = MeetingTranscriber(
      MeetingTranscriber.Dependencies(
        store: store,
        cipher: { PassthroughCipher() },
        model: { MeetingModel(model: .parakeetUltra, languages: languages) },
        makeRecognizer: { _ in
          try await ParakeetMeetingRecognizer.load(modelDirectory: parakeetModel)
        },
        makeDetector: { WhisperVADDetector(modelPath: detectorModel) },
        diarization: MeetingDiarization(
          state: MeetingDiarizerState(), isInstalled: { true },
          load: { try await ParakeetMeetingDiarizer.load(modelDirectory: diarizerModel) },
          discard: {}, wallClock: { Date() }),
        now: { DispatchTime.now().uptimeNanoseconds },
        sleep: { try await Task.sleep(for: $0) },
        publish: { _ in },
        log: nil))
    await transcriber.run()
    let transcript = try await store.transcript(of: header.id, cipher: cipher)
    let lines = transcript.utterances

    #expect(Set(lines.map(\.speaker)) == [.numbered(1), .numbered(2)])
    for line in lines {
      let turn = spans.firstIndex {
        $0.lowerBound - 0.3 <= line.start && line.start <= $0.upperBound
      }
      let index = try #require(turn, "line at \(line.start) is in no turn: \(line.text)")
      #expect(
        line.speaker == .numbered(index % 2 + 1),
        "turn \(index) at \(line.start): \(line.speaker.rawValue) said \(line.text)")
    }
  }
}
