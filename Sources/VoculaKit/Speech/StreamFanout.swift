import Foundation

public final class StreamFanout<Element: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]
  private let bufferingPolicy: AsyncStream<Element>.Continuation.BufferingPolicy

  public init(
    bufferingPolicy: AsyncStream<Element>.Continuation.BufferingPolicy = .bufferingNewest(1)
  ) {
    self.bufferingPolicy = bufferingPolicy
  }

  public func subscribe() -> AsyncStream<Element> {
    let id = UUID()
    let (stream, continuation) = AsyncStream<Element>.makeStream(
      bufferingPolicy: bufferingPolicy)
    continuation.onTermination = { [weak self] _ in
      guard let self else { return }
      self.lock.withLock { _ = self.continuations.removeValue(forKey: id) }
    }
    lock.withLock { continuations[id] = continuation }
    return stream
  }

  public func emit(_ value: Element) {
    let targets = lock.withLock { Array(continuations.values) }
    for continuation in targets { continuation.yield(value) }
  }

  public func finishAll() {
    let targets = lock.withLock { () -> [AsyncStream<Element>.Continuation] in
      let values = Array(continuations.values)
      continuations.removeAll()
      return values
    }
    for continuation in targets { continuation.finish() }
  }

  public var subscriberCount: Int { lock.withLock { continuations.count } }
}
