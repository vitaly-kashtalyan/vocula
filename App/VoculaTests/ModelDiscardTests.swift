import Foundation
import Testing
import VoculaKit

@testable import Vocula

@Suite("Discarding a model")
struct ModelDiscardTests {
  @Test("a model pointed at a directory of its own is never deleted")
  func overrideSurvives() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("discard-\(UUID().uuidString)")
    let own = root.appendingPathComponent("own")
    try FileManager.default.createDirectory(at: own, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ModelStore(
      directory: root, fileSystem: SystemModelFileSystem(),
      localOverrides: [.parakeetUltra: own])

    #expect(!AppCoordinator.removeInstalled(.parakeetUltra, from: store))
    #expect(FileManager.default.fileExists(atPath: own.path))
  }

  @Test("a downloaded model is deleted")
  func downloadIsDeleted() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("discard-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ModelStore(directory: root, fileSystem: SystemModelFileSystem())
    let installed = store.url(for: .parakeetUltra)
    try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)

    #expect(AppCoordinator.removeInstalled(.parakeetUltra, from: store))
    #expect(!FileManager.default.fileExists(atPath: installed.path))
  }

  @Test("discarding Parakeet Ultra leaves an older Parakeet v3 directory alone")
  func anOlderV3Survives() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("discard-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ModelStore(directory: root, fileSystem: SystemModelFileSystem())
    let v3 = root.appendingPathComponent("parakeet-tdt-0.6b-v3")
    try FileManager.default.createDirectory(at: v3, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: store.url(for: .parakeetUltra), withIntermediateDirectories: true)

    #expect(AppCoordinator.removeInstalled(.parakeetUltra, from: store))
    #expect(FileManager.default.fileExists(atPath: v3.path))
  }

  @Test("models.path is read on a Debug build")
  func overrideIsReadInDebug() throws {
    let suite = "app.vocula.tests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set("/tmp/own-model", forKey: "models.path.qwenRefine2B")
    #if DEBUG
      #expect(
        ModelStore.developmentOverrides(defaults)
          == [.qwenRefine2B: URL(fileURLWithPath: "/tmp/own-model")])
    #else
      #expect(ModelStore.developmentOverrides(defaults).isEmpty)
    #endif
  }

  @Test("the speaker model's discard refuses a second copy and an override")
  func theDiarizerDiscardRefusesASecondCopyAndAnOverride() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("discard-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let plain = ModelStore(directory: root, fileSystem: SystemModelFileSystem())
    let installed = plain.url(for: .speakerDiarizer)
    try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)

    #expect(!MeetingTranscriptionParts.discardDiarizer(from: plain, isSecondCopy: true))
    #expect(FileManager.default.fileExists(atPath: installed.path))

    let own = root.appendingPathComponent("own")
    try FileManager.default.createDirectory(at: own, withIntermediateDirectories: true)
    let overridden = ModelStore(
      directory: root, fileSystem: SystemModelFileSystem(), localOverrides: [.speakerDiarizer: own])
    #expect(!MeetingTranscriptionParts.discardDiarizer(from: overridden, isSecondCopy: false))
    #expect(FileManager.default.fileExists(atPath: own.path))

    #expect(MeetingTranscriptionParts.discardDiarizer(from: plain, isSecondCopy: false))
    #expect(!FileManager.default.fileExists(atPath: installed.path))
  }

  @Test("a speaker model that could not be removed is not reported as removed")
  func anUnremovableDiarizerIsNotReportedRemoved() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("discard-\(UUID().uuidString)")
    let store = ModelStore(directory: root, fileSystem: SystemModelFileSystem())
    let installed = store.url(for: .speakerDiarizer)
    try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)
    try Data("x".utf8).write(to: installed.appendingPathComponent("f"))
    chmod(root.path, 0o500)
    defer {
      chmod(root.path, 0o700)
      try? FileManager.default.removeItem(at: root)
    }

    #expect(!MeetingTranscriptionParts.discardDiarizer(from: store, isSecondCopy: false))
    #expect(FileManager.default.fileExists(atPath: installed.path))
  }
}
