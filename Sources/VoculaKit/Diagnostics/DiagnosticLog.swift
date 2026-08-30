import Foundation

public struct DiagnosticEvent: Equatable, Sendable, Codable {
  public let timestamp: Date
  public let kind: String
  public let detail: String
}

public final class DiagnosticLog: @unchecked Sendable {
  private let fileURL: URL
  private let maximumEvents: Int
  private let queue = DispatchQueue(label: "vocula.diagnostics")
  private var events: [DiagnosticEvent] = []

  public init(fileURL: URL, maximumEvents: Int = 2_000) {
    self.fileURL = fileURL
    self.maximumEvents = maximumEvents
    if let data = try? Data(contentsOf: fileURL),
      let decoded = try? JSONDecoder().decode([DiagnosticEvent].self, from: data)
    {
      events = decoded
    }
  }

  public func record(_ kind: String, _ detail: String, at timestamp: Date = Date()) {
    queue.sync {
      let safeKind = Self.allowedKinds.contains(kind) ? kind : "unknown"
      events.append(
        DiagnosticEvent(
          timestamp: timestamp, kind: safeKind,
          detail: Self.redact(detail)))
      if events.count > maximumEvents { events.removeFirst(events.count - maximumEvents) }
      persist()
    }
  }

  public func clear() {
    queue.sync {
      events = []
      persist()
    }
  }

  private func persist() {
    guard let data = try? JSONEncoder().encode(events) else { return }
    try? data.write(to: fileURL, options: .atomic)
    try? FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: fileURL.path)
  }

  public func recent(_ count: Int) -> [DiagnosticEvent] {
    queue.sync { Array(events.suffix(count).reversed()) }
  }

  public static func redact(_ detail: String) -> String {
    let fields = detail.split(separator: " ")
    guard fields.allSatisfy({ $0.contains("=") }) else { return "<dropped>" }
    return fields.map { field -> String in
      let parts = field.split(separator: "=", maxSplits: 1)
      guard parts.count == 2 else { return "<dropped>" }
      let key = String(parts[0])
      let value = String(parts[1])
      guard FieldShape.identifier.matches(key) else { return "<dropped>" }
      // An UNKNOWN key takes its own name down with it: the name is
      // caller-controlled text, and echoing it put three language codes into a
      // real log as `ru=<dropped> pl=<dropped>` — the one thing PRIVACY.md
      // promises this file never holds. An allow-listed key keeps its name,
      // because that name is ours and says which field went wrong.
      guard let shape = allowedKeys[key] else { return "<dropped>" }
      guard shape.matches(value) else { return "\(key)=<dropped>" }
      return "\(key)=\(value)"
    }.joined(separator: " ")
  }

  static func isKindAllowed(_ kind: String) -> Bool { allowedKinds.contains(kind) }

  static var allowedKindsForTesting: Set<String> { allowedKinds }

  private static let allowedKinds: Set<String> = [
    "session.start", "session.stop", "session.cancel", "session.failed",
    "gesture.longHold",
    "gesture.rapidRetap",
    "session.blocked",
    "audio.deviceMissing",
    "audio.deviceRefused",
    "audio.conversionFailed",
    "audio.startFailed",
    "audio.inputWentSilent",
    "audio.renderFailed",
    "audio.deviceLost",
    "audio.deviceWatchFailed",
    "audio.deviceListWatchFailed",
    "audio.failover",
    "language.detected",
    "guard.deny", "tap.rearm", "tap.install", "binding.saved",
    "model.download", "history.readFailed", "history.writeFailed",
    "history.retentionFailed",
    "permission.microphone",
    "app.launch",
    "insert.clipboardNotRestored",
    "audio.input",
    "session.noSpeech",
    "permission.accessibility",
    "audio.ready",
    "audio.deviceScan",
    "audio.live",
    "audio.meterOpen",
    "session.transcribed",
    "language.cycle",
  ]

  enum FieldShape {
    case number
    case identifier
    case flag

    func matches(_ value: String) -> Bool {
      switch self {
      case .number:
        let digits = value.hasPrefix("-") ? value.dropFirst() : value[...]
        return !digits.isEmpty && digits.allSatisfy { $0.isASCII && $0.isNumber }
      case .identifier:
        return !value.isEmpty && value.count <= 40
          && value.allSatisfy {
            $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_")
          }
      case .flag:
        return value == "true" || value == "false"
      }
    }
  }

  static let allowedKeys: [String: FieldShape] = [
    "listen": .flag,
    "session": .number,
    "ms": .number,
    "kbd": .number,
    "recording": .number,
    "count": .number,
    "attempt": .number,
    "bytes": .number,
    "rate": .number,
    "channels": .number,
    "reason": .identifier,
    "state": .identifier,
    "error": .identifier,
    "domain": .identifier,
    "code": .number,
    "tls": .number,
    "step": .identifier,
    "wanted": .identifier,
    "default": .identifier,
    "class": .identifier,
    "model": .identifier,
    "outcome": .identifier,
    "version": .identifier,
    "build": .number,
    "os": .identifier,
    "mac": .identifier,
    "secureInput": .flag,
    "ok": .flag,
    "auto": .flag,
    "langs": .number,
    "pk": .number,
    "pct": .number,
    "nextPct": .number,
    "selPct": .number,
    "gap": .number,
  ]
}
