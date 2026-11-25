import Combine
import Foundation
import VoculaKit

@MainActor
final class MeetingDiarizerFetcher {
  let store: ModelStore
  let downloader: ModelDownloader
  private(set) var running: Task<Void, Never>?

  init(
    store: ModelStore = .app(manifest: [ModelManifest.descriptor(for: .speakerDiarizer)]),
    configuration: URLSessionConfiguration = .default,
    isSecondCopy: Bool = VoculaAppDelegate.isSecondCopy
  ) {
    self.store = store
    downloader = ModelDownloader(
      store: store, requiredModels: { [.speakerDiarizer] }, configuration: configuration,
      isWanted: { _ in true }, isSecondCopy: isSecondCopy, allowsExpensiveNetworks: true)
  }

  func fetch(
    log: DiagnosticLog?, progress: @escaping @MainActor (Int?) -> Void,
    onReady: @escaping @MainActor () async -> Void
  ) {
    guard running == nil else { return }
    downloader.diagnose = { log?.record($0, $1) }
    let watch = downloader.$fraction.combineLatest(downloader.$isDownloading).sink {
      fraction, downloading in
      progress(downloading ? Int((fraction[.speakerDiarizer] ?? 0) * 100) : nil)
    }
    running = Task {
      let downloaded = await downloader.downloadAutomatically()
      watch.cancel()
      running = nil
      if downloaded { await onReady() }
    }
  }
}
