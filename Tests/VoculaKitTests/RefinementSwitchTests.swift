import Foundation
import Testing

@testable import VoculaKit

struct ActiveRow: Sendable, CustomTestStringConvertible {
  let intent: Bool
  let model: ModelStatus
  let active: Bool
  var testDescription: String { "switch \(intent ? "on" : "off"), model \(model) → \(active)" }
}

struct FooterRow: Sendable, CustomTestStringConvertible {
  let intent: Bool
  let model: ModelStatus
  let footer: RefinementSwitch.Footer
  var testDescription: String { "switch \(intent ? "on" : "off"), model \(model) → \(footer)" }
}

struct ToggleRow: Sendable, CustomTestStringConvertible {
  let on: Bool
  let model: ModelStatus
  let download: RefinementSwitch.Download
  let action: RefinementSwitch.Action?
  var testDescription: String {
    "turned \(on ? "on" : "off"), model \(model), download \(download) → \(action.map { "\($0)" } ?? "nothing")"
  }
}

private final class PresenceFS: ModelFileSystem, @unchecked Sendable {
  let present: Set<String>
  private(set) var hashes = 0

  init(present: Set<String>) { self.present = present }

  func fileExists(at url: URL) -> Bool { present.contains(url.lastPathComponent) }
  func size(of url: URL) -> Int64? { nil }
  func availableCapacity(at url: URL) -> Int64? { nil }
  func sha256(of url: URL) throws -> String {
    hashes += 1
    return ""
  }
}

@Suite("Refinement switch")
struct RefinementSwitchTests {
  static let activeRows: [ActiveRow] = [
    .init(intent: true, model: .ready, active: true),
    .init(intent: false, model: .ready, active: false),
    .init(intent: true, model: .missing, active: false),
    .init(intent: false, model: .missing, active: false),
    .init(intent: true, model: .incomplete(bytes: 1), active: false),
    .init(intent: false, model: .incomplete(bytes: 1), active: false),
    .init(intent: true, model: .corrupted, active: false),
    .init(intent: false, model: .corrupted, active: false),
  ]

  @Test("clean-up is active only with the switch on and its model ready", arguments: activeRows)
  func active(_ row: ActiveRow) {
    #expect(RefinementSwitch.isActive(intent: row.intent, model: row.model) == row.active)
  }

  @Test("every model but the clean-up one is always wanted")
  func otherModelsAreAlwaysWanted() {
    for id in ModelID.allCases where id != .qwenRefine2B {
      #expect(RefinementSwitch.isWanted(id, intent: true), "\(id)")
      #expect(RefinementSwitch.isWanted(id, intent: false), "\(id)")
    }
  }

  @Test("the clean-up model is wanted exactly while the switch is on")
  func theCleanUpModelFollowsTheSwitch() {
    #expect(RefinementSwitch.isWanted(.qwenRefine2B, intent: true))
    #expect(RefinementSwitch.isWanted(.qwenRefine2B, intent: false) == false)
  }

  static let footerRows: [FooterRow] = [
    .init(intent: true, model: .ready, footer: .explanation),
    .init(intent: false, model: .ready, footer: .explanation),
    .init(intent: false, model: .missing, footer: .explanationOffersDownload),
    .init(intent: false, model: .incomplete(bytes: 1), footer: .explanationOffersDownload),
    .init(intent: false, model: .corrupted, footer: .explanationOffersDownload),
    .init(intent: true, model: .missing, footer: .pastesAsRecognised),
    .init(intent: true, model: .incomplete(bytes: 1), footer: .pastesAsRecognised),
    .init(intent: true, model: .corrupted, footer: .pastesAsRecognised),
  ]

  @Test("the footer under the switch", arguments: footerRows)
  func footer(_ row: FooterRow) {
    #expect(RefinementSwitch.footer(intent: row.intent, model: row.model) == row.footer)
  }

  static let toggleRows: [ToggleRow] = [
    .init(on: true, model: .missing, download: .idle, action: .startDownload),
    .init(on: true, model: .corrupted, download: .idle, action: .startDownload),
    .init(on: true, model: .ready, download: .idle, action: nil),
    .init(on: true, model: .missing, download: .otherModel, action: nil),
    .init(on: true, model: .missing, download: .thisModel, action: nil),
    .init(on: false, model: .missing, download: .thisModel, action: .cancelDownload),
    .init(on: false, model: .ready, download: .thisModel, action: .cancelDownload),
    .init(on: false, model: .missing, download: .otherModel, action: nil),
    .init(on: false, model: .missing, download: .idle, action: nil),
    .init(on: false, model: .ready, download: .idle, action: nil),
  ]

  @Test("what turning the switch does", arguments: toggleRows)
  func toggled(_ row: ToggleRow) {
    #expect(
      RefinementSwitch.toggled(on: row.on, model: row.model, download: row.download)
        == row.action)
  }

  private static func settings(switchOn: Bool) -> AppSettings {
    let defaults = UserDefaults(suiteName: "test.refine.switch")!
    defaults.removePersistentDomain(forName: "test.refine.switch")
    defaults.set(switchOn, forKey: AppSettings.refineEnabledKey)
    return AppSettings(defaults: defaults)
  }

  private static let everyEntry = Set(
    ModelManifest.descriptor(for: .qwenRefine2B).contents.map {
      URL(fileURLWithPath: $0).lastPathComponent
    })

  @Test("the pipeline's gate reads the switch and the model on disk, and hashes nothing")
  func theGateReadsTheSwitchAndTheDisk() {
    let complete = PresenceFS(present: Self.everyEntry)
    let store = ModelStore(
      directory: URL(fileURLWithPath: "/tmp/vocula-gate"), fileSystem: complete)
    #expect(RefinementSwitch.isActive(settings: Self.settings(switchOn: true), store: store))
    #expect(
      RefinementSwitch.isActive(settings: Self.settings(switchOn: false), store: store) == false)
    #expect(complete.hashes == 0)

    let oneMissing = PresenceFS(present: Self.everyEntry.subtracting([Self.everyEntry.first!]))
    let broken = ModelStore(
      directory: URL(fileURLWithPath: "/tmp/vocula-gate"), fileSystem: oneMissing)
    #expect(
      RefinementSwitch.isActive(settings: Self.settings(switchOn: true), store: broken) == false)
  }
}
