import Foundation

public enum ModelID: String, Codable, Sendable, Equatable, CaseIterable {
  case largeV3Turbo
  case parakeetV3
  case speechDetector
}

public enum ModelFamily: String, Codable, Sendable, Equatable, CaseIterable {
  case whisper
  case parakeet

  public var title: String {
    switch self {
    case .whisper: return "Whisper"
    case .parakeet: return "Parakeet"
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
    }
  }

  public var engineCredit: String {
    switch self {
    case .whisper:
      return "whisper.cpp v1.9.2 — MIT, The ggml authors"
    case .parakeet:
      return "FluidAudio — Apache-2.0; weights by NVIDIA under CC-BY-4.0"
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
      id: .parakeetV3,
      family: .parakeet,
      fileName: "parakeet-tdt-0.6b-v3.zip",
      remoteURL: URL(
        string:
          "https://github.com/vitaly-kashtalyan/vocula/releases/download/models-v1/parakeet-tdt-0.6b-v3.zip"
      )!,
      sha256: "cba75876b0448f11f7db77ce1acb5f2f0619588fe7b4df77bf4b4ec7859be23c",
      byteSize: 466_638_996,
      version: "parakeet-tdt-0.6b-v3 (Core ML)",
      licence: "CC-BY-4.0 (NVIDIA weights, FluidInference Core ML conversion)",
      displayName: "Parakeet v3",
      unpacked: "parakeet-tdt-0.6b-v3",
      contents: [
        "Preprocessor.mlmodelc", "Encoder.mlmodelc", "Decoder.mlmodelc",
        "JointDecisionv3.mlmodelc", "parakeet_v3_vocab.json",
      ]),
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
  ]

  public static let transcriptionModels: [ModelID] = [.largeV3Turbo, .parakeetV3]

  public static var transcriptionModelsByFamily: [(family: ModelFamily, models: [ModelID])] {
    ModelFamily.allCases.compactMap { family in
      let models = transcriptionModels.filter { descriptor(for: $0).family == family }
      return models.isEmpty ? nil : (family, models)
    }
  }

  public static let defaultTranscriptionModel: ModelID = .largeV3Turbo

  public static func descriptor(for id: ModelID) -> ModelDescriptor {
    guard let model = current.first(where: { $0.id == id }) else {
      preconditionFailure("manifest is missing \(id)")
    }
    return model
  }
}
