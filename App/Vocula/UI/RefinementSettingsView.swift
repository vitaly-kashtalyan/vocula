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

  var body: some View {
    Section {
      Toggle(RefinementScreenCopy.enable, isOn: $isEnabled)
        .disabled(status != .ready)
    } footer: {
      if status == .ready {
        Text(RefinementScreenCopy.explanation)
      } else {
        Text(RefinementScreenCopy.needsModel)
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
      .disabled(!isEnabled || status != .ready)
    } footer: {
      Text(RefinementScreenCopy.waitFooter)
    }

    Section {
      LabeledContent {
        switch status {
        case .ready:
          Text(verbatim: descriptor.licence)
        case .missing, .corrupted, .incomplete:
          if downloader.current == .qwenRefine2B {
            ProgressView(value: downloader.fraction[.qwenRefine2B] ?? 0).frame(width: 100)
          } else {
            Button(ModelScreenCopy.load) { Task { await load() } }
              .disabled(downloader.isDownloading)
          }
        }
      } label: {
        Text(verbatim: descriptor.displayName)
        Text(verbatim: descriptor.statusLine(status))
      }
      ModelDownloadFailure(message: downloader.lastError)
    } footer: {
      Text(RefinementScreenCopy.fallback)
    }
    .task {
      if downloader.statuses.isEmpty { await downloader.refreshStatuses() }
    }
  }

  private func load() async {
    await downloader.downloadOne(.qwenRefine2B)
    if status == .ready { await onModelsReady() }
  }
}
