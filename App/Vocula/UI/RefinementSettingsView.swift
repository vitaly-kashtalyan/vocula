import SwiftUI
import VoculaKit

struct RefinementSettingsView: View {
  @ObservedObject var downloader: ModelDownloader
  let onModelsReady: () async -> Void
  @AppStorage(AppSettings.refineEnabledKey) private var isEnabled = false
  @AppStorage(AppSettings.refineMaximumWaitKey) private var maximumWait = AppSettings
    .refineMaximumWaitDefault

  private var status: ModelStatus { downloader.statuses[.qwenRefine2B] ?? .missing }
  private var descriptor: ModelDescriptor { ModelManifest.descriptor(for: .qwenRefine2B) }

  private var download: RefinementSwitch.Download {
    if downloader.current == .qwenRefine2B { return .thisModel }
    return downloader.isDownloading ? .otherModel : .idle
  }

  private var footer: RefinementSwitch.Footer {
    RefinementSwitch.footer(intent: isEnabled, model: status)
  }

  private var footerHint: Text {
    switch footer {
    case .explanation: Text(RefinementScreenCopy.explanation)
    case .explanationOffersDownload: Text(RefinementScreenCopy.offersDownload)
    case .pastesAsRecognised: Text(RefinementScreenCopy.pastesAsRecognised)
    }
  }

  private var intent: Binding<Bool> {
    Binding(
      get: { isEnabled },
      set: { turnedOn in
        isEnabled = turnedOn
        switch RefinementSwitch.toggled(on: turnedOn, model: status, download: download) {
        case .startDownload: Task { await load() }
        case .cancelDownload: downloader.cancel()
        case nil: break
        }
      })
  }

  var body: some View {
    Section {
      Toggle(RefinementScreenCopy.enable, isOn: intent)
        .accessibilityHint(footerHint)
    } footer: {
      switch footer {
      case .explanation:
        Text(RefinementScreenCopy.explanation)
      case .explanationOffersDownload:
        Text(RefinementScreenCopy.explanation)
        Text(RefinementScreenCopy.offersDownload)
      case .pastesAsRecognised:
        Text(RefinementScreenCopy.pastesAsRecognised)
      }
    }

    Section {
      Picker(selection: $maximumWait) {
        Text(RefinementScreenCopy.waitTen).tag(10)
        Text(RefinementScreenCopy.waitThirty).tag(30)
        Text(RefinementScreenCopy.waitSixty).tag(60)
      } label: {
        Text(RefinementScreenCopy.waitLabel)
      }
      .disabled(!RefinementSwitch.isActive(intent: isEnabled, model: status))
    } footer: {
      Text(RefinementScreenCopy.waitFooter)
    }

    Section {
      LabeledContent {
        switch status {
        case .ready:
          Text(verbatim: descriptor.licence)
        case .missing, .corrupted, .incomplete:
          if download == .thisModel {
            ProgressView(value: downloader.fraction[.qwenRefine2B] ?? 0).frame(width: 100)
          } else if isEnabled {
            Button(ModelScreenCopy.load) { Task { await load() } }
              .disabled(downloader.isDownloading)
          }
        }
      } label: {
        Text(verbatim: descriptor.displayName)
        Text(verbatim: descriptor.statusLine(status))
      }
      ModelDownloadFailure(message: isEnabled ? downloader.lastError : nil)
    } footer: {
      Text(RefinementScreenCopy.fallback)
    }
    .onChange(of: downloader.lastError) { _, message in
      if isEnabled, let message { Announce.say(message) }
    }
    .task {
      if downloader.statuses.isEmpty { await downloader.refreshStatuses() }
    }
  }

  private func load() async {
    if await downloader.downloadOne(.qwenRefine2B), isEnabled { await onModelsReady() }
  }
}
