import Foundation
import VoculaKit

@MainActor
final class MeetingDiarizerFetcher {
  let store: ModelStore
  private let downloader: ModelDownloader
  private(set) var running: Task<Void, Never>?

  init(
    store: ModelStore = .app(manifest: [ModelManifest.descriptor(for: .speakerDiarizer)]),
    configuration: URLSessionConfiguration = .default,
    isSecondCopy: Bool = VoculaAppDelegate.isSecondCopy
  ) {
    self.store = store
    downloader = ModelDownloader(
      store: store, requiredModels: { [.speakerDiarizer] }, configuration: configuration,
      isWanted: { _ in true }, isSecondCopy: isSecondCopy)
  }

  func fetch(log: DiagnosticLog?) {
    guard running == nil else { return }
    downloader.diagnose = { log?.record($0, $1) }
    running = Task {
      _ = await downloader.downloadAutomatically()
      running = nil
    }
  }
}
