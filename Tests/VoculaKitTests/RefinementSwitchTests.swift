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

struct LoadRow: Sendable, CustomTestStringConvertible {
  let intent: Bool
  let model: ModelStatus
  let downloadingThis: Bool
  let shows: Bool
  var testDescription: String {
    "switch \(intent ? "on" : "off"), model \(model), downloading \(downloadingThis) → \(shows)"
  }
}

struct ToggleRow: Sendable, CustomTestStringConvertible {
  let on: Bool
  let model: ModelStatus?
  let downloadingThis: Bool
  let busy: Bool
  let action: RefinementSwitch.Action?
  var testDescription: String {
    "turned \(on ? "on" : "off"), model \(model.map { "\($0)" } ?? "unknown"), downloading \(downloadingThis), busy \(busy) → \(action.map { "\($0)" } ?? "nothing")"
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

  static let loadRows: [LoadRow] = [
    .init(intent: true, model: .missing, downloadingThis: false, shows: true),
    .init(intent: true, model: .corrupted, downloadingThis: false, shows: true),
    .init(intent: true, model: .missing, downloadingThis: true, shows: false),
    .init(intent: false, model: .missing, downloadingThis: false, shows: false),
    .init(intent: true, model: .ready, downloadingThis: false, shows: false),
    .init(intent: false, model: .ready, downloadingThis: false, shows: false),
  ]

  @Test(
    "the model row offers Load only while the switch is on and nothing is fetching it",
    arguments: loadRows)
  func load(_ row: LoadRow) {
    #expect(
      RefinementSwitch.showsLoad(
        intent: row.intent, model: row.model, downloadingThis: row.downloadingThis) == row.shows)
  }

  static let toggleRows: [ToggleRow] = [
    .init(on: true, model: .missing, downloadingThis: false, busy: false, action: .startDownload),
    .init(on: true, model: nil, downloadingThis: false, busy: false, action: .startDownload),
    .init(on: true, model: .corrupted, downloadingThis: false, busy: false, action: .startDownload),
    .init(on: true, model: .ready, downloadingThis: false, busy: false, action: nil),
    .init(on: true, model: .missing, downloadingThis: false, busy: true, action: nil),
    .init(on: true, model: nil, downloadingThis: false, busy: true, action: nil),
    .init(on: true, model: .missing, downloadingThis: true, busy: true, action: nil),
    .init(on: false, model: .missing, downloadingThis: true, busy: true, action: .cancelDownload),
    .init(on: false, model: .ready, downloadingThis: true, busy: true, action: .cancelDownload),
    .init(on: false, model: .missing, downloadingThis: false, busy: true, action: nil),
    .init(on: false, model: .missing, downloadingThis: false, busy: false, action: nil),
    .init(on: false, model: .ready, downloadingThis: false, busy: false, action: nil),
    .init(on: false, model: nil, downloadingThis: false, busy: false, action: nil),
  ]

  @Test("what turning the switch does", arguments: toggleRows)
  func toggled(_ row: ToggleRow) {
    #expect(
      RefinementSwitch.toggled(
        on: row.on, model: row.model, downloadingThis: row.downloadingThis, busy: row.busy)
        == row.action)
  }
}
