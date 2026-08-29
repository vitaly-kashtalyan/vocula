import Foundation
import Testing

@testable import VoculaKit

@Suite("Insert ordering")
struct InsertOrderGateTests {
  @Test("session 2 waits for session 1 even when it is ready first")
  func laterSessionWaits() async {
    let gate = InsertOrderGate()
    let order = Recorder()

    async let second: Void = {
      await gate.wait(for: 2)
      await order.append(2)
      await gate.finish(2)
    }()
    try? await Task.sleep(for: .milliseconds(20))

    async let first: Void = {
      await gate.wait(for: 1)
      await order.append(1)
      await gate.finish(1)
    }()

    _ = await (first, second)
    #expect(await order.values == [1, 2])
  }

  @Test("a cancelled session releases the one behind it")
  func cancelledSessionReleasesTheQueue() async {
    let gate = InsertOrderGate()
    await gate.finish(1)
    #expect(await completes { await gate.wait(for: 2) })
  }

  @Test("a session that finishes out of order does not strand the one before it")
  func outOfOrderFinishDoesNotStrand() async {
    let gate = InsertOrderGate()
    await gate.finish(2)
    #expect(await completes { await gate.wait(for: 1) })
    await gate.finish(1)
    #expect(await completes { await gate.wait(for: 3) })
  }

  @Test("finishing 3, then 1, then 2 releases every waiter")
  func drainReleasesEveryWaiter() async {
    let gate = InsertOrderGate()
    await gate.finish(3)
    await gate.finish(1)
    await gate.finish(2)
    #expect(await completes { await gate.wait(for: 4) })
  }

  @Test("a session the cursor has already passed does not park for ever")
  func aPassedSessionDoesNotPark() async {
    let gate = InsertOrderGate()
    await gate.finish(2)
    await gate.finish(1)
    #expect(await completes { await gate.wait(for: 2) })
    #expect(await completes { await gate.wait(for: 3) })
  }

  @Test("sessions arriving in order do not block")
  func inOrderIsFree() async {
    let gate = InsertOrderGate()
    for session in 1...3 {
      #expect(await completes { await gate.wait(for: session) })
      await gate.finish(session)
    }
  }
}

private func completes(
  within deadline: Duration = .seconds(2),
  _ work: @escaping @Sendable () async -> Void
) async -> Bool {
  let race = BooleanRace()
  let workTask = Task {
    await work()
    race.resolve(true)
  }
  let timeoutTask = Task {
    try? await Task.sleep(for: deadline)
    guard !Task.isCancelled else { return }
    race.resolve(false)
  }
  let result = await withCheckedContinuation { race.install($0) }
  workTask.cancel()
  timeoutTask.cancel()
  return result
}

private final class BooleanRace: @unchecked Sendable {
  private let lock = NSLock()
  private var result: Bool?
  private var continuation: CheckedContinuation<Bool, Never>?

  func install(_ continuation: CheckedContinuation<Bool, Never>) {
    let immediate = lock.withLock { () -> Bool? in
      if let result { return result }
      self.continuation = continuation
      return nil
    }
    if let immediate { continuation.resume(returning: immediate) }
  }

  func resolve(_ value: Bool) {
    let continuation = lock.withLock { () -> CheckedContinuation<Bool, Never>? in
      guard result == nil else { return nil }
      result = value
      defer { self.continuation = nil }
      return self.continuation
    }
    continuation?.resume(returning: value)
  }
}

private actor Recorder {
  private(set) var values: [Int] = []
  func append(_ value: Int) { values.append(value) }
}
