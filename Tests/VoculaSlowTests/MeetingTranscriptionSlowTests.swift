import Foundation
import Testing
import VoculaKit
import VoculaParakeet
import VoculaWhisper

private let models = FileManager.default.homeDirectoryForCurrentUser
  .appendingPathComponent("Library/Application Support/app.vocula.mac/Models")
private let whisperModel = models.appendingPathComponent("ggml-large-v3-turbo.bin")
private let detectorModel = models.appendingPathComponent("ggml-silero-v5.1.2.bin")
private let parakeetModel = models.appendingPathComponent("parakeet-ultra-95eaa59")

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

private func freshGate() -> MeetingHoldGate {
  MeetingHoldGate(
    hold: DictationHold(passDeadline: { $0 }, refineWait: { nil }),
    now: { DispatchTime.now().uptimeNanoseconds }, sleep: { try await Task.sleep(for: $0) })
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
        hold: freshGate(),
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
    #expect(transcript.utterances.last.map { $0.start >= 6 && $0.start < 8 } == true)
  }

  @Test func parakeetTurnsItIntoMeThenOthers() async throws {
    let transcript = try await transcribe {
      try await ParakeetMeetingRecognizer.load(modelDirectory: parakeetModel)
    }
    #expect(transcript.utterances.map(\.speaker) == [.me, .others])
    #expect(transcript.utterances.allSatisfy { !$0.text.isEmpty })
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
