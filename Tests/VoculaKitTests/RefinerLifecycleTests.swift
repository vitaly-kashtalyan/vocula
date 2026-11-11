import Testing

@testable import VoculaKit

struct LifecycleScenario: Sendable, CustomTestStringConvertible {
  let name: String
  let steps: [(RefinerLifecycle.Event, [RefinerLifecycle.Action])]
  var testDescription: String { name }
}

@Suite("Refiner lifecycle")
struct RefinerLifecycleTests {
  static let scenarios: [LifecycleScenario] = [
    .init(
      name: "starting with clean-up on prewarms",
      steps: [(.pipelineStarted(isEnabled: true), [.prewarm])]),
    .init(
      name: "starting with clean-up off loads nothing",
      steps: [(.pipelineStarted(isEnabled: false), [])]),
    .init(
      name: "switching on prewarms",
      steps: [
        (.pipelineStarted(isEnabled: false), []),
        (.settingChanged(isEnabled: true), [.prewarm]),
      ]),
    .init(
      name: "switching off unloads",
      steps: [
        (.pipelineStarted(isEnabled: true), [.prewarm]),
        (.settingChanged(isEnabled: false), [.unload]),
      ]),
    .init(
      name: "a defaults change that leaves the switch where it was does nothing",
      steps: [
        (.pipelineStarted(isEnabled: true), [.prewarm]),
        (.settingChanged(isEnabled: true), []),
        (.settingChanged(isEnabled: false), [.unload]),
        (.settingChanged(isEnabled: false), []),
      ]),
    .init(
      name: "off then on fast unloads, then prewarms again",
      steps: [
        (.pipelineStarted(isEnabled: true), [.prewarm]),
        (.settingChanged(isEnabled: false), [.unload]),
        (.settingChanged(isEnabled: true), [.prewarm]),
      ]),
    .init(
      name: "off during a load that then fails deletes nothing",
      steps: [
        (.pipelineStarted(isEnabled: true), [.prewarm]),
        (.settingChanged(isEnabled: false), [.unload]),
        (.loadFailed(isEnabled: false, model: .ready), []),
      ]),
    .init(
      name: "a failure read before the switch-off is seen keeps the model, then unloads",
      steps: [
        (.pipelineStarted(isEnabled: true), [.prewarm]),
        (.loadFailed(isEnabled: false, model: .ready), []),
        (.settingChanged(isEnabled: false), [.unload]),
      ]),
    .init(
      name: "a failed load with the model on disk switches off, forgets, and discards",
      steps: [
        (.pipelineStarted(isEnabled: true), [.prewarm]),
        (.loadFailed(isEnabled: true, model: .ready), [.switchOff, .unload, .discard]),
        (.settingChanged(isEnabled: false), []),
      ]),
    .init(
      name: "a failure read before the switch-on is seen still discards, once",
      steps: [
        (.pipelineStarted(isEnabled: false), []),
        (.loadFailed(isEnabled: true, model: .ready), [.switchOff, .unload, .discard]),
        (.settingChanged(isEnabled: false), []),
      ]),
    .init(
      name: "a failed load before anything was downloaded deletes nothing",
      steps: [
        (.pipelineStarted(isEnabled: true), [.prewarm]),
        (.loadFailed(isEnabled: true, model: .missing), []),
        (.loadFailed(isEnabled: true, model: .incomplete(bytes: 1)), []),
        (.loadFailed(isEnabled: true, model: .corrupted), []),
      ]),
    .init(
      name: "the model arriving after a load found nothing: the restart loads it",
      steps: [
        (.pipelineStarted(isEnabled: true), [.prewarm]),
        (.loadFailed(isEnabled: true, model: .missing), []),
        (.tornDown, [.unload]),
        (.pipelineStarted(isEnabled: true), [.prewarm]),
      ]),
    .init(
      name: "a re-download after a failure loads nothing until switched on again",
      steps: [
        (.pipelineStarted(isEnabled: true), [.prewarm]),
        (.loadFailed(isEnabled: true, model: .ready), [.switchOff, .unload, .discard]),
        (.settingChanged(isEnabled: false), []),
        (.tornDown, [.unload]),
        (.pipelineStarted(isEnabled: false), []),
        (.settingChanged(isEnabled: true), [.prewarm]),
      ]),
    .init(
      name: "teardown unloads, and a change before the next start touches nothing",
      steps: [
        (.pipelineStarted(isEnabled: true), [.prewarm]),
        (.tornDown, [.unload]),
        (.settingChanged(isEnabled: false), []),
        (.settingChanged(isEnabled: true), []),
        (.tornDown, []),
      ]),
    .init(
      name: "a failed load reported after teardown still discards a model on disk",
      steps: [
        (.pipelineStarted(isEnabled: true), [.prewarm]),
        (.tornDown, [.unload]),
        (.loadFailed(isEnabled: true, model: .ready), [.switchOff, .discard]),
      ]),
    .init(
      name: "before any pipeline, nothing is performed",
      steps: [
        (.settingChanged(isEnabled: true), []),
        (.loadFailed(isEnabled: false, model: .missing), []),
        (.tornDown, []),
      ]),
  ]

  @Test("every row of the table", arguments: scenarios)
  func row(_ scenario: LifecycleScenario) {
    var lifecycle = RefinerLifecycle()
    for (index, (event, expected)) in scenario.steps.enumerated() {
      #expect(lifecycle.handle(event) == expected, "step \(index): \(event)")
    }
  }
}
