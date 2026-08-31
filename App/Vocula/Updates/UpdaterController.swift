import Combine
import Foundation
import Sparkle

@MainActor
final class UpdaterController: NSObject, ObservableObject {
  static let disableArgument = "-VoculaNoUpdates"
  static let feedOverrideKey = "updates.feedURL"

  @Published private(set) var canCheck = false
  @Published private(set) var lastSuccessfulCheck: Date?

  var diagnose: ((String, String) -> Void)?
  var gestureIsOpen: () -> Bool = { false }

  private var controller: SPUStandardUpdaterController?

  nonisolated static func mayStart(isSecondCopy: Bool, argumentsDisableUpdates: Bool) -> Bool {
    guard !isSecondCopy else { return false }
    return !argumentsDisableUpdates
  }

  var automaticallyChecks: Bool {
    get { controller?.updater.automaticallyChecksForUpdates ?? false }
    set { controller?.updater.automaticallyChecksForUpdates = newValue }
  }

  func start() {
    let controller = SPUStandardUpdaterController(
      startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
    self.controller = controller
    controller.updater.publisher(for: \.canCheckForUpdates)
      .receive(on: DispatchQueue.main)
      .assign(to: &$canCheck)
  }

  func checkForUpdates() {
    controller?.updater.checkForUpdates()
  }
}

extension UpdaterController: SPUUpdaterDelegate {
  func feedURLString(for updater: SPUUpdater) -> String? {
    UserDefaults.standard.string(forKey: Self.feedOverrideKey)
  }

  func updater(
    _ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?
  ) {
    guard let error else {
      lastSuccessfulCheck = Date()
      return
    }
    let failure = error as NSError
    var detail = ["outcome=failed", "domain=\(failure.domain)", "code=\(failure.code)"]
    if let status = Self.handshakeStatus(of: failure) {
      detail.append("tls=\(status)")
    }
    diagnose?("update.failed", detail.joined(separator: " "))
  }

  // CFNetwork keeps the handshake's own OSStatus only here; every value of it
  // collapses into the same `localizedDescription`. Sparkle wraps the transport
  // error, so the key can be one level down.
  private static func handshakeStatus(of failure: NSError) -> Int? {
    let candidates = [failure, failure.userInfo[NSUnderlyingErrorKey] as? NSError].compactMap { $0 }
    for candidate in candidates {
      if let status = candidate.userInfo["_kCFStreamErrorCodeKey"] as? Int, status != 0 {
        return status
      }
    }
    return nil
  }

  func updater(
    _ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
    untilInvokingBlock installHandler: @escaping () -> Void
  ) -> Bool {
    guard gestureIsOpen() else { return false }
    Task { @MainActor in
      while gestureIsOpen() { try? await Task.sleep(for: .milliseconds(100)) }
      installHandler()
    }
    return true
  }
}
