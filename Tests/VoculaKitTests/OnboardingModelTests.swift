import Testing

@testable import VoculaKit

@Suite("Onboarding")
struct OnboardingModelTests {
  @Test("the screen has four rows when the globe row is not needed")
  func fourRowsByDefault() {
    let rows = OnboardingModel.rows(
      microphone: .granted, accessibility: .granted,
      autostart: .granted, globeKeyNeeded: false, globeKeyDone: false)
    #expect(rows.map(\.kind) == [.microphone, .accessibility, .autostart])
  }

  @Test("the globe row appears only when it is asked for")
  func globeRowIsConditional() {
    let rows = OnboardingModel.rows(
      microphone: .granted, accessibility: .granted,
      autostart: .granted, globeKeyNeeded: true, globeKeyDone: false)
    #expect(rows.map(\.kind).contains(.globeKey))
  }

  @Test("autostart awaiting approval is shown and explained but does not block")
  func autostartNeedsApproval() {
    let rows = OnboardingModel.rows(
      microphone: .granted, accessibility: .granted,
      autostart: .needsUserApproval, globeKeyNeeded: false, globeKeyDone: false)
    #expect(OnboardingModel.isComplete(rows) == true)
    let row = rows.first { $0.kind == .autostart }
    #expect(row?.status == .needsUserApproval)
    #expect(
      OnboardingModel.keys(kind: .autostart, status: .needsUserApproval).explanation
        == "onboarding.autostart.explanation.needsApproval")
  }

  @Test("a missing permission still blocks, whatever autostart says")
  func permissionsStillBlock() {
    let rows = OnboardingModel.rows(
      microphone: .granted, accessibility: .missing,
      autostart: .granted, globeKeyNeeded: false, globeKeyDone: false)
    #expect(OnboardingModel.isComplete(rows) == false)
  }

  @Test("everything granted is complete")
  func complete() {
    let rows = OnboardingModel.rows(
      microphone: .granted, accessibility: .granted,
      autostart: .granted, globeKeyNeeded: false, globeKeyDone: false)
    #expect(OnboardingModel.isComplete(rows) == true)
  }

  @Test("a refused microphone offers System Settings, not another request")
  func microphoneRefused() {
    let rows = OnboardingModel.rows(
      microphone: .missing, accessibility: .granted,
      autostart: .granted, globeKeyNeeded: false, globeKeyDone: false)
    let microphone = rows.first { $0.kind == .microphone }
    #expect(
      OnboardingModel.keys(kind: .microphone, status: .missing).actionTitle
        == "onboarding.action.openSettings")
    #expect(microphone?.explanation.contains("asks only once") == true)
    #expect(OnboardingModel.isComplete(rows) == false)
  }

  @Test("a microphone that was never asked about still offers Request")
  func microphoneNeverAsked() {
    let rows = OnboardingModel.rows(
      microphone: .unknown, accessibility: .granted,
      autostart: .granted, globeKeyNeeded: false, globeKeyDone: false)
    #expect(
      OnboardingModel.keys(kind: .microphone, status: .unknown).actionTitle
        == "onboarding.action.request")
  }

  @Test("a prompt that never appeared is not reported as a refusal")
  func microphonePromptDidNotAppear() {
    let rows = OnboardingModel.rows(
      microphone: .promptDidNotAppear,
      accessibility: .granted, autostart: .granted,
      globeKeyNeeded: false, globeKeyDone: false)
    let microphone = rows.first { $0.kind == .microphone }
    #expect(
      OnboardingModel.keys(kind: .microphone, status: .promptDidNotAppear).actionTitle
        == "onboarding.action.tryAgain")
    #expect(microphone?.explanation.contains("never showed the prompt") == true)
    #expect(microphone?.explanation.contains("nothing was refused") == true)
    #expect(microphone?.explanation.contains("tccutil reset Microphone") == true)
    #expect(microphone?.settingsPath == nil)
    #expect(OnboardingModel.isComplete(rows) == false)
  }

  @Test("a policy-restricted microphone blames the policy, not the user")
  func microphoneRestricted() {
    let rows = OnboardingModel.rows(
      microphone: .restricted, accessibility: .granted,
      autostart: .granted, globeKeyNeeded: false, globeKeyDone: false)
    let microphone = rows.first { $0.kind == .microphone }
    #expect(
      OnboardingModel.keys(kind: .microphone, status: .restricted).actionTitle
        == "onboarding.action.openScreenTime")
    #expect(microphone?.explanation.contains("policy") == true)
    #expect(microphone?.explanation.contains("did not refuse") == true)
    #expect(microphone?.explanation.contains("Screen Time") == true)
    #expect(microphone?.settingsPath == OnboardingModel.screenTimePath)
    #expect(microphone?.settingsPath != OnboardingModel.microphonePath)
    #expect(microphone?.settingsPath?.hasPrefix("System Settings → ") == true)
    #expect(microphone?.actionEnabled == true)
    #expect(OnboardingModel.isComplete(rows) == false)
  }

  @Test("a refusal and a policy restriction are never the same advice")
  func microphoneRestrictedDiffersFromRefused() {
    func microphone(_ status: OnboardingStatus) -> OnboardingRow {
      OnboardingModel.rows(
        microphone: status, accessibility: .granted,
        autostart: .granted, globeKeyNeeded: false, globeKeyDone: false
      )
      .first { $0.kind == .microphone }!
    }
    func keys(_ status: OnboardingStatus) -> OnboardingRowKeys {
      OnboardingModel.keys(kind: .microphone, status: status)
    }
    #expect(keys(.restricted).explanation != keys(.missing).explanation)
    #expect(keys(.restricted).actionTitle != keys(.missing).actionTitle)
    #expect(microphone(.restricted).settingsPath != microphone(.missing).settingsPath)
    #expect(microphone(.restricted).explanation.contains("Refused earlier") == false)
  }

  @Test("refused and never-prompted are different copy and different actions")
  func microphoneStatesDiffer() {
    func microphone(_ status: OnboardingStatus) -> OnboardingRow {
      OnboardingModel.rows(
        microphone: status, accessibility: .granted,
        autostart: .granted, globeKeyNeeded: false, globeKeyDone: false
      )
      .first { $0.kind == .microphone }!
    }
    func keys(_ status: OnboardingStatus) -> OnboardingRowKeys {
      OnboardingModel.keys(kind: .microphone, status: status)
    }
    #expect(keys(.missing).explanation != keys(.promptDidNotAppear).explanation)
    #expect(keys(.missing).actionTitle != keys(.promptDidNotAppear).actionTitle)
    #expect(keys(.unknown).explanation != keys(.promptDidNotAppear).explanation)
    #expect(keys(.unknown).explanation != keys(.granted).explanation)
    _ = microphone(.granted)
  }

  @Test("the one-shot rule is stated before the microphone is requested")
  func oneShotWarningComesFirst() {
    let rows = OnboardingModel.rows(
      microphone: .unknown, accessibility: .granted,
      autostart: .granted, globeKeyNeeded: false, globeKeyDone: false)
    let microphone = rows.first { $0.kind == .microphone }
    #expect(
      OnboardingModel.keys(kind: .microphone, status: .unknown).actionTitle
        == "onboarding.action.request")
    #expect(microphone?.explanation.contains("once per install") == true)
    #expect(microphone?.explanation.contains("cannot ask again") == true)
  }

  @Test("no ungranted row is ever a dead end", arguments: OnboardingStatus.allCases)
  func everyUngrantedRowOffersAWayForward(status: OnboardingStatus) {
    for globeDone in [false, true] {
      let rows = OnboardingModel.rows(
        microphone: status, accessibility: status,
        autostart: status, globeKeyNeeded: true, globeKeyDone: globeDone)
      #expect(rows.count == 4)
      for row in rows where row.status != .granted {
        #expect(row.actionEnabled, "\(row.kind) in \(row.status) has no action")
        #expect(row.actionTitle.isEmpty == false)
      }
    }
  }

  @Test("every row that opens System Settings also names the path in words")
  func settingsPathIsAlwaysWritten() {
    let rows = OnboardingModel.rows(
      microphone: .missing, accessibility: .missing,
      autostart: .needsUserApproval, globeKeyNeeded: true, globeKeyDone: false)
    for row in rows {
      #expect(
        row.settingsPath?.hasPrefix("System Settings → ") == true,
        "\(row.kind) sends the user to Settings without saying where")
    }
    #expect(
      rows.first { $0.kind == .microphone }?.settingsPath
        == "System Settings → Privacy & Security → Microphone")
    #expect(
      rows.first { $0.kind == .accessibility }?.settingsPath
        == "System Settings → Privacy & Security → Accessibility")
  }

  @Test("granted rows point nowhere")
  func grantedRowsHaveNoPath() {
    let rows = OnboardingModel.rows(
      microphone: .granted, accessibility: .granted,
      autostart: .granted, globeKeyNeeded: true, globeKeyDone: true)
    #expect(rows.allSatisfy { $0.settingsPath == nil })
    #expect(rows.filter { $0.actionEnabled }.map(\.kind) == [.autostart])
  }

  @Test("autostart is one live row and remains changeable when enabled")
  func autostartRowCanDisable() {
    let rows = OnboardingModel.rows(
      microphone: .granted, accessibility: .granted,
      autostart: .granted, globeKeyNeeded: false, globeKeyDone: false)
    let autostart = rows.first { $0.kind == .autostart }
    #expect(
      OnboardingModel.keys(kind: .autostart, status: .granted).actionTitle
        == "onboarding.action.disable")
    #expect(autostart?.status == .granted)
    #expect(rows.filter { $0.kind == .autostart }.count == 1)
  }
}

@Suite("Onboarding keys")
struct OnboardingKeyTests {
  @Test(
    "every row has one symbolic key per user-facing field",
    arguments: OnboardingRowKind.allCases, OnboardingStatus.allCases)
  func everyFieldHasItsOwnKey(kind: OnboardingRowKind, status: OnboardingStatus) {
    let keys = OnboardingModel.keys(kind: kind, status: status)
    for key in [keys.title, keys.explanation, keys.actionTitle] {
      #expect(key.hasPrefix("onboarding."))
      #expect(!key.contains(" "))
    }
    #expect(keys.title != keys.explanation)
  }

  @Test(
    "a row's title does not change with its status",
    arguments: OnboardingRowKind.allCases)
  func titleIsStatusIndependent(kind: OnboardingRowKind) {
    let titles = Set(
      OnboardingStatus.allCases.map {
        OnboardingModel.keys(kind: kind, status: $0).title
      })
    #expect(titles.count == 1)
  }

  @Test("the shared action title really is shared")
  func openSettingsIsOneKey() {
    let settings = OnboardingModel.keys(kind: .accessibility, status: .missing).actionTitle
    #expect(OnboardingModel.keys(kind: .microphone, status: .missing).actionTitle == settings)
    #expect(
      OnboardingModel.keys(kind: .autostart, status: .needsUserApproval).actionTitle == settings)
  }

  @Test("each microphone state has an explanation of its own")
  func microphoneExplanationsAreDistinct() {
    let keys = Set(
      OnboardingStatus.allCases.map {
        OnboardingModel.keys(kind: .microphone, status: $0).explanation
      })
    #expect(keys.count == 5)
  }
}

@Suite("Onboarding — what is still missing")
struct OnboardingIncompleteTests {
  private func row(_ kind: OnboardingRowKind, _ status: OnboardingStatus) -> OnboardingRow {
    OnboardingRow(
      kind: kind, status: status, title: "t", explanation: "e",
      actionTitle: "a", settingsPath: nil, actionEnabled: true)
  }

  @Test("only blocking permissions count, and only ungranted ones")
  func filters() {
    let rows = [
      row(.microphone, .granted), row(.accessibility, .missing),
      row(.autostart, .missing),
    ]
    #expect(OnboardingModel.incomplete(rows).map(\.kind) == [.accessibility])
  }

  @Test("complete means nothing is incomplete")
  func agreesWithIsComplete() {
    let granted = [
      row(.microphone, .granted), row(.accessibility, .granted),
      row(.autostart, .missing),
    ]
    #expect(OnboardingModel.isComplete(granted))
    #expect(OnboardingModel.incomplete(granted).isEmpty)
    let missing = granted + [row(.accessibility, .missing)]
    #expect(OnboardingModel.isComplete(missing) == false)
    #expect(OnboardingModel.incomplete(missing).isEmpty == false)
  }
}

@Suite("Every onboarding key has a sentence behind it")
struct OnboardingKeyCoverageTests {
  private var everyKey: Set<String> {
    var keys: Set<String> = []
    for kind in OnboardingRowKind.allCases {
      for status in OnboardingStatus.allCases {
        let row = OnboardingModel.keys(kind: kind, status: status)
        keys.formUnion([row.title, row.explanation, row.actionTitle])
      }
    }
    return keys
  }

  @Test("the key set is not empty, or this suite would prove nothing")
  func theKeySetIsReal() {
    #expect(everyKey.count >= 16, "only \(everyKey.count) keys were gathered")
  }

  @Test("no key resolves to itself")
  func everyKeyResolves() {
    for key in everyKey {
      #expect(
        OnboardingModel.text(forKey: key) != key,
        "\(key) fell through to the default and would reach the user as a raw key")
    }
  }

  @Test("the row a user sees is built from the keys it declares")
  func rowsAreDerivedFromKeys() {
    for status in OnboardingStatus.allCases {
      let rows = OnboardingModel.rows(
        microphone: status, accessibility: status, autostart: status,
        globeKeyNeeded: true, globeKeyDone: status == .granted)
      for row in rows {
        let keys = OnboardingModel.keys(kind: row.kind, status: row.status)
        #expect(row.title == OnboardingModel.text(forKey: keys.title))
        #expect(row.explanation == OnboardingModel.text(forKey: keys.explanation))
        #expect(row.actionTitle == OnboardingModel.text(forKey: keys.actionTitle))
      }
    }
  }
}
