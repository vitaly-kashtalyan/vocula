import AppKit
import SwiftUI
import VoculaKit

struct ModelPickerView: View {
  @ObservedObject var downloader: ModelDownloader
  @AppStorage(AppSettings.transcriptionModelKey)
  private var transcriptionModel = AppSettings.transcriptionModelDefault
  let onModelsReady: () async -> Void

  private var detectorNeedsAttention: Bool {
    (downloader.statuses[.speechDetector] ?? .missing) != .ready
  }

  var body: some View {
    ForEach(ModelManifest.transcriptionModelsByFamily, id: \.family) { group in
      Section {
        ForEach(group.models, id: \.self) { id in
          ModelPickerRow(
            descriptor: ModelManifest.descriptor(for: id),
            isSelected: id == transcriptionModel,
            status: downloader.statuses[id] ?? .missing,
            fraction: downloader.fraction[id] ?? 0,
            isDownloading: downloader.isDownloading,
            select: {
              transcriptionModel = id
              Task { await activateIfReady() }
            },
            load: { Task { await load(id) } })
        }
      } header: {
        Text(verbatim: group.family.title)
      }
    }
    Section {
      if detectorNeedsAttention {
        LabeledContent {
          ProgressView(value: downloader.fraction[.speechDetector] ?? 0)
            .frame(width: 100)
        } label: {
          Text(ModelScreenCopy.speechDetector)
          Text(ModelScreenCopy.requiredForTranscription)
        }
      }
      if !downloader.allReady {
        HStack {
          Button(ModelScreenCopy.downloadMissing) {
            Task {
              await downloader.downloadMissing()
              if downloader.allReady { await onModelsReady() }
            }
          }
          .disabled(downloader.isDownloading)
          if downloader.isDownloading {
            Button(CommonCopy.cancel) { downloader.cancel() }
          }
        }
      }
      if let error = downloader.lastError {
        Text(verbatim: error).foregroundStyle(.red)
      }
    } footer: {
      Text(ModelScreenCopy.fullyLocal)
    }
    AttributionSection()
      .task {
        if downloader.statuses.isEmpty { await downloader.refreshStatuses() }
      }
  }

  private func load(_ id: ModelID) async {
    await downloader.downloadOne(id)
    await activateIfReady()
  }

  private func activateIfReady() async {
    guard downloader.statuses[transcriptionModel] == .ready else { return }
    await onModelsReady()
  }
}

private struct ModelPickerRow: View {
  let descriptor: ModelDescriptor
  let isSelected: Bool
  let status: ModelStatus
  let fraction: Double
  let isDownloading: Bool
  let select: () -> Void
  let load: () -> Void

  var body: some View {
    LabeledContent {
      switch status {
      case .ready:
        EmptyView()
      case .missing, .corrupted, .incomplete:
        if isSelected, isDownloading {
          ProgressView(value: fraction).frame(width: 100)
        } else {
          Button(ModelScreenCopy.load, action: load)
            .disabled(!isSelected || isDownloading)
        }
      }
    } label: {
      Button(action: select) {
        HStack {
          Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
            .foregroundStyle(isSelected ? Theme.accentText : Color.secondary)
          Text(verbatim: descriptor.displayName)
        }
      }
      .buttonStyle(.plain)
      .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
      Text(verbatim: subtitle)
    }
  }

  private var subtitle: String {
    let size = descriptor.byteSize.formatted(.byteCount(style: .file).locale(.interface))
    switch status {
    case .ready: return size
    case .missing: return String(localized: ModelScreenCopy.notDownloaded(size))
    case .incomplete: return String(localized: ModelScreenCopy.partlyDownloaded(size))
    case .corrupted:
      return String(localized: ModelScreenCopy.damaged(size, descriptor.version))
    }
  }
}

private struct AttributionSection: View {
  var body: some View {
    Section {
      ForEach(ModelManifest.current, id: \.id) { model in
        LabeledContent {
          Text(verbatim: model.licence)
        } label: {
          Text(verbatim: model.displayName)
          Text(verbatim: model.version)
        }
      }
      ForEach(presentFamilies, id: \.self) { family in
        LabeledContent {
          Text(verbatim: family.engineCredit)
        } label: {
          Text(ModelScreenCopy.engineCredit(family.title))
            .accessibilityIdentifier("models.engineCredit.\(family.rawValue)")
        }
      }
      if let licences = Self.bundledLicences {
        Button(ModelScreenCopy.fullLicenceTexts) { NSWorkspace.shared.open(licences) }
      }
    } header: {
      Text(ModelScreenCopy.licences)
    }
  }

  private static var bundledLicences: URL? {
    Bundle.main.url(forResource: "THIRD-PARTY", withExtension: "txt")
  }

  private var presentFamilies: [ModelFamily] {
    ModelFamily.allCases.filter { family in
      ModelManifest.current.contains { $0.family == family }
    }
  }
}
