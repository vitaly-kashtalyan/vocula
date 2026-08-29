import Foundation

enum AudioDiagnostics {
  private static let lock = NSLock()
  nonisolated(unsafe) private static var sink: (@Sendable (String, String) -> Void)?

  static func setSink(_ sink: (@Sendable (String, String) -> Void)?) {
    lock.withLock { Self.sink = sink }
  }

  static func record(_ kind: String, _ detail: String) {
    lock.withLock { Self.sink }?(kind, detail)
  }

  static let slowScanMilliseconds = 50
  static let slowOpenMilliseconds = 400

  static func milliseconds(since start: DispatchTime) -> Int {
    Int((DispatchTime.now().uptimeNanoseconds &- start.uptimeNanoseconds) / 1_000_000)
  }
}
