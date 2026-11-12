import Foundation
import Testing

@testable import VoculaKit

private struct FakeFS: ModelFileSystem {
  var files: [String: Int64] = [:]
  var digests: [String: String] = [:]
  var capacity: Int64? = 100_000_000_000

  func fileExists(at url: URL) -> Bool { files[url.lastPathComponent] != nil }
  func size(of url: URL) -> Int64? { files[url.lastPathComponent] }
  func availableCapacity(at url: URL) -> Int64? { capacity }
  func sha256(of url: URL) throws -> String { digests[url.lastPathComponent] ?? "" }
}

private final class CountingFS: ModelFileSystem, @unchecked Sendable {
  var files: [String: Int64] = [:]
  var digests: [String: String] = [:]
  var capacity: Int64? = 100_000_000_000
  private(set) var hashCallCounts: [String: Int] = [:]

  func fileExists(at url: URL) -> Bool { files[url.lastPathComponent] != nil }
  func size(of url: URL) -> Int64? { files[url.lastPathComponent] }
  func availableCapacity(at url: URL) -> Int64? { capacity }
  func sha256(of url: URL) throws -> String {
    hashCallCounts[url.lastPathComponent, default: 0] += 1
    return digests[url.lastPathComponent] ?? ""
  }
}

private let directory = URL(fileURLWithPath: "/tmp/vocula-models")
private let transcription = ModelID.largeV3Turbo
private let required: [ModelID] = [transcription, .speechDetector]

private func store(_ fs: FakeFS) -> ModelStore {
  ModelStore(directory: directory, fileSystem: fs, manifest: ModelManifest.current)
}

@Suite("ModelStore")
struct ModelStoreTests {
  @Test("the manifest pins every model with a version, a checksum and a licence")
  func manifestIsComplete() {
    #expect(ModelManifest.current.count == 4)
    for model in ModelManifest.current {
      #expect(model.sha256.count == 64)
      #expect(model.sha256.allSatisfy { $0.isHexDigit })
      #expect(!model.version.isEmpty)
      #expect(!model.licence.isEmpty)
      #expect(model.byteSize > 0)
    }
    #expect(Set(ModelManifest.current.map(\.id)) == Set(ModelID.allCases))
    #expect(ModelManifest.transcriptionModels.count == 2)
    #expect(!ModelManifest.transcriptionModels.contains(.speechDetector))
    #expect(!ModelManifest.transcriptionModels.contains(.qwenRefine2B))
    let grouped = ModelManifest.transcriptionModelsByFamily
    #expect(grouped.flatMap(\.models) == ModelManifest.transcriptionModels)
    #expect(grouped.allSatisfy { !$0.models.isEmpty })
  }

  @Test("the refinement model arrives as an archive and is never offered as an engine")
  func refinementModelIsNotAnEngine() {
    let descriptor = ModelManifest.descriptor(for: .qwenRefine2B)
    #expect(descriptor.unpacked != nil)
    #expect(!descriptor.contents.isEmpty)
    #expect(descriptor.family == .refiner)
    #expect(!ModelManifest.transcriptionModelsByFamily.contains { $0.family == .refiner })
  }

  @Test("the clean-up model's licence line says the Qwen weights were modified")
  func refinementModelSaysItIsModified() {
    #expect(ModelManifest.descriptor(for: .qwenRefine2B).licence.contains("modified"))
  }

  @Test("refinement is off until someone turns it on")
  func refinementDefaultsOff() {
    let defaults = UserDefaults(suiteName: "test.refine.default")!
    defaults.removePersistentDomain(forName: "test.refine.default")
    #expect(AppSettings(defaults: defaults).refineEnabled == false)
  }

  @Test("a local override moves one model, and status reads it there, while the others stay put")
  func localOverrideIsUsed() {
    let elsewhere = URL(fileURLWithPath: "/tmp/somewhere/qwen")
    var fs = FakeFS()
    for name in ModelManifest.descriptor(for: .qwenRefine2B).contents { fs.files[name] = 1 }
    let store = ModelStore(
      directory: directory, fileSystem: fs, manifest: ModelManifest.current,
      localOverrides: [.qwenRefine2B: elsewhere])
    #expect(store.url(for: .qwenRefine2B) == elsewhere)
    #expect(store.status(of: .qwenRefine2B) == .ready)
    #expect(store.url(for: .largeV3Turbo).deletingLastPathComponent().path == directory.path)
  }

  @Test("a fresh install starts on Whisper, and an unknown model falls back to it")
  func whisperIsTheDefaultEngine() {
    #expect(ModelManifest.defaultTranscriptionModel == .largeV3Turbo)
    #expect(ModelManifest.descriptor(for: .largeV3Turbo).family == .whisper)

    let defaults = UserDefaults(suiteName: "test.models.default")!
    defaults.removePersistentDomain(forName: "test.models.default")
    #expect(AppSettings(defaults: defaults).transcriptionModel == .largeV3Turbo)
    defaults.set("aModelThisBuildDoesNotHave", forKey: AppSettings.transcriptionModelKey)
    #expect(AppSettings(defaults: defaults).transcriptionModel == .largeV3Turbo)
  }

  @Test("a missing file is missing")
  func missing() {
    #expect(store(FakeFS()).status(of: transcription) == .missing)
  }

  @Test("a short file is incomplete and reports how much arrived")
  func incomplete() {
    let model = ModelManifest.descriptor(for: transcription)
    var fs = FakeFS()
    fs.files[model.fileName] = model.byteSize / 2
    #expect(store(fs).status(of: transcription) == .incomplete(bytes: model.byteSize / 2))
  }

  @Test("a full-size file with the wrong digest is corrupted, not ready")
  func corrupted() {
    let model = ModelManifest.descriptor(for: transcription)
    var fs = FakeFS()
    fs.files[model.fileName] = model.byteSize
    fs.digests[model.fileName] = "deadbeef"
    #expect(store(fs).status(of: transcription) == .corrupted)
  }

  @Test("a full-size file with the right digest is ready")
  func ready() {
    let model = ModelManifest.descriptor(for: transcription)
    var fs = FakeFS()
    fs.files[model.fileName] = model.byteSize
    fs.digests[model.fileName] = model.sha256
    #expect(store(fs).status(of: transcription) == .ready)
  }

  @Test("missing bytes cover both required models")
  func missingBytesCoversBothModels() {
    let total = required.reduce(Int64(0)) { $0 + ModelManifest.descriptor(for: $1).byteSize }
    #expect(store(FakeFS()).missingBytes(for: required) == total)
  }

  @Test("a partial download reduces what is still missing")
  func partialReducesMissing() {
    let model = ModelManifest.descriptor(for: .speechDetector)
    var fs = FakeFS()
    fs.files[model.fileName] = model.byteSize
    fs.digests[model.fileName] = model.sha256
    #expect(
      store(fs).missingBytes(for: required)
        == ModelManifest.descriptor(for: transcription).byteSize)
  }

  @Test("a shortage is reported as a number of bytes")
  func shortageIsANumber() {
    var fs = FakeFS()
    fs.capacity = 1_000_000
    let total = required.reduce(Int64(0)) { $0 + ModelManifest.descriptor(for: $1).byteSize }
    #expect(store(fs).spaceVerdict(for: required) == .short(byBytes: total - 1_000_000))
  }

  @Test("enough space is enough")
  func enoughSpace() {
    #expect(store(FakeFS()).spaceVerdict(for: required) == .enough)
  }

  @Test("an unavailable capacity check never means enough")
  func unknownCapacityRefuses() {
    var fs = FakeFS()
    fs.capacity = nil
    #expect(store(fs).spaceVerdict(for: required) == .unknown)
  }

  @Test("isReady requires BOTH required models — turbo without the detector hallucinates")
  func readyRequiresBoth() {
    let model = ModelManifest.descriptor(for: transcription)
    var fs = FakeFS()
    fs.files[model.fileName] = model.byteSize
    fs.digests[model.fileName] = model.sha256
    #expect(store(fs).isReady(required) == false)
  }

  @Test("a corrupted file is reclaimable before its replacement is downloaded")
  func corruptedFileSpaceIsReclaimable() {
    let model = ModelManifest.descriptor(for: transcription)
    var fs = FakeFS()
    fs.capacity = 10
    fs.files[model.fileName] = model.byteSize
    fs.digests[model.fileName] = "wrong"
    let detector = ModelManifest.descriptor(for: .speechDetector)
    fs.files[detector.fileName] = detector.byteSize
    fs.digests[detector.fileName] = detector.sha256
    #expect(store(fs).spaceVerdict(for: required) == .enough)
  }

  @Test("a model delivered as an archive is named twice, and read as a directory")
  func anExpandedModelHasTwoPaths() {
    let subject = store(FakeFS())
    #expect(subject.url(for: .parakeetUltra).lastPathComponent == "parakeet-ultra-95eaa59")
    #expect(
      subject.archiveURL(for: .parakeetUltra).lastPathComponent == "parakeet-ultra-95eaa59.zip")
    #expect(subject.url(for: transcription) == subject.archiveURL(for: transcription))
  }

  @Test("a verified archive is not yet a ready model; the expanded directory is")
  func expansionIsWhatMakesItReady() {
    let model = ModelManifest.descriptor(for: .parakeetUltra)
    var fs = FakeFS()
    fs.files[model.fileName] = model.byteSize
    fs.digests[model.fileName] = model.sha256
    #expect(store(fs).status(of: .parakeetUltra) == .missing)
    #expect(store(fs).matchesChecksum(.parakeetUltra))

    for entry in model.contents { fs.files[entry] = 1 }
    #expect(store(fs).status(of: .parakeetUltra) == .ready)
  }

  @Test("the checksum is read off the archive, and a wrong one is refused")
  func checksumReadsTheArchive() {
    let model = ModelManifest.descriptor(for: .parakeetUltra)
    var fs = FakeFS()
    #expect(!store(fs).matchesChecksum(.parakeetUltra))
    fs.files[model.fileName] = model.byteSize
    fs.digests[model.fileName] = "wrong"
    #expect(!store(fs).matchesChecksum(.parakeetUltra))
  }

  @Test(
    "every archive says how large it expands, and room is asked for the archive and that at once")
  func spaceCountsTheArchiveAndItsExpansion() throws {
    for model in ModelManifest.current {
      guard model.unpacked != nil else {
        #expect(model.expandedBytes == nil && model.contents.isEmpty, "\(model.id)")
        #expect(store(FakeFS()).missingBytes(for: [model.id]) == model.byteSize)
        continue
      }
      let expanded = try #require(
        model.expandedBytes, "\(model.id) does not say how large it expands")
      #expect(!model.contents.isEmpty, "\(model.id)")
      #expect(store(FakeFS()).missingBytes(for: [model.id]) == model.byteSize + expanded)
    }
  }

  @Test("only an expanded model is discarded when it will not load")
  func onlyAnExpandedModelIsReinstalled() {
    let subject = store(FakeFS())
    #expect(subject.needsReinstall(after: .modelUnreadable, model: .parakeetUltra))
    #expect(!subject.needsReinstall(after: .modelUnreadable, model: transcription))
    for failure in SessionFailure.allCases where failure != .modelUnreadable {
      #expect(!subject.needsReinstall(after: failure, model: .parakeetUltra))
    }
  }

  @Test("Parakeet Ultra is read from the directory and the five entries loadLocal needs")
  func ultraNamesWhatLoadLocalReads() {
    let model = ModelManifest.descriptor(for: .parakeetUltra)
    #expect(model.unpacked == "parakeet-ultra-95eaa59")
    #expect(model.fileName == "parakeet-ultra-95eaa59.zip")
    #expect(
      Set(model.contents) == [
        "Preprocessor.mlmodelc", "Encoder.mlmodelc", "Decoder.mlmodelc",
        "JointDecisionv3.mlmodelc", "parakeet_vocab.json",
      ])
    #expect(ModelManifest.transcriptionModels == [.largeV3Turbo, .parakeetUltra])
  }

  @Test("a stored model id reads back as itself, and a Parakeet v3 one as Parakeet Ultra")
  func storedModelIDsResolve() {
    for id in ModelID.allCases { #expect(ModelID(rawValue: id.rawValue) == id) }
    #expect(ModelID(rawValue: "parakeetV3") == .parakeetUltra)
    #expect(ModelID(rawValue: "parakeetV4") == nil)
    let suite = "test.models.legacy"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    defaults.set("parakeetV3", forKey: AppSettings.transcriptionModelKey)
    #expect(AppSettings(defaults: defaults).transcriptionModel == .parakeetUltra)
    #expect(defaults.string(forKey: AppSettings.transcriptionModelKey) == "parakeetV3")
  }

  @Test("an injected manifest is used for paths, sizes and digests")
  func injectedManifestIsAuthoritative() {
    let custom = ModelDescriptor(
      id: transcription, family: .whisper, fileName: "custom.bin",
      remoteURL: URL(string: "https://example.invalid/custom.bin")!,
      sha256: String(repeating: "a", count: 64), byteSize: 42,
      version: "test", licence: "test", displayName: "Test", unpacked: nil, contents: [])
    var fs = FakeFS()
    fs.files[custom.fileName] = custom.byteSize
    fs.digests[custom.fileName] = custom.sha256
    let injected = ModelStore(directory: directory, fileSystem: fs, manifest: [custom])
    #expect(injected.url(for: transcription).lastPathComponent == "custom.bin")
    #expect(injected.status(of: transcription) == .ready)
    #expect(injected.missingBytes(for: [transcription]) == 0)
  }

  @Test("spaceVerdict hashes each requested model at most once")
  func spaceVerdictHashesEachModelOnce() {
    let fs = CountingFS()
    for model in ModelManifest.current {
      fs.files[model.fileName] = model.byteSize
      fs.digests[model.fileName] = model.sha256
    }
    let subject = ModelStore(directory: directory, fileSystem: fs, manifest: ModelManifest.current)
    _ = subject.spaceVerdict(for: ModelManifest.current.map(\.id))
    for model in ModelManifest.current {
      #expect(fs.hashCallCounts[model.fileName] == (model.unpacked == nil ? 1 : nil))
    }
  }
}
