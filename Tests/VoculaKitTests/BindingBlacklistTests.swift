import Testing

@testable import VoculaKit

@Suite("Apple's standard shortcuts")
struct AppleStandardShortcutTests {
  @Test(
    "⌘ plus a standard key is warned about",
    arguments: [
      (UInt16(0x06), "Undo"), (UInt16(0x08), "Copy"), (UInt16(0x00), "Select All"),
      (UInt16(0x01), "Save"), (UInt16(0x2B), "Settings"),
    ])
  func standardCommandShortcutsWarn(_ code: UInt16, _ what: String) {
    let binding = KeyBinding(
      klass: .comboWithKey, keyCode: code,
      modifiers: [.leftCommand])
    guard case .warning = BindingBlacklist.check(binding) else {
      Issue.record("⌘\(what) was accepted without a word")
      return
    }
  }

  @Test("the refusals still refuse")
  func refusalsWin() {
    for code: UInt16 in [0x09, 0x0C, 0x0D] {
      let binding = KeyBinding(
        klass: .comboWithKey, keyCode: code,
        modifiers: [.leftCommand])
      guard case .rejected = BindingBlacklist.check(binding) else {
        Issue.record("⌘ key \(code) was not refused")
        return
      }
    }
  }

  @Test("the default language cycle is clean")
  func defaultIsClean() {
    guard case .allowed = BindingBlacklist.check(.languageCycle) else {
      Issue.record("the shipped default does not pass our own rules")
      return
    }
  }
}

@Suite("Binding refusal copy")
struct BindingBlacklistCopyTests {
  @Test("a verdict carries a symbolic key, not a sentence")
  func verdictCarriesAKey() {
    guard
      case .rejected(let key) = BindingBlacklist.check(
        KeyBinding(klass: .comboWithKey, keyCode: 0x39, modifiers: []))
    else {
      Issue.record("Caps Lock is no longer refused")
      return
    }
    #expect(key == "binding.rejected.capsLock")
  }

  @Test("every key resolves to copy of its own", arguments: BindingBlacklist.allMessageKeys)
  func everyKeyResolves(key: String) {
    let text = BindingBlacklist.text(forKey: key)
    #expect(text != key, "\(key) fell through to the default arm")
    #expect(text.count > 10)
  }

  @Test("no two refusals say the same thing")
  func everyMessageIsDistinct() {
    let texts = BindingBlacklist.allMessageKeys.map(BindingBlacklist.text(forKey:))
    #expect(Set(texts).count == BindingBlacklist.allMessageKeys.count)
    #expect(
      Set(BindingBlacklist.allMessageKeys).count
        == BindingBlacklist.allMessageKeys.count)
  }
}
