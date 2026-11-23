import CoreML
import FluidAudio
import Foundation
import Testing
import VoculaKit

@testable import VoculaParakeet

private let modelDirectory = FileManager.default.homeDirectoryForCurrentUser
  .appendingPathComponent(
    "Library/Application Support/app.vocula.mac/Models/parakeet-ultra-95eaa59")

private var modelIsAbsent: Bool {
  !FileManager.default.fileExists(atPath: modelDirectory.path)
}

private func fixture(_ name: String) throws -> [Float] {
  let url = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures/\(name).f32")
  let data = try Data(contentsOf: url)
  return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
}

@Suite(
  "Parakeet on the recorded fixtures",
  .disabled(if: modelIsAbsent, "Parakeet model not downloaded"))
struct ParakeetPipelineTests {
  @Test(
    "Each fixture comes back as the sentence that was spoken",
    arguments: [
      ("en-phrase", "en", "Hello, this is a test"),
      ("es-phrase", "es", "Hola, esto es una prueba"),
      ("pl-phrase", "pl", "Jestem szczęśliwy i zadowolony"),
      ("ru-phrase", "ru", "Я счастлив и доволен"),
      ("pl-cue", "pl", "Jestem szczęśliwy i zadowolony"),
    ])
  func transcribesAFixture(name: String, code: String, expected: String) async throws {
    let engine = ParakeetEngine(modelDirectory: modelDirectory)
    let result = try await engine.transcribe(
      try fixture(name), languages: .pinned(code), deadline: .seconds(60))
    #expect(result.text.hasPrefix(expected))
    #expect(result.language == code)
  }

  @Test("Auto-detect passes no hint and still transcribes")
  func autoDetectNeedsNoHint() async throws {
    let engine = ParakeetEngine(modelDirectory: modelDirectory)
    let result = try await engine.transcribe(
      try fixture("ru-phrase"),
      languages: LanguageSelection(codes: ["ru", "pl"], autoDetect: true),
      deadline: .seconds(60))
    #expect(result.text.hasPrefix("Я счастлив и доволен"))
    #expect(result.languageScores.isEmpty)
  }
}

private func fakeUltra(at model: URL) throws {
  let vocabulary = Dictionary(uniqueKeysWithValues: (0..<8192).map { (String($0), "t\($0)") })
  try FileManager.default.createDirectory(at: model, withIntermediateDirectories: true)
  for entry in ModelManifest.descriptor(for: .parakeetUltra).contents {
    let url = model.appendingPathComponent(entry)
    guard entry.hasSuffix(".mlmodelc") else {
      try JSONSerialization.data(withJSONObject: vocabulary).write(to: url)
      continue
    }
    let weights = url.appendingPathComponent("weights", isDirectory: true)
    try FileManager.default.createDirectory(at: weights, withIntermediateDirectories: true)
    try Data("junk".utf8).write(to: url.appendingPathComponent("coremldata.bin"))
    try Data("junk".utf8).write(to: weights.appendingPathComponent("weight.bin"))
  }
}

private func snapshot(of directory: URL) -> [String: Data] {
  Dictionary(
    uniqueKeysWithValues: (FileManager.default.subpaths(atPath: directory.path) ?? [])
      .compactMap { path in
        (try? Data(contentsOf: directory.appendingPathComponent(path))).map { (path, $0) }
      })
}

@Suite("Parakeet without any weights on disk")
struct ParakeetWithoutModelTests {
  @Test(
    "FluidAudio finds every file it reads for Parakeet Ultra under the names the manifest downloads"
  )
  func theManifestNamesWhatFluidAudioReads() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let model = root.appendingPathComponent(Repo.parakeetUltra.folderName, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try fakeUltra(at: model)
    let contents = ModelManifest.descriptor(for: .parakeetUltra).contents
    let error = #expect(throws: (any Error).self) {
      try AsrModels.loadLocal(from: model, version: .ultra)
    }
    if case .modelNotFound(let name, _)? = error as? AsrModelsError {
      Issue.record("FluidAudio reads \(name), which the manifest does not download")
    }
    #expect(
      AsrModels.modelsExist(at: model, version: .ultra),
      "FluidAudio needs a file the manifest does not download")
    let aside = root.appendingPathComponent("aside")
    for entry in contents {
      try FileManager.default.moveItem(at: model.appendingPathComponent(entry), to: aside)
      #expect(
        !AsrModels.modelsExist(at: model, version: .ultra),
        "the manifest downloads \(entry), which FluidAudio does not need")
      try FileManager.default.moveItem(at: aside, to: model.appendingPathComponent(entry))
    }
  }

  @Test("Every code this app offers for Parakeet is one FluidAudio knows")
  func theCodeListIsNotAHandWrittenGuess() {
    for code in EngineLanguages.parakeetCodes {
      #expect(
        Language(rawValue: code) != nil,
        "\(code) would silently fall back to auto-detect, defeating the pin")
    }
  }

  @Test("A directory with no bundles is refused before FluidAudio can reach the network")
  func anEmptyDirectoryIsRefusedLocally() async throws {
    let nowhere = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let engine = ParakeetEngine(modelDirectory: nowhere)
    await #expect(throws: TranscriptionError.modelNotLoaded) {
      try await engine.transcribe(
        [Float](repeating: 0.1, count: 16000),
        languages: .pinned("en"), deadline: .seconds(5))
    }
  }

  @Test("An empty recording is answered without touching the model at all")
  func emptyAudioNeedsNoModel() async throws {
    let nowhere = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let engine = ParakeetEngine(modelDirectory: nowhere)
    let result = try await engine.transcribe(
      [], languages: .pinned("pl"), deadline: .seconds(1))
    #expect(result.text.isEmpty)
  }
}

@Suite("Models that will not load, with the download host unreachable", .serialized)
struct ParakeetUnloadableModelTests {
  @Test("A model that will not load is refused without deleting or downloading anything")
  func anUnloadableModelIsLeftAlone() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let model = root.appendingPathComponent("parakeet-ultra", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try fakeUltra(at: model)
    let before = snapshot(of: model)
    #expect(before.count == 9)
    let host = ModelRegistry.baseURL
    ModelRegistry.baseURL = "http://127.0.0.1:9"
    defer { ModelRegistry.baseURL = host }

    let engine = ParakeetEngine(modelDirectory: model)
    await #expect(throws: TranscriptionError.modelNotLoaded) {
      try await engine.transcribe(
        [Float](repeating: 0.1, count: 16000), languages: .pinned("en"), deadline: .seconds(30))
    }
    #expect(snapshot(of: model) == before)
  }

  @Test("A speaker model that will not load is refused without deleting or downloading anything")
  func anUnloadableDiarizerIsLeftAlone() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let model = root.appendingPathComponent("speaker-diarizer-df2625a", isDirectory: true)
    for entry in ModelManifest.descriptor(for: .speakerDiarizer).contents {
      let url = model.appendingPathComponent(entry)
      guard entry.hasSuffix(".mlmodelc") else {
        try FileManager.default.createDirectory(at: model, withIntermediateDirectories: true)
        try Data("junk".utf8).write(to: url)
        continue
      }
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
      try Data("junk".utf8).write(to: url.appendingPathComponent("model.mil"))
      try Data("junk".utf8).write(to: url.appendingPathComponent("coremldata.bin"))
    }
    let empty = root.appendingPathComponent("empty", isDirectory: true)
    try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
    let before = snapshot(of: model)
    #expect(before.count == 9)
    let host = ModelRegistry.baseURL
    ModelRegistry.baseURL = "http://127.0.0.1:9"
    defer { ModelRegistry.baseURL = host }

    for directory in [model, empty] {
      await #expect {
        _ = try await ParakeetMeetingDiarizer.load(modelDirectory: directory)
      } throws: { error in
        guard case .model? = error as? MeetingDiarizerError else { return false }
        return true
      }
    }
    #expect(snapshot(of: model) == before)
    #expect(snapshot(of: empty).isEmpty)
  }
}

@Suite("The speaker separation adapter, without its weights")
struct ParakeetMeetingDiarizerTests {
  @Test("The manifest downloads the files FluidAudio's offline diarizer loads")
  func theDiarizerContentsAreWhatFluidAudioLoads() {
    #expect(
      ModelManifest.descriptor(for: .speakerDiarizer).contents == [
        ModelNames.OfflineDiarizer.segmentationFile, ModelNames.OfflineDiarizer.fbankFile,
        ModelNames.OfflineDiarizer.embeddingFile, ModelNames.OfflineDiarizer.pldaRhoFile,
        ModelNames.OfflineDiarizer.pldaParameters,
      ])
  }

  @Test(
    "Segmentation and FBank run on the CPU; on the GPU segmentation held 620 MB more for the same speed"
  )
  func theModelsRunWhereTheyCostLeast() {
    let names = ModelNames.OfflineDiarizer.self
    #expect(ParakeetMeetingDiarizer.computeUnits[names.segmentationFile] == .cpuOnly)
    #expect(ParakeetMeetingDiarizer.computeUnits[names.fbankFile] == .cpuOnly)
    #expect(ParakeetMeetingDiarizer.computeUnits[names.embeddingFile] == .all)
    #expect(ParakeetMeetingDiarizer.computeUnits[names.pldaRhoFile] == .all)
    #expect(ParakeetMeetingDiarizer.computeUnits.count == 4)
  }

  @Test("The split is FluidAudio's default, with runs that no cluster voted for re-embedded")
  func theConfigurationReembedsZeroVoteRuns() {
    let configuration = ParakeetMeetingDiarizer.configuration
    #expect(configuration.zeroVoteReembed.enabled)
    #expect(configuration.zeroVoteReembed.minDurationSeconds == 0.4)
    var expected = OfflineDiarizerConfig.default
    expected.zeroVoteReembed = configuration.zeroVoteReembed
    #expect(String(describing: configuration) == String(describing: expected))
    #expect(!OfflineDiarizerConfig.default.zeroVoteReembed.enabled)
    #expect(!configuration.postProcessing.exclusiveSegments)
  }

  @Test("No speech found is no turns, not a failure")
  func noSpeechIsNoTurnsNotAFailure() {
    #expect(
      ParakeetMeetingDiarizer.outcome(of: OfflineDiarizationError.noSpeechDetected, loading: false)
        == .noSpeech)
  }

  @Test("Error codes are the underlying code or a fixed number, never a bridged case index")
  func errorsAreClassifiedWithoutCaseIndexes() {
    typealias Adapter = ParakeetMeetingDiarizer
    #expect(Adapter.outcome(of: CancellationError(), loading: false) == .cancelled)
    for loading in [false, true] {
      #expect(
        Adapter.outcome(of: NSError(domain: MLModelErrorDomain, code: 5), loading: loading)
          == .failure(.model(code: 5)))
    }
    let missing = NSError(domain: NSCocoaErrorDomain, code: 260)
    #expect(Adapter.outcome(of: missing, loading: false) == .failure(.failed(code: 260)))
    #expect(Adapter.outcome(of: missing, loading: true) == .failure(.model(code: 260)))
    #expect(
      Adapter.outcome(of: NSError(domain: NSPOSIXErrorDomain, code: 12), loading: false)
        == .failure(.failed(code: 12)))
    #expect(
      Adapter.outcome(of: NSError(domain: NSOSStatusErrorDomain, code: -50), loading: false)
        == .failure(.failed(code: -50)))
    let own: [(OfflineDiarizationError, Int)] = [
      (.modelNotLoaded("x"), 10), (.invalidConfiguration("x"), 11), (.invalidBatchSize("x"), 12),
      (.processingFailed("x"), 13), (.exportFailed("x"), 14), (.invalidSpan("x"), 15),
    ]
    for (error, code) in own {
      #expect(Adapter.outcome(of: error, loading: false) == .failure(.failed(code: code)))
      #expect(Adapter.outcome(of: error, loading: true) == .failure(.model(code: code)))
    }
    let memory: [(ANEMemoryUtils.ANEMemoryError, Int)] = [
      (.allocationFailed, 30), (.invalidShape, 31), (.unsupportedDataType, 32),
      (.invalidArrayBounds, 33),
    ]
    for (error, code) in memory {
      #expect(Adapter.outcome(of: error, loading: false) == .failure(.failed(code: code)))
    }
    #expect((ANEMemoryUtils.ANEMemoryError.invalidShape as NSError).code == 1)
    enum Probe: Error { case a, b }
    #expect((Probe.b as NSError).code == 1)
    #expect(Adapter.outcome(of: Probe.b, loading: false) == .failure(.failed(code: 0)))
  }
}
