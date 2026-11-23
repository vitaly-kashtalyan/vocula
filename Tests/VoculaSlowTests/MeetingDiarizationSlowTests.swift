import Foundation
import Testing
import VoculaKit

@testable import VoculaParakeet
@testable import VoculaWhisper

private let models = FileManager.default.homeDirectoryForCurrentUser
  .appendingPathComponent("Library/Application Support/app.vocula.mac/Models")
private let detectorModel = models.appendingPathComponent("ggml-silero-v5.1.2.bin")
private let parakeetModel = models.appendingPathComponent("parakeet-ultra-95eaa59")
private let diarizerModel =
  ProcessInfo.processInfo.environment["VOCULA_DIARIZER_MODEL"].map(URL.init(fileURLWithPath:))
  ?? models.appendingPathComponent("speaker-diarizer-df2625a")

private func ready(_ urls: URL...) -> Bool {
  urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) }
}

@Suite(
  "Two voices on a meeting's call track become two speakers",
  .enabled(if: ready(detectorModel, parakeetModel, diarizerModel)))
struct MeetingDiarizationSlowTests {
  private let s: UInt64 = 1_000_000_000
  private let callStart = 1.0

  private func twoVoices() throws -> [Float] {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .appendingPathComponent("Fixtures/two-voices.f32")
    let data = try Data(contentsOf: url)
    return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
  }

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
    let audio = try twoVoices()
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
