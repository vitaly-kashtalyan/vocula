import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import Tokenizers
import VoculaKit

actor MLXRefiner: TextRefining {
  nonisolated let modelID: String
  private let directory: URL
  private let tokenBudget: @Sendable (Int) -> Int
  private let loadFailed: @Sendable () -> Void
  private var load: Task<ModelContainer, Error>?

  init(
    directory: URL, modelID: String,
    tokenBudget: @escaping @Sendable (Int) -> Int = MLXRefiner.tokenBudget,
    loadFailed: @escaping @Sendable () -> Void = {}
  ) {
    self.directory = directory
    self.modelID = modelID
    self.tokenBudget = tokenBudget
    self.loadFailed = loadFailed
  }

  static let shortInputAllowance = 32

  static func tokenBudget(forInputTokens count: Int) -> Int {
    Int(Double(count) * RefinementPolicy.longestAcceptableRatio) + shortInputAllowance
  }

  func refine(_ text: String, deadline: Duration) async throws -> String {
    let load = loading()
    let budget = tokenBudget
    return try await withBound(deadline) {
      let container = try await load.value
      try Task.checkCancellation()
      let inputTokens = await container.tokenizer.encode(text: text, addSpecialTokens: false).count
      let session = ChatSession(
        container, generateParameters: .init(maxTokens: budget(inputTokens), temperature: 0))
      return try await Self.text(of: session.streamDetails(to: RefinePrompt.rendered(text)))
    }
  }

  func prewarm() {
    _ = loading()
  }

  func unload() async {
    _ = await load.take()?.result
  }

  private func loading() -> Task<ModelContainer, Error> {
    if let load { return load }
    // A pass still running at an unload frees the weights after it; MLX would cache them for good.
    Memory.cacheLimit = 0
    let started = Task(priority: .utility) { [directory, loadFailed] in
      do {
        return try await loadModelContainer(from: directory, using: LocalTokenizer())
      } catch {
        loadFailed()
        throw TranscriptionError.modelNotLoaded
      }
    }
    load = started
    return started
  }

  static func text(of events: AsyncThrowingStream<Generation, Error>) async throws -> String {
    var text = ""
    var stop: GenerateStopReason?
    for try await event in events {
      switch event {
      case .chunk(let piece): text += piece
      case .info(let info): stop = info.stopReason
      case .toolCall: continue
      }
    }
    switch stop {
    case .stop: return text
    case .length: throw RefinementError.tokenCap
    case .cancelled, nil: throw TranscriptionError.timedOut
    }
  }
}

struct LocalTokenizer: TokenizerLoader {
  func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
    Bridge(try await AutoTokenizer.from(modelFolder: directory))
  }
}

// mlx-swift-lm 3.x ships no adapter for swift-transformers' tokenizer.
private struct Bridge: MLXLMCommon.Tokenizer, @unchecked Sendable {
  let upstream: any Tokenizers.Tokenizer

  init(_ upstream: any Tokenizers.Tokenizer) { self.upstream = upstream }

  func encode(text: String, addSpecialTokens: Bool) -> [Int] {
    upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
  }
  func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
    upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
  }
  func convertTokenToId(_ token: String) -> Int? { upstream.convertTokenToId(token) }
  func convertIdToToken(_ id: Int) -> String? { upstream.convertIdToToken(id) }
  var bosToken: String? { upstream.bosToken }
  var eosToken: String? { upstream.eosToken }
  var unknownToken: String? { upstream.unknownToken }
  func applyChatTemplate(
    messages: [[String: any Sendable]], tools: [[String: any Sendable]]?,
    additionalContext: [String: any Sendable]?
  ) throws -> [Int] {
    try upstream.applyChatTemplate(
      messages: messages, tools: tools, additionalContext: additionalContext)
  }
}
