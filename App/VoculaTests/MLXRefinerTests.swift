import Foundation
import MLX
import MLXLMCommon
import Synchronization
import Testing
import VoculaKit

@testable import Vocula

@Suite("MLXRefiner without a model")
struct MLXRefinerStreamTests {
  private static func events(_ items: [Generation], finishes: Bool = true)
    -> AsyncThrowingStream<Generation, Error>
  {
    AsyncThrowingStream { continuation in
      for item in items { continuation.yield(item) }
      if finishes { continuation.finish() }
    }
  }

  private static func info(_ reason: GenerateStopReason) -> Generation {
    .info(
      GenerateCompletionInfo(
        promptTokenCount: 10, generationTokenCount: 2, promptTime: 0.1, generationTime: 0.1,
        stopReason: reason))
  }

  @Test("an answer that ended on its own stop token is returned whole")
  func finishedAnswer() async throws {
    let text = try await MLXRefiner.text(
      of: Self.events([.chunk("Это "), .chunk("работает."), Self.info(.stop)]))
    #expect(text == "Это работает.")
  }

  @Test("an answer cut at the token cap throws instead of returning its head")
  func tokenCapIsAFailure() async {
    await #expect(throws: RefinementError.tokenCap) {
      try await MLXRefiner.text(of: Self.events([.chunk("Это "), Self.info(.length)]))
    }
  }

  @Test("an answer whose stream ended without completion info throws")
  func cutStreamIsAFailure() async {
    await #expect(throws: TranscriptionError.timedOut) {
      try await MLXRefiner.text(of: Self.events([.chunk("Это ")]))
    }
    await #expect(throws: TranscriptionError.timedOut) {
      try await MLXRefiner.text(of: Self.events([.chunk("Это "), Self.info(.cancelled)]))
    }
  }

  @Test("a generation still running at the deadline throws timedOut, not what it had so far")
  func deadlineOnAStream() async {
    let endless = Self.events([.chunk("Это ")], finishes: false)
    await #expect(throws: TranscriptionError.timedOut) {
      try await withBound(.milliseconds(50)) { try await MLXRefiner.text(of: endless) }
    }
  }

  @Test("a load that failed is not retried by the next dictation, only after an unload")
  func failedLoadIsRememberedOnce() async throws {
    let empty = FileManager.default.temporaryDirectory
      .appendingPathComponent("no-model-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: empty) }
    let failures = Counter()
    let refiner = MLXRefiner(
      directory: empty, modelID: "none", loadFailed: { failures.count.add(1, ordering: .relaxed) })

    for _ in 0..<3 {
      await #expect(throws: TranscriptionError.modelNotLoaded) {
        try await refiner.refine("Ну вот, это работает", deadline: .seconds(10))
      }
    }
    #expect(failures.count.load(ordering: .relaxed) == 1)

    await refiner.unload()
    await refiner.prewarm()
    await #expect(throws: TranscriptionError.modelNotLoaded) {
      try await refiner.refine("Ну вот, это работает", deadline: .seconds(10))
    }
    #expect(failures.count.load(ordering: .relaxed) == 2)
  }

  private static func emptyDirectory() throws -> URL {
    let empty = FileManager.default.temporaryDirectory
      .appendingPathComponent("no-model-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
    return empty
  }

  private static let spoken = "Ну вот, это работает"

  @Test("a second prewarm while the first load runs starts no second load")
  func prewarmTwiceLoadsOnce() async throws {
    let empty = try Self.emptyDirectory()
    defer { try? FileManager.default.removeItem(at: empty) }
    let held = HeldLoad()
    let refiner = MLXRefiner(directory: empty, modelID: "none", loadFailed: held.failing)

    await refiner.prewarm()
    await refiner.prewarm()
    await held.waitForLoads(1)
    #expect(held.loads == 1)
    held.letGo()
    await #expect(throws: TranscriptionError.modelNotLoaded) {
      try await refiner.refine(Self.spoken, deadline: .seconds(10))
    }
    #expect(held.loads == 1)
  }

  @Test("a dictation arriving during the load waits for that load instead of starting its own")
  func refineDuringALoadShares() async throws {
    let empty = try Self.emptyDirectory()
    defer { try? FileManager.default.removeItem(at: empty) }
    let held = HeldLoad()
    let refiner = MLXRefiner(directory: empty, modelID: "none", loadFailed: held.failing)

    await refiner.prewarm()
    await held.waitForLoads(1)
    let dictation = Task { try await refiner.refine(Self.spoken, deadline: .seconds(10)) }
    try await Task.sleep(for: .milliseconds(100))
    #expect(held.loads == 1)
    held.letGo()
    await #expect(throws: TranscriptionError.modelNotLoaded) { try await dictation.value }
    #expect(held.loads == 1)
  }

  @Test("an unload during a load waits for it, and the next dictation loads afresh")
  func unloadDuringALoadWaits() async throws {
    let empty = try Self.emptyDirectory()
    defer { try? FileManager.default.removeItem(at: empty) }
    let held = HeldLoad()
    let refiner = MLXRefiner(directory: empty, modelID: "none", loadFailed: held.failing)

    await refiner.prewarm()
    await held.waitForLoads(1)
    let unloaded = Counter()
    let unloading = Task {
      await refiner.unload()
      unloaded.count.add(1, ordering: .relaxed)
    }
    try await Task.sleep(for: .milliseconds(100))
    #expect(unloaded.count.load(ordering: .relaxed) == 0)
    held.letGo()
    await unloading.value

    let next = Task { try await refiner.refine(Self.spoken, deadline: .seconds(10)) }
    await held.waitForLoads(2)
    held.letGo()
    await #expect(throws: TranscriptionError.modelNotLoaded) { try await next.value }
    #expect(held.loads == 2)
  }

  @Test("switched off and on again during a load, the dictation uses the second load")
  func offThenOnDuringALoad() async throws {
    let empty = try Self.emptyDirectory()
    defer { try? FileManager.default.removeItem(at: empty) }
    let held = HeldLoad()
    let refiner = MLXRefiner(directory: empty, modelID: "none", loadFailed: held.failing)

    await refiner.prewarm()
    await held.waitForLoads(1)
    let unloading = Task { await refiner.unload() }
    try await Task.sleep(for: .milliseconds(50))
    await refiner.prewarm()
    await held.waitForLoads(2)
    held.letGo()
    held.letGo()
    await unloading.value
    await #expect(throws: TranscriptionError.modelNotLoaded) {
      try await refiner.refine(Self.spoken, deadline: .seconds(10))
    }
    #expect(held.loads == 2)
  }

  @Test("the token budget covers everything the kit would accept, up to three times the input")
  func budgetFollowsTheInput() {
    for inputTokens in [3, 400, 545, 2000] {
      #expect(MLXRefiner.tokenBudget(forInputTokens: inputTokens) >= inputTokens * 3)
    }
  }
}

private final class Counter: Sendable {
  let count = Atomic<Int>(0)
}

private final class HeldLoad: Sendable {
  private let started = Atomic<Int>(0)
  private let gate = DispatchSemaphore(value: 0)

  var loads: Int { started.load(ordering: .relaxed) }

  func failing() {
    started.add(1, ordering: .relaxed)
    _ = gate.wait(timeout: .now() + .seconds(5))
  }

  func letGo() { gate.signal() }

  func waitForLoads(_ count: Int) async {
    for _ in 0..<500 where loads < count {
      try? await Task.sleep(for: .milliseconds(10))
    }
  }
}

@Suite("MLXRefiner on the real model", .serialized)
struct MLXRefinerTests {
  static var installed: URL? {
    let store = ModelStore.app()
    return store.status(of: .qwenRefine2B) == .ready ? store.url(for: .qwenRefine2B) : nil
  }

  static func refiner(
    tokenBudget: @escaping @Sendable (Int) -> Int = MLXRefiner.tokenBudget
  )
    throws -> MLXRefiner
  {
    MLXRefiner(
      directory: try #require(installed), modelID: ModelID.qwenRefine2B.rawValue,
      tokenBudget: tokenBudget)
  }

  @Test(
    "it cleans a Russian transcript and answers with text, not with a reply",
    .enabled(if: installed != nil))
  func cleansRealRussianSpeech() async throws {
    let refiner = try Self.refiner()
    let spoken = "Ну вот, значит, на сервере это работает, и поэтому также появилась такая задача"
    let out = try await refiner.refine(spoken, deadline: .seconds(30))

    #expect(!out.isEmpty)
    #expect(out.count < spoken.count * 3)
    #expect(out.contains { $0.isCyrillic })
    #expect(!out.contains("transcript"))

    let asked =
      "Что как мне тогда сохранить файл? Я не хочу терять старый формат. Как мне это сделать?"
    let answer = try await refiner.refine(asked, deadline: .seconds(30))
    #expect(answer.contains("?"))
    #expect(answer.count < asked.count * 2)
  }

  @Test("the real stream reports the token cap, and it throws", .enabled(if: installed != nil))
  func tokenCapOnTheRealModel() async throws {
    let refiner = try Self.refiner(tokenBudget: { _ in 3 })
    await #expect(throws: RefinementError.tokenCap) {
      try await refiner.refine(
        "Ну вот, значит, на сервере это работает, и поэтому появилась такая задача",
        deadline: .seconds(30))
    }
  }

  @Test(
    "a pass cut by its deadline throws instead of pasting a head", .enabled(if: installed != nil))
  func deadlineOnTheRealModel() async throws {
    let refiner = try Self.refiner()
    _ = try await refiner.refine(
      "Ну вот, значит, это работает, проверка связи", deadline: .seconds(30))
    await #expect(throws: TranscriptionError.timedOut) {
      try await refiner.refine(Self.long, deadline: .milliseconds(300))
    }
  }

  private static let long = """
    Ну вот, значит, я сегодня опять сел разбираться с этой сборкой, и она снова упала на подписи. \
    Потом я полез в настройки ключей, поменял сертификат, перезапустил машину, и всё равно та же ошибка. \
    Кстати, на прошлой неделе такого не было, значит, что-то сломалось после обновления системы. \
    Я проверил логи, там написано, что не может построить цепочку до корневого сертификата. \
    Ещё я заметил, что тесты интерфейса стали падать на первом запуске, а на втором проходят. \
    И отдельно надо разобраться, почему загрузка модели иногда занимает десять секунд, а иногда одну. \
    В общем, план такой: сначала добавить промежуточный сертификат, потом прогнать тесты, потом замерить загрузку.
    """

  private static func weightsAreGone() async -> Bool {
    for _ in 0..<50 {
      let now = Memory.snapshot()
      if now.activeMemory + now.cacheMemory < 200_000_000 { return true }
      try? await Task.sleep(for: .milliseconds(100))
    }
    return false
  }

  @Test(
    "unloading while a pass runs lets the pass end, then gives the weights back",
    .enabled(if: installed != nil))
  func unloadDuringAPass() async throws {
    let refiner = try Self.refiner()
    _ = try await refiner.refine(
      "Ну вот, значит, это работает, проверка связи", deadline: .seconds(30))
    let pass = Task { try await refiner.refine(Self.long, deadline: .seconds(30)) }
    try await Task.sleep(for: .milliseconds(300))
    await refiner.unload()

    if case .failure(let error) = await pass.result {
      #expect(error is TranscriptionError || error is RefinementError, "\(error)")
    }
    #expect(await Self.weightsAreGone())
  }

  @Test(
    "a load that failed, an unload, then the files arriving: the next pass loads them",
    .enabled(if: installed != nil))
  func failedLoadThenUnloadThenSuccess() async throws {
    let source = try #require(Self.installed)
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("arriving-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let failures = Counter()
    let refiner = MLXRefiner(
      directory: directory, modelID: ModelID.qwenRefine2B.rawValue,
      loadFailed: { failures.count.add(1, ordering: .relaxed) })
    let spoken = "Ну вот, значит, это работает, проверка связи"

    await #expect(throws: TranscriptionError.modelNotLoaded) {
      try await refiner.refine(spoken, deadline: .seconds(30))
    }
    for name in ModelManifest.descriptor(for: .qwenRefine2B).contents {
      try FileManager.default.createSymbolicLink(
        at: directory.appendingPathComponent(name),
        withDestinationURL: source.appendingPathComponent(name))
    }
    await #expect(throws: TranscriptionError.modelNotLoaded) {
      try await refiner.refine(spoken, deadline: .seconds(30))
    }

    await refiner.unload()
    let out = try await refiner.refine(spoken, deadline: .seconds(30))
    #expect(!out.isEmpty)
    #expect(failures.count.load(ordering: .relaxed) == 1)
    await refiner.unload()
    #expect(await Self.weightsAreGone())
  }

  @Test(
    "two cold dictations share one load, and unloading gives the weights back",
    .enabled(if: installed != nil))
  func oneLoadThenUnload() async throws {
    let refiner = try Self.refiner()
    Memory.peakMemory = 0
    async let first = refiner.refine(
      "Ну вот, значит, это работает, проверка связи", deadline: .seconds(30))
    async let second = refiner.refine(
      "Ну вот, значит, это тоже работает, проверка", deadline: .seconds(30))
    _ = try await (first, second)
    #expect(Memory.activeMemory > 1_000_000_000)
    #expect(Memory.peakMemory < 3_000_000_000)

    await refiner.unload()
    let unloaded = Memory.snapshot()
    #expect(unloaded.activeMemory + unloaded.cacheMemory < 200_000_000)
  }
}

extension Character {
  fileprivate var isCyrillic: Bool {
    unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) }
  }
}
