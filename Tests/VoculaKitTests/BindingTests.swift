import Foundation
import Testing

@testable import VoculaKit

@Suite("KeyBinding")
struct BindingTests {
  @Test("only combos and function keys absorb their own event")
  func absorption() {
    #expect(KeyBinding.fn.absorbsOwnEvent == false)
    #expect(KeyBinding.rightCommand.absorbsOwnEvent == false)
    #expect(
      KeyBinding(
        klass: .modifierPair, keyCode: nil,
        modifiers: [.leftControl, .leftShift]
      ).absorbsOwnEvent == false)
    #expect(
      KeyBinding(
        klass: .comboWithKey, keyCode: 0x02,
        modifiers: [.leftControl, .leftShift]
      ).absorbsOwnEvent == true)
    #expect(KeyBinding(klass: .functionKey, keyCode: 0x69, modifiers: []).absorbsOwnEvent == true)
  }

  @Test("only the two modifier-only classes are bare modifiers")
  func bareModifier() {
    #expect(KeyBinding.fn.isBareModifier == true)
    #expect(
      KeyBinding(
        klass: .modifierPair, keyCode: nil,
        modifiers: [.leftControl, .leftShift]
      ).isBareModifier == true)
    #expect(
      KeyBinding(
        klass: .comboWithKey, keyCode: 0x02,
        modifiers: [.leftControl, .leftShift]
      ).isBareModifier == false)
    #expect(KeyBinding(klass: .functionKey, keyCode: 0x69, modifiers: []).isBareModifier == false)
  }

  @Test("sides are distinct bindings, not 'any command'")
  func sidesAreDistinct() {
    #expect(
      KeyBinding.rightCommand
        != KeyBinding(
          klass: .singleModifier, keyCode: nil,
          modifiers: [.leftCommand]))
  }

  @Test("the language cycle defaults to ⌃⇧L")
  func languageCycleDefault() {
    let defaults = UserDefaults(suiteName: "test.languageCycle")!
    defaults.removePersistentDomain(forName: "test.languageCycle")
    let store = BindingStore(defaults: defaults)
    #expect(
      store.languageCycle
        == KeyBinding(
          klass: .comboWithKey, keyCode: 0x25,
          modifiers: [.leftControl, .leftShift]))
    #expect(store.config.languageCycle == store.languageCycle)
    #expect(KeyBinding.languageCycle.absorbsOwnEvent)
  }

  @Test("a rebound language cycle survives a relaunch")
  func languageCycleRebinds() {
    let defaults = UserDefaults(suiteName: "test.languageCycle.rebind")!
    defaults.removePersistentDomain(forName: "test.languageCycle.rebind")
    var store = BindingStore(defaults: defaults)
    let f13 = KeyBinding(klass: .functionKey, keyCode: 0x69, modifiers: [])
    #expect(store.save(languageCycle: f13) == .allowed)
    #expect(BindingStore(defaults: defaults).languageCycle == f13)
  }

  @Test("a rejected language cycle is not saved")
  func languageCycleRejected() {
    let defaults = UserDefaults(suiteName: "test.languageCycle.rejected")!
    defaults.removePersistentDomain(forName: "test.languageCycle.rejected")
    var store = BindingStore(defaults: defaults)
    let commandV = KeyBinding(klass: .comboWithKey, keyCode: 0x09, modifiers: [.leftCommand])
    guard case .rejected = store.save(languageCycle: commandV) else {
      Issue.record("⌘V must be rejected")
      return
    }
    #expect(store.languageCycle == .languageCycle)
  }

  @Test("a binding survives a round trip through Codable")
  func codableRoundTrip() throws {
    let binding = KeyBinding(
      klass: .comboWithKey, keyCode: 0x02,
      modifiers: [.leftControl, .leftShift])
    let data = try JSONEncoder().encode(binding)
    #expect(try JSONDecoder().decode(KeyBinding.self, from: data) == binding)
  }

  @Test(
    "the blacklist rejects a bare key, ⌘V, ⌘Tab, ⌘Space, ⌘Q, ⌘W, Esc and Caps Lock",
    arguments: [
      KeyBinding(klass: .comboWithKey, keyCode: 0x02, modifiers: []),
      KeyBinding(klass: .comboWithKey, keyCode: 0x09, modifiers: [.leftCommand]),
      KeyBinding(klass: .comboWithKey, keyCode: 0x30, modifiers: [.leftCommand]),
      KeyBinding(klass: .comboWithKey, keyCode: 0x31, modifiers: [.leftCommand]),
      KeyBinding(klass: .comboWithKey, keyCode: 0x0C, modifiers: [.leftCommand]),
      KeyBinding(klass: .comboWithKey, keyCode: 0x0D, modifiers: [.leftCommand]),
      KeyBinding(klass: .comboWithKey, keyCode: 0x35, modifiers: []),
      KeyBinding(klass: .singleModifier, keyCode: 0x39, modifiers: []),
    ])
  func blacklistRejects(binding: KeyBinding) {
    guard case .rejected = BindingBlacklist.check(binding) else {
      Issue.record("expected rejection for \(binding)")
      return
    }
  }

  @Test("the blacklist allows Fn and ⌃⌥D")
  func blacklistAllows() {
    #expect(BindingBlacklist.check(.fn) == .allowed)
    #expect(
      BindingBlacklist.check(
        KeyBinding(
          klass: .comboWithKey, keyCode: 0x02,
          modifiers: [.leftControl, .leftShift])) == .allowed)
  }

  @Test("known typical conflicts warn but do not reject")
  func knownConflictsWarn() {
    guard case .warning = BindingBlacklist.check(.rightOption) else {
      Issue.record("right ⌥ should warn about layouts that use it for symbols")
      return
    }
  }

  @Test(
    "a single Shift warns about the JetBrains double-tap conflict",
    arguments: [ModifierSet.leftShift, ModifierSet.rightShift])
  func singleShiftWarns(modifier: ModifierSet) {
    let binding = KeyBinding(klass: .singleModifier, keyCode: nil, modifiers: [modifier])
    guard case .warning = BindingBlacklist.check(binding) else {
      Issue.record("a single Shift should warn about double ⇧ being taken in JetBrains IDEs")
      return
    }
  }

  @Test("a collision with a system hotkey is reported with its action name")
  func systemHotkeyNamed() {
    let defaults: [String: Any] = [
      "AppleSymbolicHotKeys": [
        "64": [
          "enabled": true,
          "value": ["parameters": [32, 49, 1 << 20], "type": "standard"],
        ]
      ]
    ]
    let binding = KeyBinding(klass: .comboWithKey, keyCode: 49, modifiers: [.leftCommand])
    let conflict = SystemHotkeys.conflict(for: binding, in: defaults)
    #expect(conflict?.displayName == "Spotlight")
  }

  @Test("an unknown identifier is shown as a number, not invented")
  func unknownIdentifierShownAsNumber() {
    let defaults: [String: Any] = [
      "AppleSymbolicHotKeys": [
        "9999": [
          "enabled": true,
          "value": ["parameters": [100, 2, 1 << 18], "type": "standard"],
        ]
      ]
    ]
    let binding = KeyBinding(klass: .comboWithKey, keyCode: 2, modifiers: [.leftControl])
    #expect(
      SystemHotkeys.conflict(for: binding, in: defaults)?.displayName
        == "system action #9999")
  }

  @Test("a disabled system hotkey is not a conflict")
  func disabledIsNotAConflict() {
    let defaults: [String: Any] = [
      "AppleSymbolicHotKeys": [
        "64": [
          "enabled": false,
          "value": ["parameters": [32, 49, 1 << 20], "type": "standard"],
        ]
      ]
    ]
    let binding = KeyBinding(klass: .comboWithKey, keyCode: 49, modifiers: [.leftCommand])
    #expect(SystemHotkeys.conflict(for: binding, in: defaults) == nil)
  }
}
