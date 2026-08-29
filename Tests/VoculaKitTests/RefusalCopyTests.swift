import Testing

@testable import VoculaKit

@Suite("Refusal copy")
struct RefusalCopyTests {
  @Test("every failure has copy", arguments: SessionFailure.allCases, [true, false])
  func everyFailureHasCopy(failure: SessionFailure, recording: Bool) {
    #expect(RefusalCopy.text(for: failure, historyIsRecording: recording).count > 10)
  }

  @Test("every insert refusal has copy", arguments: InsertDenyReason.allCases, [true, false])
  func everyDenyHasCopy(reason: InsertDenyReason, recording: Bool) {
    #expect(RefusalCopy.text(for: reason, historyIsRecording: recording).count > 10)
  }

  @Test("seven failures produce eight distinct sentences")
  func failureKeysAreDistinct() {
    let keys = SessionFailure.allCases.flatMap {
      RefusalCopy.keys(for: $0, historyIsRecording: true)
    }
    #expect(Set(keys).count == 8)
  }

  @Test("a silenced input and a dead device are not the same sentence")
  func silencedInputSplitsInTwo() {
    #expect(
      RefusalCopy.keys(
        for: .silentInput, historyIsRecording: true,
        inputIsSilenced: true)
        != RefusalCopy.keys(
          for: .silentInput, historyIsRecording: true,
          inputIsSilenced: false))
  }

  @Test("the queue timeout and the pass timeout read differently")
  func timeoutsAreDistinct() {
    #expect(
      RefusalCopy.keys(for: .queueTimeout, historyIsRecording: true)
        != RefusalCopy.keys(for: .passTimeout, historyIsRecording: true))
  }

  @Test(
    "only a refusal that has text points at where the text is",
    arguments: SessionFailure.allCases, [true, false])
  func onlyRecoverableFailuresOfferRecovery(failure: SessionFailure, recording: Bool) {
    let keys = RefusalCopy.keys(for: failure, historyIsRecording: recording)
    let offersRecovery = keys.contains { $0.hasPrefix("refusal.recovery.") }
    #expect(offersRecovery == (failure == .insertionFailed))
    #expect(keys.count == (failure == .insertionFailed ? 2 : 1))
  }

  @Test(
    "every insert refusal points at where the text is",
    arguments: InsertDenyReason.allCases, [true, false])
  func everyDenyOffersRecovery(reason: InsertDenyReason, recording: Bool) {
    let keys = RefusalCopy.keys(for: reason, historyIsRecording: recording)
    #expect(keys.count == 2)
    #expect(
      keys.last
        == (recording
          ? "refusal.recovery.historyOn"
          : "refusal.recovery.historyOff"))
  }

  @Test("the recovery sentence is its own key, in both directions")
  func recoveryIsItsOwnKey() {
    let on = RefusalCopy.keys(for: .insertionFailed, historyIsRecording: true)
    let off = RefusalCopy.keys(for: .insertionFailed, historyIsRecording: false)
    #expect(on.first == off.first)
    #expect(on.last != off.last)
  }

  @Test(
    "every key is symbolic, and none of them is a sentence",
    arguments: SessionFailure.allCases)
  func keysAreSymbolic(failure: SessionFailure) {
    for key in RefusalCopy.keys(for: failure, historyIsRecording: true) {
      #expect(key.hasPrefix("refusal."))
      #expect(!key.contains(" "))
    }
  }

  @Test(
    "with history off, no copy sends the user to History",
    arguments: InsertDenyReason.allCases)
  func historyOffNeverNamesHistory(reason: InsertDenyReason) {
    #expect(!RefusalCopy.text(for: reason, historyIsRecording: false).contains("in History"))
    #expect(
      RefusalCopy.keys(for: reason, historyIsRecording: false)
        .contains("refusal.recovery.historyOff"))
  }

  @Test("with history off, the one recoverable failure still says where the text is")
  func historyOffInsertionFailedStillRecovers() {
    #expect(
      !RefusalCopy.text(for: .insertionFailed, historyIsRecording: false)
        .contains("in History"))
    #expect(
      RefusalCopy.keys(for: .insertionFailed, historyIsRecording: false)
        .contains("refusal.recovery.historyOff"))
  }

  @Test("the guard's refusals are said in terms of what the user did")
  func denialsReadAsUserActions() {
    #expect(
      RefusalCopy.text(for: .appChanged, historyIsRecording: true)
        .contains("you switched to another app"))
    #expect(
      RefusalCopy.text(for: .windowChanged, historyIsRecording: true)
        .contains("you switched to another window"))
    #expect(
      RefusalCopy.text(for: .elementChanged, historyIsRecording: true)
        .contains("you clicked into another field"))
    #expect(
      RefusalCopy.text(for: .secureField, historyIsRecording: true)
        .contains("password field"))
  }

  @Test("a dropped hallucination is deliberately silent, not accidentally silent")
  func hallucinationIsSilentOnPurpose() {
    #expect(
      RefusalCopy.text(
        forRawReason: RefusalCopy.hallucination,
        historyIsRecording: true) == nil)
    #expect(
      RefusalCopy.keys(
        forRawReason: RefusalCopy.hallucination,
        historyIsRecording: true) == nil)
  }

  @Test("every other reason resolves to copy, and an unknown one still says something")
  func rawReasonsResolve() {
    #expect(
      RefusalCopy.keys(
        forRawReason: SessionFailure.passTimeout.rawValue,
        historyIsRecording: true)
        == RefusalCopy.keys(for: .passTimeout, historyIsRecording: true))
    #expect(
      RefusalCopy.keys(
        forRawReason: InsertDenyReason.secureField.rawValue,
        historyIsRecording: true)
        == RefusalCopy.keys(for: .secureField, historyIsRecording: true))
    #expect(RefusalCopy.keys(forRawReason: "something-new", historyIsRecording: true) != nil)
    #expect(RefusalCopy.keys(forRawReason: nil, historyIsRecording: true) != nil)
    #expect(RefusalCopy.text(forRawReason: "something-new", historyIsRecording: true) != nil)
    #expect(RefusalCopy.text(forRawReason: nil, historyIsRecording: true) != nil)
  }

  @Test("an unknown reason promises nothing about where the text is")
  func unknownReasonsPromiseNothing() {
    for recording in [true, false] {
      for raw in [nil, "something-new"] {
        let keys = RefusalCopy.keys(forRawReason: raw, historyIsRecording: recording)
        #expect(keys?.contains { $0.hasPrefix("refusal.recovery.") } == false)
      }
    }
  }

  @Test("the hallucination sentinel is not a key")
  func hallucinationIsNotAKey() {
    #expect(!RefusalCopy.hallucination.hasPrefix("refusal."))
  }

  @Test("a recording judged silent is explained rather than passed over")
  func noSpeechIsExplained() {
    #expect(RefusalCopy.noSpeechKey == "refusal.noSpeech")
    #expect(RefusalCopy.noSpeechText.isEmpty == false)
  }

  @Test("does not suggest a microphone or settings problem")
  func noSpeechDoesNotBlameTheMicrophone() {
    let copy = RefusalCopy.noSpeechText.lowercased()
    #expect(!copy.contains("microphone"))
    #expect(!copy.contains("settings"))
  }
}

@Suite("A silenced input names itself")
struct SilencedInputCopyTests {
  @Test("the level is named when it is down")
  func namesTheLevel() {
    #expect(
      RefusalCopy.keys(
        for: .silentInput, historyIsRecording: false,
        inputIsSilenced: true) == ["refusal.silentInput.volumeDown"])
  }

  @Test("otherwise the device is named instead")
  func namesTheDevice() {
    #expect(
      RefusalCopy.keys(for: .silentInput, historyIsRecording: false)
        == ["refusal.silentInput.deadDevice"])
  }
}

@Suite("Every refusal key has a sentence behind it")
struct RefusalKeyCoverageTests {
  private var everyKey: Set<String> {
    var keys: Set<String> = [RefusalCopy.noSpeechKey, "refusal.nothingInserted"]
    for historyIsRecording in [true, false] {
      for inputIsSilenced in [true, false] {
        for failure in SessionFailure.allCases {
          keys.formUnion(
            RefusalCopy.keys(
              for: failure, historyIsRecording: historyIsRecording,
              inputIsSilenced: inputIsSilenced))
        }
      }
      for reason in InsertDenyReason.allCases {
        keys.formUnion(
          RefusalCopy.keys(for: reason, historyIsRecording: historyIsRecording))
      }
    }
    return keys
  }

  @Test("the key set is not empty, or this suite would prove nothing")
  func theKeySetIsReal() {
    #expect(everyKey.count >= 12, "only \(everyKey.count) keys were gathered")
  }

  @Test("no key resolves to itself")
  func everyKeyResolves() {
    for key in everyKey {
      #expect(
        RefusalCopy.text(forKey: key) != key,
        "\(key) fell through to the default and would reach the user as a raw key")
    }
  }

  @Test("the sentence a failure shows is built from the keys it declares")
  func textIsDerivedFromKeys() {
    for historyIsRecording in [true, false] {
      for failure in SessionFailure.allCases {
        let fromKeys = RefusalCopy.keys(
          for: failure, historyIsRecording: historyIsRecording
        ).map(RefusalCopy.text(forKey:)).joined(separator: " ")
        #expect(
          RefusalCopy.text(for: failure, historyIsRecording: historyIsRecording) == fromKeys,
          "\(failure) shows a sentence its own key list does not produce")
      }
      for reason in InsertDenyReason.allCases {
        let fromKeys = RefusalCopy.keys(
          for: reason, historyIsRecording: historyIsRecording
        ).map(RefusalCopy.text(forKey:)).joined(separator: " ")
        #expect(
          RefusalCopy.text(for: reason, historyIsRecording: historyIsRecording) == fromKeys,
          "\(reason) shows a sentence its own key list does not produce")
      }
    }
  }
}
