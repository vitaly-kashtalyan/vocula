import FluidAudio
import Foundation
import Testing
import VoculaKit
import VoculaParakeet

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

private func snapshot(of directory: URL) throws -> [String: Data] {
  let base = directory.resolvingSymlinksInPath().path + "/"
  var files: [String: Data] = [:]
  let walk = FileManager.default.enumerator(
    at: directory, includingPropertiesForKeys: [.isRegularFileKey])
  while let url = walk?.nextObject() as? URL {
    guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
      continue
    }
    let path = url.resolvingSymlinksInPath().path
    files[String(path.dropFirst(base.count))] = try Data(contentsOf: url)
  }
  return files
}

@Suite("Parakeet without any weights on disk", .serialized)
struct ParakeetWithoutModelTests {
  @Test(
    "FluidAudio finds every file it reads for Parakeet Ultra under the names the manifest downloads"
  )
  func theManifestNamesWhatFluidAudioReads() throws {
    let model = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: model) }
    let vocabulary = Dictionary(uniqueKeysWithValues: (0..<8192).map { (String($0), "t\($0)") })
    for entry in ModelManifest.descriptor(for: .parakeetUltra).contents {
      let url = model.appendingPathComponent(entry)
      if entry.hasSuffix(".mlmodelc") {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data("junk".utf8).write(to: url.appendingPathComponent("coremldata.bin"))
      } else {
        try FileManager.default.createDirectory(at: model, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: vocabulary).write(to: url)
      }
    }
    let error = #expect(throws: (any Error).self) {
      try AsrModels.loadLocal(from: model, version: .ultra)
    }
    if case .modelNotFound(let name, _)? = error as? AsrModelsError {
      Issue.record("FluidAudio reads \(name), which the manifest does not download")
    }
  }

  @Test("A model that will not load is refused without deleting or downloading anything")
  func anUnloadableModelIsLeftAlone() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let model = root.appendingPathComponent("parakeet-ultra", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: model, withIntermediateDirectories: true)
    let vocabulary = Dictionary(uniqueKeysWithValues: (0..<8192).map { (String($0), "t\($0)") })
    try JSONSerialization.data(withJSONObject: vocabulary)
      .write(to: model.appendingPathComponent("parakeet_vocab.json"))
    for bundle in ["Preprocessor", "Encoder", "Decoder", "JointDecisionv3"] {
      let weights = model.appendingPathComponent("\(bundle).mlmodelc/weights", isDirectory: true)
      try FileManager.default.createDirectory(at: weights, withIntermediateDirectories: true)
      try Data("junk".utf8).write(
        to: weights.deletingLastPathComponent().appendingPathComponent("coremldata.bin"))
      try Data("junk".utf8).write(to: weights.appendingPathComponent("weight.bin"))
    }
    let before = try snapshot(of: model)
    #expect(before.count == 9)
    let host = ModelRegistry.baseURL
    ModelRegistry.baseURL = "http://127.0.0.1:9"
    defer { ModelRegistry.baseURL = host }

    let engine = ParakeetEngine(modelDirectory: model)
    await #expect(throws: TranscriptionError.modelNotLoaded) {
      try await engine.transcribe(
        [Float](repeating: 0.1, count: 16000), languages: .pinned("en"), deadline: .seconds(30))
    }
    #expect(try snapshot(of: model) == before)
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
