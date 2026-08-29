import Foundation

public struct ClipboardRestore: Equatable, Sendable {
  let previous: ClipboardSnapshot
  let ourChangeCount: Int
}

public enum InsertOutcome: Equatable, Sendable {
  case sent(ClipboardRestore)
  case skippedEmpty
  case failedLocally
}

private final class PendingRestore: @unchecked Sendable {
  private let lock = NSLock()
  private var owed: ClipboardRestore?

  func owe(_ restore: ClipboardRestore) {
    lock.withLock { owed = restore }
  }

  func take() -> ClipboardRestore? {
    lock.withLock {
      defer { owed = nil }
      return owed
    }
  }

  func takeIfStillOwed(_ restore: ClipboardRestore) -> Bool {
    lock.withLock {
      guard owed == restore else { return false }
      owed = nil
      return true
    }
  }
}

public struct TextInserter: Sendable {
  private let pending = PendingRestore()
  private let clipboard: Clipboard
  private let paste: PasteSending
  private let timings: Timings
  private let sleep: @Sendable (Duration) async -> Void
  private let recordClipboardNotRestored: @Sendable () -> Void

  public init(
    clipboard: Clipboard, paste: PasteSending, timings: Timings = .default,
    sleep: @escaping @Sendable (Duration) async -> Void = {
      try? await Task.sleep(for: $0)
    },
    recordClipboardNotRestored: @escaping @Sendable () -> Void = {}
  ) {
    self.clipboard = clipboard
    self.paste = paste
    self.timings = timings
    self.sleep = sleep
    self.recordClipboardNotRestored = recordClipboardNotRestored
  }

  @MainActor
  public func insert(_ text: String, approval: InsertApproval) async -> InsertOutcome {
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return .skippedEmpty
    }
    settleOwedRestore()
    let previous = clipboard.snapshot()
    let write = clipboard.write(text, concealed: true, transient: true)
    let ourChangeCount: Int
    switch write {
    case .written(let changeCount):
      ourChangeCount = changeCount
    case .failed(let afterChangeCount):
      if let count = afterChangeCount, clipboard.changeCount == count {
        _ = putBack(previous)
      }
      return .failedLocally
    }
    guard paste.sendPaste() else {
      if clipboard.changeCount == ourChangeCount { _ = putBack(previous) }
      return .failedLocally
    }
    let restore = ClipboardRestore(previous: previous, ourChangeCount: ourChangeCount)
    pending.owe(restore)
    return .sent(restore)
  }

  @MainActor
  public func restoreClipboard(_ restore: ClipboardRestore) async -> Bool {
    await sleep(timings.clipboardRestore)
    guard pending.takeIfStillOwed(restore) else { return false }
    guard clipboard.changeCount == restore.ourChangeCount else {
      return false
    }
    return putBack(restore.previous)
  }

  @MainActor
  public func settleOwedRestore() {
    guard let owed = pending.take(),
      clipboard.changeCount == owed.ourChangeCount
    else { return }
    _ = putBack(owed.previous)
  }

  @MainActor
  private func putBack(_ previous: ClipboardSnapshot) -> Bool {
    guard !previous.abandoned else {
      clipboard.restore(ClipboardSnapshot(items: [], changeCount: previous.changeCount))
      recordClipboardNotRestored()
      return false
    }
    guard clipboard.restore(previous) != nil else {
      recordClipboardNotRestored()
      return false
    }
    return true
  }
}
