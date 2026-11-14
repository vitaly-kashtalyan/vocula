import Foundation

public enum ModelID: String, Codable, Sendable, Equatable, CaseIterable {
  case largeV3Turbo
  case parakeetUltra
  case speechDetector
  case qwenRefine2B

  public init?(rawValue: String) {
    if rawValue == "parakeetV3" {
      self = .parakeetUltra
      return
    }
    guard let id = Self.allCases.first(where: { $0.rawValue == rawValue }) else { return nil }
    self = id
  }
}

public enum ModelFamily: String, Codable, Sendable, Equatable, CaseIterable {
  case whisper
  case parakeet
  case refiner

  public var title: String {
    switch self {
    case .whisper: return "Whisper"
    case .parakeet: return "Parakeet"
    case .refiner: return "MLX"
    }
  }

  public var summary: String {
    switch self {
    case .whisper:
      return String(
        localized: "models.summary.whisper",
        defaultValue:
          "The wider choice of languages, and the one to pick when a single sentence mixes two — it will keep an English term inside Greek speech. Larger to download and slower to transcribe.",
        bundle: .module,
        comment:
          "Footer under the Whisper group in Settings → Models. It orients someone who cannot tell the engines apart, so it names behaviour rather than numbers, which would go stale."
      )
    case .parakeet:
      return String(
        localized: "models.summary.parakeet",
        defaultValue:
          "Faster and much smaller, and it works out the language by itself. It holds to one alphabet per phrase, so a foreign term inside a sentence may come out transliterated or lost.",
        bundle: .module,
        comment:
          "Footer under the Parakeet group in Settings → Models. It orients someone who cannot tell the engines apart, so it names behaviour rather than numbers, which would go stale."
      )
    case .refiner:
      return ""
    }
  }

  public var engineCredit: String {
    switch self {
    case .whisper:
      return "whisper.cpp v1.9.5 — MIT, The ggml authors"
    case .parakeet:
      return
        "FluidAudio — Apache-2.0; Parakeet Ultra weights by moondream, from NVIDIA Parakeet TDT v3, under CC-BY-4.0"
    case .refiner:
      return
        "MLX — MIT, Apple; swift-transformers — Apache-2.0, Hugging Face; Qwen3.5 weights by Alibaba under Apache-2.0, fine-tuned by Vocula"
    }
  }
}

public struct ModelDescriptor: Codable, Sendable, Equatable {
  public let id: ModelID
  public let family: ModelFamily
  public let fileName: String
  public let remoteURL: URL
  public let sha256: String
  public let byteSize: Int64
  public let version: String
  public let licence: String
  public let displayName: String
  public let unpacked: String?
  public let contents: [String]
  public var expandedBytes: Int64? = nil
}

public enum ModelManifest {
  public static let current: [ModelDescriptor] = [
    ModelDescriptor(
      id: .largeV3Turbo,
      family: .whisper,
      fileName: "ggml-large-v3-turbo.bin",
      remoteURL: URL(
        string:
          "https://github.com/vitaly-kashtalyan/vocula/releases/download/models-v1/ggml-large-v3-turbo.bin"
      )!,
      sha256: "1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69",
      byteSize: 1_624_555_275,
      version: "large-v3-turbo @ 5359861c",
      licence: "MIT (OpenAI weights, whisper.cpp GGML conversion)",
      displayName: "Large v3 Turbo",
      unpacked: nil, contents: []),
    ModelDescriptor(
      id: .parakeetUltra,
      family: .parakeet,
      fileName: "parakeet-ultra-95eaa59.zip",
      remoteURL: URL(
        string:
          "https://github.com/vitaly-kashtalyan/vocula/releases/download/models-v1/parakeet-ultra-95eaa59.zip"
      )!,
      sha256: "f208a416e5327e120f01fa70bf19a7f0c2427cc555c6471dc055b7835e2c6596",
      byteSize: 554_970_523,
      version: "parakeet-ultra (Core ML, FluidInference 95eaa59)",
      licence:
        "CC-BY-4.0 (moondream Parakeet Ultra, post-trained from NVIDIA Parakeet TDT 0.6B v3; Core ML conversion by FluidInference)",
      displayName: "Parakeet Ultra",
      unpacked: "parakeet-ultra-95eaa59",
      contents: [
        "Preprocessor.mlmodelc", "Encoder.mlmodelc", "Decoder.mlmodelc",
        "JointDecisionv3.mlmodelc", "parakeet_vocab.json",
      ],
      expandedBytes: 632_162_964),
    ModelDescriptor(
      id: .speechDetector,
      family: .whisper,
      fileName: "ggml-silero-v5.1.2.bin",
      remoteURL: URL(
        string:
          "https://github.com/vitaly-kashtalyan/vocula/releases/download/models-v1/ggml-silero-v5.1.2.bin"
      )!,
      sha256: "29940d98d42b91fbd05ce489f3ecf7c72f0a42f027e4875919a28fb4c04ea2cf",
      byteSize: 885_098,
      version: "silero-v5.1.2 @ 9ffd54a1",
      licence: "MIT (Silero VAD)",
      displayName: String(
        localized: "models.speechDetector", defaultValue: "Speech detector", bundle: .module,
        comment: "Name of the VAD model as shown in the model list."),
      unpacked: nil, contents: []),
    ModelDescriptor(
      id: .qwenRefine2B,
      family: .refiner,
      fileName: "vocula-cleanup-2b-v1.zip",
      remoteURL: URL(
        string:
          "https://github.com/vitaly-kashtalyan/vocula/releases/download/models-v1/vocula-cleanup-2b-v1.zip"
      )!,
      sha256: "5a2ca3de9a9c2f3a6edf1fbbd107ce0e52f2d22056d9015f6e457be8d93a3673",
      byteSize: 1_488_415_413,
      version: "Qwen3.5-2B-6bit @ ba2bcf03",
      licence: "Apache-2.0 (Qwen3.5, modified)",
      displayName: "Vocula 2B v1",
      unpacked: "vocula-cleanup-2b-v1",
      contents: [
        "model.safetensors", "model.safetensors.index.json", "config.json",
        "tokenizer.json", "tokenizer_config.json", "vocab.json", "chat_template.jinja",
      ],
      expandedBytes: 1_556_519_683),
  ]

  public static let transcriptionModels: [ModelID] = [.largeV3Turbo, .parakeetUltra]

  public static var transcriptionModelsByFamily: [(family: ModelFamily, models: [ModelID])] {
    ModelFamily.allCases.compactMap { family in
      let models = transcriptionModels.filter { descriptor(for: $0).family == family }
      return models.isEmpty ? nil : (family, models)
    }
  }

  public static let defaultTranscriptionModel: ModelID = .parakeetUltra

  public static func descriptor(for id: ModelID) -> ModelDescriptor {
    guard let model = current.first(where: { $0.id == id }) else {
      preconditionFailure("manifest is missing \(id)")
    }
    return model
  }
}
