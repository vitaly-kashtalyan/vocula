import Foundation
import Testing

@testable import Vocula

@Suite("Bounded wait")
struct BoundedWaitTests {
  @Test("uncancellable work does not outrun the bound")
  func boundHoldsAgainstUncancellableWork() async {
    let started = ContinuousClock.now
    await withBound(.milliseconds(200)) {
      await Task { try? await Task.sleep(for: .seconds(5)) }.value
    }
    let elapsed = ContinuousClock.now - started
    #expect(
      elapsed < .seconds(2),
      "the bound was fiction: waited \(elapsed) for work bounded at 200 ms")
  }

  @Test("work that finishes early returns early")
  func fastWorkReturnsImmediately() async {
    let started = ContinuousClock.now
    await withBound(.seconds(5)) {
      try? await Task.sleep(for: .milliseconds(20))
    }
    #expect(ContinuousClock.now - started < .seconds(1))
  }

  @Test("both racers completing does not resume twice")
  func bothRacersAreSafe() async {
    for _ in 0..<20 {
      await withBound(.milliseconds(10)) {
        try? await Task.sleep(for: .milliseconds(10))
      }
    }
  }
}

@Suite("What the bound leaves behind")
struct BoundedWaitCancellationTests {
  private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var raised = false
    func raise() { lock.withLock { raised = true } }
    var isRaised: Bool { lock.withLock { raised } }
  }

  @Test("work that outran the bound is cancelled rather than left running")
  func theLoserIsCancelled() async {
    let cancelled = Flag()
    await withBound(.milliseconds(100)) {
      await withTaskCancellationHandler {
        try? await Task.sleep(for: .seconds(5))
      } onCancel: {
        cancelled.raise()
      }
    }
    try? await Task.sleep(for: .milliseconds(100))
    #expect(cancelled.isRaised, "the bound returned but left its work running")
  }
}
