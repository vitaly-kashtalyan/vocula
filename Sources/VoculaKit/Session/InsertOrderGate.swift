import Foundation

public actor InsertOrderGate {
  private struct Waiter {
    let token: UUID
    let continuation: CheckedContinuation<Void, Never>
  }
  private var next = 1
  private var waiting: [Int: Waiter] = [:]
  private var finished: Set<Int> = []

  public init() {}

  public func wait(for session: Int) async {
    guard session > next else { return }
    precondition(waiting[session] == nil, "session \(session) is already waiting")
    let token = UUID()
    await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        guard !Task.isCancelled else {
          continuation.resume()
          return
        }
        waiting[session] = Waiter(token: token, continuation: continuation)
      }
    } onCancel: {
      Task { await self.cancelWait(session, token: token) }
    }
  }

  public func finish(_ session: Int) {
    guard session >= next else { return }
    finished.insert(session)
    while finished.contains(next) {
      finished.remove(next)
      next += 1
      waiting.removeValue(forKey: next)?.continuation.resume()
    }
  }

  private func cancelWait(_ session: Int, token: UUID) {
    guard waiting[session]?.token == token else { return }
    waiting.removeValue(forKey: session)?.continuation.resume()
  }
}
