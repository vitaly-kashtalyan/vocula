import Foundation

@testable import VoculaKit

final class MarkingCipher: HistoryCipher, @unchecked Sendable {
  static let mark = Data("SEALED".utf8)
  struct NotSealed: Error {}
  struct Refused: Error {}

  private let lock = NSLock()
  private var failures = 0

  init() {}

  func failNext(_ seals: Int) {
    lock.withLock { failures = seals }
  }

  func seal(_ plaintext: Data) throws -> Data {
    let fail = lock.withLock {
      defer { failures = max(0, failures - 1) }
      return failures > 0
    }
    if fail { throw Refused() }
    return Self.mark + plaintext
  }

  func open(_ ciphertext: Data) throws -> Data {
    guard ciphertext.starts(with: Self.mark) else { throw NotSealed() }
    return ciphertext.dropFirst(Self.mark.count)
  }
}

func meetingTemporaryDirectory() -> URL {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("vocula-meeting-\(UUID().uuidString)", isDirectory: true)
  try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

func plant(header: MeetingHeader, chunks: [String: Data], in root: URL) throws {
  let directory = root.appendingPathComponent(header.id.uuidString, isDirectory: true)
  try FileManager.default.createDirectory(
    at: directory.appendingPathComponent("audio"), withIntermediateDirectories: true)
  let sealed = MarkingCipher.mark + (try JSONEncoder().encode(header))
  try sealed.write(to: directory.appendingPathComponent("header.sealed"))
  for (path, bytes) in chunks {
    try bytes.write(to: directory.appendingPathComponent(path))
  }
}

final class TestClock: @unchecked Sendable {
  private struct Sleeper {
    let id: UInt64
    let deadline: UInt64
    let continuation: CheckedContinuation<Void, Error>
  }

  private let lock = NSLock()
  private var current: UInt64
  private var nextID: UInt64 = 0
  private var sleepers: [Sleeper] = []
  private var cancelledEarly: Set<UInt64> = []
  private var nextWaiter: UInt64 = 0
  private var cancelledWaiters: Set<UInt64> = []
  private var waiters: [(id: UInt64, count: Int, continuation: CheckedContinuation<Void, Never>)] =
    []

  init(start: UInt64 = 1_000_000_000) { current = start }

  func now() -> UInt64 { lock.withLock { current } }

  var parked: Int { lock.withLock { sleepers.count } }

  func sleep(for duration: Duration) async throws {
    let id = lock.withLock {
      defer { nextID += 1 }
      return nextID
    }
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, Error>) in
        let outcome: (cancelled: Bool, ready: [CheckedContinuation<Void, Never>]) = lock.withLock {
          if cancelledEarly.remove(id) != nil { return (true, []) }
          sleepers.append(
            Sleeper(
              id: id, deadline: HostTime.adding(current, Self.nanos(duration)),
              continuation: continuation))
          let count = sleepers.count
          let ready = waiters.filter { $0.count <= count }.map(\.continuation)
          waiters.removeAll { $0.count <= count }
          return (false, ready)
        }
        if outcome.cancelled { continuation.resume(throwing: CancellationError()) }
        outcome.ready.forEach { $0.resume() }
      }
    } onCancel: {
      let parked: CheckedContinuation<Void, Error>? = lock.withLock {
        guard let index = sleepers.firstIndex(where: { $0.id == id }) else {
          cancelledEarly.insert(id)
          return nil
        }
        return sleepers.remove(at: index).continuation
      }
      parked?.resume(throwing: CancellationError())
    }
  }

  func advance(by duration: Duration) {
    let due: [Sleeper] = lock.withLock {
      current = HostTime.adding(current, Self.nanos(duration))
      let due = sleepers.filter { $0.deadline <= current }
      sleepers.removeAll { $0.deadline <= current }
      return due
    }
    due.forEach { $0.continuation.resume() }
  }

  func untilSleeping(_ count: Int = 1) async {
    let id = lock.withLock {
      defer { nextWaiter += 1 }
      return nextWaiter
    }
    await withTaskCancellationHandler {
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        let satisfied = lock.withLock {
          if sleepers.count >= count || cancelledWaiters.remove(id) != nil { return true }
          waiters.append((id, count, continuation))
          return false
        }
        if satisfied { continuation.resume() }
      }
    } onCancel: {
      let parkedWaiter: CheckedContinuation<Void, Never>? = lock.withLock {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else {
          cancelledWaiters.insert(id)
          return nil
        }
        return waiters.remove(at: index).continuation
      }
      parkedWaiter?.resume()
    }
  }

  private static func nanos(_ duration: Duration) -> UInt64 {
    guard duration > .zero else { return 0 }
    let parts = duration.components
    let (whole, overflow) = UInt64(parts.seconds).multipliedReportingOverflow(by: 1_000_000_000)
    guard !overflow else { return .max }
    return HostTime.adding(whole, UInt64(parts.attoseconds / 1_000_000_000))
  }
}

func value<T: Sendable>(of task: Task<T, Never>) async -> T? {
  let box = ResultBox<T>()
  return await withTaskCancellationHandler {
    await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
      box.park(continuation)
      Task { box.finish(await task.value) }
    }
  } onCancel: {
    box.finish(nil)
  }
}

private final class ResultBox<T: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<T?, Never>?
  private var early: T??
  private var done = false

  func park(_ continuation: CheckedContinuation<T?, Never>) {
    let ready: T?? = lock.withLock {
      if let early { return early }
      self.continuation = continuation
      return nil
    }
    if let ready { continuation.resume(returning: ready) }
  }

  func finish(_ value: T?) {
    let taken: CheckedContinuation<T?, Never>? = lock.withLock {
      if done { return nil }
      done = true
      guard let continuation else {
        early = .some(value)
        return nil
      }
      self.continuation = nil
      return continuation
    }
    taken?.resume(returning: value)
  }
}

final class Latch: @unchecked Sendable {
  private let lock = NSLock()
  private var opened = false
  private var waiting: [CheckedContinuation<Void, Never>] = []

  init() {}

  var isOpen: Bool { lock.withLock { opened } }

  func open() {
    let resumed: [CheckedContinuation<Void, Never>] = lock.withLock {
      opened = true
      defer { waiting = [] }
      return waiting
    }
    resumed.forEach { $0.resume() }
  }

  func wait() async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      let already = lock.withLock {
        if opened { return true }
        waiting.append(continuation)
        return false
      }
      if already { continuation.resume() }
    }
  }
}
