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
  private var nextWaiter: UInt64 = 0
  private var cancelled: Set<UInt64> = []
  private var waiting: [UInt64: CheckedContinuation<Void, Never>] = [:]

  init() {}

  var isOpen: Bool { lock.withLock { opened } }

  func open() {
    let resumed: [CheckedContinuation<Void, Never>] = lock.withLock {
      opened = true
      defer { waiting = [:] }
      return Array(waiting.values)
    }
    resumed.forEach { $0.resume() }
  }

  func wait() async {
    let id = lock.withLock {
      defer { nextWaiter += 1 }
      return nextWaiter
    }
    await withTaskCancellationHandler {
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        let already = lock.withLock {
          if opened || cancelled.remove(id) != nil { return true }
          waiting[id] = continuation
          return false
        }
        if already { continuation.resume() }
      }
    } onCancel: {
      let parked: CheckedContinuation<Void, Never>? = lock.withLock {
        guard let continuation = waiting.removeValue(forKey: id) else {
          cancelled.insert(id)
          return nil
        }
        return continuation
      }
      parked?.resume()
    }
  }
}

final class Gate: @unchecked Sendable {
  private let lock = NSLock()
  private var opened = false
  private var waiting: [CheckedContinuation<Void, Never>] = []

  init() {}

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

final class GatedSealCipher: HistoryCipher, @unchecked Sendable {
  let sealHeld = Latch()
  private let marking = MarkingCipher()
  private let release = DispatchSemaphore(value: 0)
  private let lock = NSLock()
  private var armed = false

  func holdNextSeal() { lock.withLock { armed = true } }

  func releaseSeal() { release.signal() }

  func seal(_ plaintext: Data) throws -> Data {
    let hold = lock.withLock {
      defer { armed = false }
      return armed
    }
    if hold {
      sealHeld.open()
      release.wait()
    }
    return try marking.seal(plaintext)
  }

  func open(_ ciphertext: Data) throws -> Data { try marking.open(ciphertext) }
}

func voice(at host: UInt64) -> TrackDrain {
  TrackDrain(
    runs: [MeetingRun(start: host, samples: Array(repeating: 400, count: 160))], freshRuns: 1)
}

final class FakeTrackSource: MeetingTrackSource, @unchecked Sendable {
  enum StartMode {
    case succeed
    case fail(MeetingFailure)
    case gated
  }

  enum FinishMode { case immediate, gated, never }

  let startCalled = Latch()
  let stopCalled = Latch()
  let finishCalled = Latch()
  private let startGate = Gate()
  private let finishGate = Gate()
  private let startMode: StartMode
  private let finishMode: FinishMode
  private let lock = NSLock()
  private var drains: [TrackDrain]
  private var ended: (@Sendable () async -> Void)?
  private var calls = 0
  private var starts = 0
  private var stops = 0
  private var returned = false

  init(start: StartMode = .succeed, finish: FinishMode = .immediate, drains: [TrackDrain] = []) {
    startMode = start
    finishMode = finish
    self.drains = drains
  }

  var onEnded: (@Sendable () async -> Void)? {
    get { lock.withLock { ended } }
    set { lock.withLock { ended = newValue } }
  }

  var callbacks: Int {
    get { lock.withLock { calls } }
    set { lock.withLock { calls = newValue } }
  }

  var startCount: Int { lock.withLock { starts } }
  var stopCount: Int { lock.withLock { stops } }
  var finishedReturned: Bool { lock.withLock { returned } }

  func openStart() { startGate.open() }
  func openFinish() { finishGate.open() }

  func start() async throws {
    lock.withLock { starts += 1 }
    startCalled.open()
    switch startMode {
    case .succeed: return
    case .fail(let failure): throw failure
    case .gated: await startGate.wait()
    }
  }

  func stop() {
    lock.withLock { stops += 1 }
    stopCalled.open()
  }

  func finished() async {
    finishCalled.open()
    switch finishMode {
    case .immediate: break
    case .gated: await finishGate.wait()
    case .never:
      await Gate().wait()
      return
    }
    lock.withLock { returned = true }
  }

  func drain() -> TrackDrain {
    lock.withLock { drains.isEmpty ? TrackDrain() : drains.removeFirst() }
  }
}

final class CipherSource: @unchecked Sendable {
  let cipher: any HistoryCipher
  let called = Latch()
  private let gate: DispatchSemaphore?
  private let error: (any Error)?
  private let lock = NSLock()
  private var count = 0

  init(
    _ cipher: any HistoryCipher = MarkingCipher(), gated: Bool = false, error: (any Error)? = nil
  ) {
    self.cipher = cipher
    gate = gated ? DispatchSemaphore(value: 0) : nil
    self.error = error
  }

  var calls: Int { lock.withLock { count } }

  func open() { gate?.signal() }

  func call() throws -> any HistoryCipher {
    lock.withLock { count += 1 }
    called.open()
    gate?.wait()
    if let error { throw error }
    return cipher
  }
}

final class PowerHoldSpy: @unchecked Sendable {
  private let lock = NSLock()
  private let failing: Int32?
  private var held = 0
  private var released = 0
  private var willSleep: (@Sendable () async -> Void)?

  init(failing code: Int32? = nil) { failing = code }

  var holds: Int { lock.withLock { held } }
  var releases: Int { lock.withLock { released } }
  var onWillSleep: (@Sendable () async -> Void)? { lock.withLock { willSleep } }

  func hold(_ onWillSleep: @escaping @Sendable () async -> Void) -> MeetingPowerHold {
    lock.withLock {
      held += 1
      willSleep = onWillSleep
    }
    if let failing { return .failed(code: failing) }
    return .held(release: { [self] in lock.withLock { released += 1 } })
  }
}

final class MeetingHarness: @unchecked Sendable {
  private final class Record: @unchecked Sendable {
    let lock = NSLock()
    var statuses: [MeetingStatus] = []
    var waiting: [FakeTrackSource]
    var made = 0
    var madeAt: [UInt64] = []
    var watches = 0
    var filesWhenEnded: [String]?
    weak var watch: AnyObject?
    var onDeviceListChange: (@Sendable () -> Void)?

    init(_ mics: [FakeTrackSource]) { waiting = mics }

    func microphone(_ onEnded: @escaping @Sendable () async -> Void, at now: UInt64)
      -> FakeTrackSource
    {
      let mic = lock.withLock {
        made += 1
        madeAt.append(now)
        return waiting.isEmpty ? FakeTrackSource() : waiting.removeFirst()
      }
      mic.onEnded = onEnded
      return mic
    }

    func watched(_ onChange: @escaping @Sendable () -> Void) -> AnyObject {
      let token = NSObject()
      lock.withLock {
        watches += 1
        watch = token
        onDeviceListChange = onChange
      }
      return token
    }
  }

  let clock: TestClock
  let wallClock: Date
  let root: URL
  let store: MeetingStore
  let log: DiagnosticLog
  let power: PowerHoldSpy
  let ended: Latch
  let publishHeld: Latch
  let recorder: MeetingRecorder
  private let publishGate: Gate
  private let cipher: CipherSource
  private let record: Record

  init(
    cipher: CipherSource = .init(), mics: [FakeTrackSource] = [.init()],
    system: FakeTrackSource = .init(), power: PowerHoldSpy = .init(), recover: Bool = false,
    holdFirstPublish: Bool = false, root: URL = meetingTemporaryDirectory()
  ) {
    let clock = TestClock()
    let store = MeetingStore(directory: root)
    let log = DiagnosticLog(
      fileURL: meetingTemporaryDirectory().appendingPathComponent("diagnostics.json"))
    let record = Record(mics)
    let ended = Latch()
    let wallClock = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let publishHeld = Latch()
    let publishGate = Gate()
    self.publishHeld = publishHeld
    self.publishGate = publishGate
    self.clock = clock
    self.wallClock = wallClock
    self.ended = ended
    self.root = root
    self.store = store
    self.log = log
    self.power = power
    self.cipher = cipher
    self.record = record
    recorder = MeetingRecorder(
      .init(
        store: store,
        cipher: { try cipher.call() },
        makeMicrophone: { record.microphone($0, at: clock.now()) },
        makeSystemAudio: { system },
        holdPower: { power.hold($0) },
        watchDeviceList: { record.watched($0) },
        now: { clock.now() },
        sleep: { try await clock.sleep(for: $0) },
        wallClock: { wallClock },
        publish: { status in
          let first = record.lock.withLock {
            record.statuses.append(status)
            return record.statuses.count == 1
          }
          guard first, holdFirstPublish else { return }
          publishHeld.open()
          await publishGate.wait()
        },
        ended: {
          let files = Self.audioFiles(under: root)
          record.lock.withLock { record.filesWhenEnded = files }
          ended.open()
        },
        log: log,
        recover: recover))
  }

  var statuses: [MeetingStatus] { record.lock.withLock { record.statuses } }
  var micsMade: Int { record.lock.withLock { record.made } }
  var micsMadeAt: [UInt64] { record.lock.withLock { record.madeAt } }
  var deviceWatches: Int { record.lock.withLock { record.watches } }
  var deviceWatch: AnyObject? { record.lock.withLock { record.watch } }
  var audioFilesWhenEnded: [String]? { record.lock.withLock { record.filesWhenEnded } }

  var meetingDirectories: [URL] { Self.meetingDirectories(under: root) }

  func audioFiles() -> [String] { Self.audioFiles(under: root) }

  func releasePublish() { publishGate.open() }

  func fireDeviceListChange() { record.lock.withLock { record.onDeviceListChange }?() }

  private static func meetingDirectories(under root: URL) -> [URL] {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
    return names.filter { UUID(uuidString: $0) != nil }.map { root.appendingPathComponent($0) }
  }

  private static func audioFiles(under root: URL) -> [String] {
    guard let meeting = meetingDirectories(under: root).first else { return [] }
    let audio = meeting.appendingPathComponent("audio").path
    return ((try? FileManager.default.contentsOfDirectory(atPath: audio)) ?? []).sorted()
  }

  func kinds() -> [String] { log.recent(100).reversed().map(\.kind) }

  func detail(of kind: String) -> String? { log.recent(100).first { $0.kind == kind }?.detail }

  func header() async -> MeetingHeader? {
    let meetings = meetingDirectories
    guard meetings.count == 1, let id = UUID(uuidString: meetings[0].lastPathComponent) else {
      return nil
    }
    return await store.header(of: id, cipher: cipher.cipher)
  }

  func tick(_ duration: Duration) async {
    await clock.untilSleeping()
    clock.advance(by: duration)
    await clock.untilSleeping()
  }

  func settleSystemStart() async {
    let recorder = recorder
    _ = await value(of: Task { await recorder.systemStartSettled() })
  }

  func settleReopen() async {
    let recorder = recorder
    _ = await value(of: Task { await recorder.reopenSettled() })
  }
}
