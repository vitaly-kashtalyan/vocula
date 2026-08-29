import Foundation
import Testing

@testable import Vocula
@testable import VoculaKit

@MainActor
struct BindingSettingsModelTests {
  private func make(_ suite: String) -> (BindingSettingsModel, BindingStore) {
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let store = BindingStore(defaults: defaults)
    let monitor = HotkeyMonitor(
      config: store.config, onSignal: { _ in },
      onTapLost: { _ in }, onGestureAbandoned: {})
    let model = BindingSettingsModel(monitor: monitor, defaults: defaults) { _ in }
    return (model, store)
  }

  @Test("a recorded key is saved at once, with no live check")
  func captureSaves() {
    let (model, store) = make("test.binding.capture")
    model.capture(.record, CapturedKey(keyCode: nil, modifiers: [.rightCommand]))
    #expect(store.primary == .rightCommand)
    #expect(model.binding(for: .record) == .rightCommand)
  }

  @Test("the saved config reaches the monitor through onSaved")
  func captureReportsTheConfig() {
    let defaults = UserDefaults(suiteName: "test.binding.onSaved")!
    defaults.removePersistentDomain(forName: "test.binding.onSaved")
    let store = BindingStore(defaults: defaults)
    let monitor = HotkeyMonitor(
      config: store.config, onSignal: { _ in },
      onTapLost: { _ in }, onGestureAbandoned: {})
    final class Box: @unchecked Sendable { var config: GestureConfig? }
    let box = Box()
    let model = BindingSettingsModel(monitor: monitor, defaults: defaults) {
      box.config = $0
    }
    model.capture(.record, CapturedKey(keyCode: nil, modifiers: [.rightControl]))
    #expect(box.config?.primary == .rightControl)
  }

  @Test("a blacklisted key is refused, the old one stays, and the row says why")
  func rejectedIsNotSaved() {
    let (model, store) = make("test.binding.rejected")
    model.capture(.record, CapturedKey(keyCode: 0x09, modifiers: [.leftCommand]))
    #expect(store.primary == .fn)
    #expect(model.binding(for: .record) == .fn)
    #expect(model.notice(for: .record)?.contains("⌘V") == true)
  }

  @Test("the record slot saves a key of its own")
  func recordSaves() {
    let (model, store) = make("test.binding.record")
    model.capture(.record, CapturedKey(keyCode: 0x02, modifiers: [.leftControl, .leftOption]))
    #expect(
      store.primary
        == KeyBinding(
          klass: .comboWithKey, keyCode: 0x02,
          modifiers: [.leftControl, .leftOption]))
  }

  @Test("the language-cycle slot saves, and is the only one that starts non-empty")
  func languageCycleSaves() {
    let (model, store) = make("test.binding.cycle")
    #expect(model.binding(for: .languageCycle) == .languageCycle)
    let f13 = KeyBinding(klass: .functionKey, keyCode: 0x69, modifiers: [])
    model.capture(.languageCycle, CapturedKey(keyCode: 0x69, modifiers: []))
    #expect(store.languageCycle == f13)
  }

  @Test("rows are named through the layout, not through a four-entry table")
  func rowsAreNamed() {
    let (model, _) = make("test.binding.names")
    #expect(model.name(of: .record) == "fn")
    #expect(model.name(of: .languageCycle).hasPrefix("⌃⇧"))
  }
}
