import Combine
import Foundation
import Sparkle

@MainActor
final class UpdaterController: NSObject, ObservableObject {
  static let disableArgument = "-VoculaNoUpdates"

  @Published private(set) var canCheck = false
  @Published private(set) var automaticallyChecks = false
  @Published private(set) var availableVersion: String? = UpdaterController.pretendedUpdate

  var diagnose: ((String, String) -> Void)?

  private var controller: SPUStandardUpdaterController?

  nonisolated static let pretendUpdateArgument = "-VoculaPretendUpdate"

  // A found update cannot be produced without a served feed, so the one state
  // no test could otherwise reach is substituted here. Second copies only, and
  // read from argv rather than UserDefaults: UserDefaults would also answer a
  // stale `defaults write`, and screenshots.sh runs as a second copy without
  // withholding Permissions, so a promo shot would carry a fake update row.
  nonisolated static var pretendedUpdate: String? {
    guard VoculaAppDelegate.isSecondCopy else { return nil }
    let arguments = ProcessInfo.processInfo.arguments
    guard let flag = arguments.firstIndex(of: pretendUpdateArgument) else { return nil }
    let value = arguments.index(after: flag)
    return value < arguments.endIndex ? arguments[value] : nil
  }

  nonisolated static func mayStart(isSecondCopy: Bool, argumentsDisableUpdates: Bool) -> Bool {
    guard !isSecondCopy else { return false }
    return !argumentsDisableUpdates
  }

  var lastSuccessfulCheck: Date? { controller?.updater.lastUpdateCheckDate }

  func setAutomaticallyChecks(_ on: Bool) {
    controller?.updater.automaticallyChecksForUpdates = on
  }

  func start() {
    guard controller == nil else { return }
    let controller = SPUStandardUpdaterController(
      startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
    self.controller = controller
    controller.updater.clearFeedURLFromUserDefaults()
    controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
    controller.updater.publisher(for: \.automaticallyChecksForUpdates)
      .assign(to: &$automaticallyChecks)
  }

  func checkForUpdates() {
    controller?.updater.checkForUpdates()
  }
}

extension UpdaterController: SPUUpdaterDelegate {
  // SUHost prefers UserDefaults over Info.plist for SUFeedURL, so any local
  // process could redirect the feed. The delegate outranks both.
  func feedURLString(for updater: SPUUpdater) -> String? {
    Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
  }

  // Closing the update window tells Sparkle nothing, so without holding what the
  // check found, a dismissed window leaves the screen reading "checked today"
  // over a version that is waiting.
  func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
    availableVersion = item.displayVersionString
  }

  func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
    availableVersion = nil
  }

  // Skip is a decision and Dismiss is a postponement, so only one of them takes
  // the row away. Neither reaches updaterDidNotFindUpdate: both abort the cycle
  // with a nil error, which didFinishUpdateCycleFor deliberately ignores.
  func updater(
    _ updater: SPUUpdater, userDidMake choice: SPUUserUpdateChoice,
    forUpdate updateItem: SUAppcastItem, state: SPUUserUpdateState
  ) {
    guard choice == .skip else { return }
    availableVersion = nil
  }

  // Sparkle relaunches with no arguments, so the request cannot travel in argv.
  func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
    Relaunch.request(.permissions)
  }

  func updater(
    _ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?
  ) {
    let failure = error as NSError?
    guard let failure, !Self.isRoutine(failure) else { return }
    var detail = ["outcome=failed", "domain=\(failure.domain)", "code=\(failure.code)"]
    if let status = Self.handshakeStatus(of: failure) {
      detail.append("tls=\(status)")
    }
    diagnose?("update.failed", detail.joined(separator: " "))
  }

  // Sparkle reports "there was no update" as an ERROR on this delegate method,
  // and does not log it itself. Recording it would put a line in the diagnostic
  // file on every routine check that found nothing.
  private static func isRoutine(_ failure: NSError) -> Bool {
    guard failure.domain == SUSparkleErrorDomain else { return false }
    return [
      SUError.noUpdateError,
      SUError.installationCanceledError,
      SUError.installationAuthorizeLaterError,
    ].map { Int($0.rawValue) }.contains(failure.code)
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

}
