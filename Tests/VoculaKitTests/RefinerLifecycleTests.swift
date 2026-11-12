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
      steps: [(.pipelineStarted(isActive: true), [.prewarm])]),
    .init(
      name: "starting with clean-up off loads nothing",
      steps: [(.pipelineStarted(isActive: false), [])]),
    .init(
      name: "switching on prewarms",
      steps: [
        (.pipelineStarted(isActive: false), []),
        (.settingChanged(isActive: true), [.prewarm]),
      ]),
    .init(
      name: "switching off unloads",
      steps: [
        (.pipelineStarted(isActive: true), [.prewarm]),
        (.settingChanged(isActive: false), [.unload]),
      ]),
    .init(
      name: "a defaults change that leaves the switch where it was does nothing",
      steps: [
        (.pipelineStarted(isActive: true), [.prewarm]),
        (.settingChanged(isActive: true), []),
        (.settingChanged(isActive: false), [.unload]),
        (.settingChanged(isActive: false), []),
      ]),
    .init(
      name: "off then on fast unloads, then prewarms again",
      steps: [
        (.pipelineStarted(isActive: true), [.prewarm]),
        (.settingChanged(isActive: false), [.unload]),
        (.settingChanged(isActive: true), [.prewarm]),
      ]),
    .init(
      name: "off during a load that then fails deletes nothing",
      steps: [
        (.pipelineStarted(isActive: true), [.prewarm]),
        (.settingChanged(isActive: false), [.unload]),
        (.loadFailed(isEnabled: false, model: .ready), []),
      ]),
    .init(
      name: "a failure read before the switch-off is seen keeps the model, then unloads",
      steps: [
        (.pipelineStarted(isActive: true), [.prewarm]),
        (.loadFailed(isEnabled: false, model: .ready), []),
        (.settingChanged(isActive: false), [.unload]),
      ]),
    .init(
      name:
        "a failed load with the model on disk discards and keeps the failure until switched off",
      steps: [
        (.pipelineStarted(isActive: true), [.prewarm]),
        (.loadFailed(isEnabled: true, model: .ready), [.discard]),
        (.settingChanged(isActive: false), [.unload]),
      ]),
    .init(
      name: "a failure read before the switch-on is seen still discards",
      steps: [
        (.pipelineStarted(isActive: false), []),
        (.loadFailed(isEnabled: true, model: .ready), [.discard]),
        (.settingChanged(isActive: false), []),
      ]),
    .init(
      name: "a failed load before anything was downloaded deletes nothing",
      steps: [
        (.pipelineStarted(isActive: true), [.prewarm]),
        (.loadFailed(isEnabled: true, model: .missing), []),
        (.loadFailed(isEnabled: true, model: .incomplete(bytes: 1)), []),
        (.loadFailed(isEnabled: true, model: .corrupted), []),
      ]),
    .init(
      name: "the model arriving after a load found nothing: the restart loads it",
      steps: [
        (.pipelineStarted(isActive: true), [.prewarm]),
        (.loadFailed(isEnabled: true, model: .missing), []),
        (.tornDown, [.unload]),
        (.pipelineStarted(isActive: true), [.prewarm]),
      ]),
    .init(
      name: "after a failure, switching off unloads and switching on loads again",
      steps: [
        (.pipelineStarted(isActive: true), [.prewarm]),
        (.loadFailed(isEnabled: true, model: .ready), [.discard]),
        (.settingChanged(isActive: false), [.unload]),
        (.settingChanged(isActive: true), [.prewarm]),
        (.tornDown, [.unload]),
        (.pipelineStarted(isActive: true), [.prewarm]),
      ]),
    .init(
      name: "teardown unloads, and a change before the next start touches nothing",
      steps: [
        (.pipelineStarted(isActive: true), [.prewarm]),
        (.tornDown, [.unload]),
        (.settingChanged(isActive: false), []),
        (.settingChanged(isActive: true), []),
        (.tornDown, []),
      ]),
    .init(
      name: "a failed load reported after teardown still discards a model on disk",
      steps: [
        (.pipelineStarted(isActive: true), [.prewarm]),
        (.tornDown, [.unload]),
        (.loadFailed(isEnabled: true, model: .ready), [.discard]),
      ]),
    .init(
      name: "before any pipeline, nothing is performed",
      steps: [
        (.settingChanged(isActive: true), []),
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
