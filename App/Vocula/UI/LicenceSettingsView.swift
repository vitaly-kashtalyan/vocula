import AppKit
import SwiftUI
import VoculaKit

struct LicenceSettingsView: View {
  @AppStorage(AppSettings.licenceKeyKey) private var key = AppSettings.licenceKeyDefault

  @AppStorage(UsageLedger.usageCountKey) private var dictationsToday = 0

  @AppStorage(UsageLedger.highWaterKey) private var highWaterSeen = 0.0

  private var verdict: LicenceVerifier.Verdict { LicenceVerifier.verdict(for: key) }

  @State private var confirmingRemoval = false
  @FocusState private var keyFieldFocused: Bool

  var body: some View {
    if case .licensed(let holder) = verdict {
      licensed(to: holder)
    } else {
      unlicensed
    }
  }

  @ViewBuilder
  private func licensed(to holder: String) -> some View {
    Section {
      LabeledContent(LicenceScreenCopy.licensedTo) {
        Label {
          Text(verbatim: holder)
        } icon: {
          Image(systemName: "checkmark.seal.fill")
        }
        .foregroundStyle(Theme.accentText)
        .accessibilityIdentifier("licence.holder")
      }
    } footer: {
      VStack(alignment: .leading, spacing: 6) {
        Text(LicenceScreenCopy.unlimited)
        Text(LicenceScreenCopy.personalLicence)
      }
    }

    Section {
      Button(LicenceScreenCopy.removeItem, role: .destructive) { confirmingRemoval = true }
        .accessibilityIdentifier("licence.remove")
        .confirmationDialog(
          Text(LicenceScreenCopy.removeTitle),
          isPresented: $confirmingRemoval, titleVisibility: .visible
        ) {
          Button(LicenceScreenCopy.removeButton, role: .destructive) { key = "" }
        } message: {
          Text(LicenceScreenCopy.removeMessage)
        }
    }
  }

  @ViewBuilder
  private var unlicensed: some View {
    Section {
      LabeledContent(LicenceScreenCopy.status) { status }
      LabeledContent(LicenceScreenCopy.freeUse) { allowance }
    } footer: {
      Text(LicenceScreenCopy.offlineCheck)
    }

    clockOvershoot

    Section {
      Button(LicenceScreenCopy.pasteButton) {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        key = text
      }
      .accessibilityIdentifier("licence.paste")

      if case .invalid = verdict {
        keyField
        Button(LicenceScreenCopy.clearButton, role: .destructive) { key = "" }
          .accessibilityIdentifier("licence.clear")
      }
    } footer: {
      if case .invalid = verdict {
        Text(LicenceScreenCopy.notAKey)
      } else {
        Text(LicenceScreenCopy.pasteHint)
      }
    }

    Section {
      Link(LicenceScreenCopy.buy, destination: URL(string: "https://vocula.app")!)
        .accessibilityIdentifier("licence.buy")
    }
  }

  @ViewBuilder
  private var keyField: some View {
    ZStack(alignment: .topLeading) {
      if key.isEmpty {
        Text(LicenceScreenCopy.fieldPlaceholder)
          .font(.system(size: 12, design: .monospaced))
          .foregroundStyle(Theme.textMuted)
          .allowsHitTesting(false)
      }
      TextField(text: $key, axis: .vertical) { Text(verbatim: "") }
        .textFieldStyle(.plain)
        .lineLimit(3...5)
        .font(.system(size: 12, design: .monospaced))
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .focused($keyFieldFocused)
        .accessibilityIdentifier("licence.key")
    }
    .padding(10)
    .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
    .background(
      RoundedRectangle(cornerRadius: Theme.Radius.control)
        .fill(Theme.cardBackground)
    )
    .overlay(
      RoundedRectangle(cornerRadius: Theme.Radius.control)
        .strokeBorder(Theme.cardBorder)
        .allowsHitTesting(false)
    )
    .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control))
    .onTapGesture { keyFieldFocused = true }
  }

  @ViewBuilder
  private var clockOvershoot: some View {
    if let seen = UsageLedger().clockOvershoot() {
      Section {
        LabeledContent(LicenceScreenCopy.clockRow) {
          Text(verbatim: seen.formatted(date: .abbreviated, time: .omitted))
            .foregroundStyle(Theme.warning)
            .accessibilityIdentifier("licence.clock.seen")
        }
        Button(LicenceScreenCopy.clockReset) { UsageLedger().forgetClockHistory() }
          .accessibilityIdentifier("licence.clock.reset")
      } footer: {
        Text(LicenceScreenCopy.clockExplained)
      }
    }
  }

  @ViewBuilder
  private var allowance: some View {
    switch UsageLedger().entitlement(licensed: false) {
    case .trial(let daysLeft):
      Text(verbatim: CountedText.text(LicenceCopy.trialDaysLeft(count: daysLeft)))
        .foregroundStyle(Theme.textSecondary)
    case .limited(let remaining):
      Text(
        verbatim: CountedText.text(
          LicenceCopy.dictationsLeftToday(
            count: remaining, of: TrialPolicy.dictationsPerDayAfterTrial))
      )
      .foregroundStyle(remaining == 0 ? Theme.warning : Theme.textSecondary)
    case .licensed:
      EmptyView()
    }
  }

  @ViewBuilder
  private var status: some View {
    switch verdict {
    case .absent:
      Text(LicenceScreenCopy.notActivated).foregroundStyle(Theme.textMuted)
    case .licensed(let holder):
      Label {
        Text(verbatim: holder)
      } icon: {
        Image(systemName: "checkmark.seal.fill")
      }
      .foregroundStyle(Theme.accentText)
      .accessibilityIdentifier("licence.holder")
    case .invalid:
      Label(LicenceScreenCopy.notRecognised, systemImage: "exclamationmark.triangle.fill")
        .foregroundStyle(Theme.warning)
    }
  }
}
