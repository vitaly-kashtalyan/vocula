import Foundation
import Testing

@testable import VoculaKit

@Suite("Live check and binding storage")
struct LiveCheckTests {
  @Test("both press and release arrived → the binding works")
  func working() {
    var check = LiveCheck(timeout: .seconds(5))
    check.observe(.press(at: .milliseconds(0)))
    check.observe(.release(at: .milliseconds(200)))
    #expect(check.outcome == .working)
  }

  @Test("nothing arrived → someone below us took the key")
  func nothingArrived() {
    var check = LiveCheck(timeout: .seconds(5))
    check.observe(.timeout(at: .seconds(5)))
    #expect(check.outcome == .nothingArrived)
  }

  @Test("press without release → hold will not work on this key")
  func pressWithoutRelease() {
    var check = LiveCheck(timeout: .seconds(5))
    check.observe(.press(at: .milliseconds(0)))
    check.observe(.timeout(at: .seconds(5)))
    #expect(check.outcome == .pressWithoutRelease)
  }

  @Test("release without press is reported too")
  func releaseWithoutPress() {
    var check = LiveCheck(timeout: .seconds(5))
    check.observe(.release(at: .milliseconds(10)))
    check.observe(.timeout(at: .seconds(5)))
    #expect(check.outcome == .releaseWithoutPress)
  }

  @Test("a single sided modifier becomes .singleModifier")
  func capturesSingleModifier() {
    let binding = BindingCapture.binding(
      from: CapturedKey(keyCode: nil, modifiers: [.rightCommand]))
    #expect(binding.klass == .singleModifier)
    #expect(binding.modifiers == [.rightCommand])
    #expect(binding.keyCode == nil)
  }

  @Test("Fn alone is a single modifier, not a pair")
  func capturesFn() {
    #expect(
      BindingCapture.binding(from: CapturedKey(keyCode: nil, modifiers: [.function]))
        .klass == .singleModifier)
  }

  @Test("two modifiers become .modifierPair, which has no double tap")
  func capturesModifierPair() {
    let binding = BindingCapture.binding(
      from: CapturedKey(keyCode: nil, modifiers: [.leftControl, .leftOption]))
    #expect(binding.klass == .modifierPair)
  }

  @Test("a function key with no modifiers becomes .functionKey and absorbs")
  func capturesFunctionKey() {
    let binding = BindingCapture.binding(from: CapturedKey(keyCode: 0x69, modifiers: []))
    #expect(binding.klass == .functionKey)
    #expect(binding.absorbsOwnEvent == true)
  }

  @Test("an ordinary key with modifiers becomes .comboWithKey")
  func capturesCombo() {
    let binding = BindingCapture.binding(
      from: CapturedKey(keyCode: 0x02, modifiers: [.leftControl, .leftOption]))
    #expect(binding.klass == .comboWithKey)
    #expect(binding.absorbsOwnEvent == true)
  }

  @Test("an ordinary key with no modifiers is produced and then rejected")
  func capturesBareKeyAndRejectsIt() {
    let binding = BindingCapture.binding(from: CapturedKey(keyCode: 0x02, modifiers: []))
    guard case .rejected = BindingBlacklist.check(binding) else {
      Issue.record("a bare key must be rejected with an explanation")
      return
    }
  }

  @Test("no verdict before either both events or the timeout")
  func noEarlyVerdict() {
    var check = LiveCheck(timeout: .seconds(5))
    check.observe(.press(at: .milliseconds(0)))
    #expect(check.outcome == nil)
  }

  @Test("a rejected binding is not saved")
  func rejectedIsNotSaved() {
    let defaults = UserDefaults(suiteName: "test.rejected")!
    defaults.removePersistentDomain(forName: "test.rejected")
    var store = BindingStore(defaults: defaults)
    let verdict = store.save(
      primary: KeyBinding(
        klass: .comboWithKey, keyCode: 0x09,
        modifiers: [.leftCommand]))
    guard case .rejected = verdict else {
      Issue.record("⌘V must be rejected")
      return
    }
    #expect(store.primary == .fn)
  }

  @Test("a warned binding IS saved — the user decides whose key matters more")
  func warnedIsSaved() {
    let defaults = UserDefaults(suiteName: "test.warned")!
    defaults.removePersistentDomain(forName: "test.warned")
    var store = BindingStore(defaults: defaults)
    let verdict = store.save(primary: .rightOption)
    guard case .warning = verdict else {
      Issue.record("right ⌥ must warn")
      return
    }
    #expect(store.primary == .rightOption)
  }

  @Test("the binding survives a relaunch by key code, not by character")
  func survivesRelaunch() {
    let defaults = UserDefaults(suiteName: "test.persist")!
    defaults.removePersistentDomain(forName: "test.persist")
    var store = BindingStore(defaults: defaults)
    let combo = KeyBinding(
      klass: .comboWithKey, keyCode: 0x02,
      modifiers: [.leftControl, .leftOption])
    _ = store.save(primary: combo)
    let reloaded = BindingStore(defaults: defaults)
    #expect(reloaded.primary == combo)
    #expect(reloaded.primary.keyCode == 0x02)
  }

  @Test("the config handed to the state machine reflects the stored bindings")
  func configMirrorsStore() {
    let defaults = UserDefaults(suiteName: "test.config")!
    defaults.removePersistentDomain(forName: "test.config")
    var store = BindingStore(defaults: defaults)
    #expect(store.config.primary == .fn)
    _ = store.save(primary: .rightControl)
    #expect(store.config.primary == .rightControl)
    #expect(store.config.languageCycle == .languageCycle)
  }
}

@Suite("Live check copy")
struct LiveCheckCopyTests {
  @Test("every outcome has a key of its own", arguments: LiveCheckOutcome.allCases)
  func everyOutcomeHasAKey(outcome: LiveCheckOutcome) {
    let key = LiveCheck.explanationKey(for: outcome)
    #expect(key.hasPrefix("livecheck."))
    #expect(!key.contains(" "))
  }

  @Test("four outcomes, four keys")
  func keysAreDistinct() {
    let keys = LiveCheckOutcome.allCases.map(LiveCheck.explanationKey(for:))
    #expect(Set(keys).count == 4)
  }

  @Test("a press without a release is not the same message as a release without a press")
  func theTwoHalfGesturesStayApart() {
    #expect(
      LiveCheck.explanationKey(for: .pressWithoutRelease)
        != LiveCheck.explanationKey(for: .releaseWithoutPress))
    #expect(
      LiveCheck.explanation(for: .pressWithoutRelease)
        != LiveCheck.explanation(for: .releaseWithoutPress))
  }

  @Test("every outcome still has copy", arguments: LiveCheckOutcome.allCases)
  func everyOutcomeHasCopy(outcome: LiveCheckOutcome) {
    #expect(LiveCheck.explanation(for: outcome).count > 10)
  }
}
