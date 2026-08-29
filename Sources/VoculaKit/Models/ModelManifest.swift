import Foundation

public enum ModelID: String, Codable, Sendable, Equatable, CaseIterable {
  case largeV3Turbo
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

  public var engineCredit: String {
    switch self {
    case .whisper:
      return "whisper.cpp v1.9.2 — MIT, The ggml authors"
    case .parakeet:
      return "parakeet.cpp — MIT; weights by NVIDIA under CC-BY-4.0"
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
}

public enum ModelManifest {
  public static let current: [ModelDescriptor] = [
    ModelDescriptor(
      id: .largeV3Turbo,
      family: .whisper,
      fileName: "ggml-large-v3-turbo.bin",
      remoteURL: URL(
        string:
          "https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-large-v3-turbo.bin"
      )!,
      sha256: "1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69",
      byteSize: 1_624_555_275,
      version: "large-v3-turbo @ 5359861c",
      licence: "MIT (OpenAI weights, whisper.cpp GGML conversion)",
      displayName: "Large v3 Turbo"),
    ModelDescriptor(
      id: .speechDetector,
      family: .whisper,
      fileName: "ggml-silero-v5.1.2.bin",
      remoteURL: URL(
        string:
          "https://huggingface.co/ggml-org/whisper-vad/resolve/9ffd54a1e1ee413ddf265af9913beaf518d1639b/ggml-silero-v5.1.2.bin"
      )!,
      sha256: "29940d98d42b91fbd05ce489f3ecf7c72f0a42f027e4875919a28fb4c04ea2cf",
      byteSize: 885_098,
      version: "silero-v5.1.2 @ 9ffd54a1",
      licence: "MIT (Silero VAD)",
      displayName: String(
        localized: "models.speechDetector", defaultValue: "Speech detector", bundle: .module,
        comment: "Name of the VAD model as shown in the model list.")),
  ]

  public static let transcriptionModels: [ModelID] = [.largeV3Turbo]

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
