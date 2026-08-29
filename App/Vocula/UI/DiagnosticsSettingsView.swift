import AppKit
import SwiftUI
import VoculaKit

struct DiagnosticsSettingsView: View {
  let menu: MenuBarController
  let coordinator: AppCoordinator
  @State private var events: [DiagnosticEvent] = []
  @State private var confirmingClear = false

  private static let shown = 30

  var body: some View {
    Section {
      if events.isEmpty {
        Text(DiagnosticsScreenCopy.empty).foregroundStyle(Theme.textMuted)
      }
      ForEach(Array(events.enumerated()), id: \.offset) { _, event in
        LabeledContent {
          Text(verbatim: event.detail.isEmpty ? "—" : event.detail)
            .font(Theme.readout)
            .foregroundStyle(Theme.textMuted)
            .multilineTextAlignment(.trailing)
        } label: {
          HStack(spacing: 10) {
            Text(verbatim: event.timestamp.formatted(date: .omitted, time: .standard))
              .font(Theme.readout)
              .foregroundStyle(Theme.textMuted)
            Text(verbatim: event.kind)
              .font(Theme.readout)
              .foregroundStyle(Theme.textPrimary)
          }
        }
      }
    } header: {
      HStack {
        Text(verbatim: CountedText.text(DiagnosticsCopy.lastEvents(count: events.count)))
        Spacer()
        Button(DiagnosticsScreenCopy.revealInFinder) { menu.revealDiagnosticLog() }
        Button(DiagnosticsScreenCopy.reportProblem) { menu.reportProblem() }
        Button(DiagnosticsScreenCopy.clear) { confirmingClear = true }
          .accessibilityIdentifier("diagnostics.clear")
          .confirmationDialog(
            Text(DiagnosticsScreenCopy.clearTitle),
            isPresented: $confirmingClear,
            titleVisibility: .visible
          ) {
            Button(DiagnosticsScreenCopy.clear, role: .destructive) {
              coordinator.clearDiagnosticLog()
              Task { await reload() }
            }
            Button(CommonCopy.cancel, role: .cancel) {}
          } message: {
            Text(DiagnosticsScreenCopy.clearMessage)
          }
      }
    } footer: {
      Text(DiagnosticsScreenCopy.logContents)
    }
    .task { await reload() }
    .refreshOnActivate { Task { await reload() } }
  }

  private func reload() async {
    let url = MenuBarController.diagnosticLogURL
    let count = Self.shown
    events = await Task.detached(priority: .utility) {
      DiagnosticLog(fileURL: url).recent(count)
    }.value
  }
}
