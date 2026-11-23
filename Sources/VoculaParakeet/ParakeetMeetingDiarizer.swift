import CoreML
import FluidAudio
import Foundation
import VoculaKit

public struct ParakeetMeetingDiarizer: MeetingDiarizing {
  enum Outcome: Equatable {
    case noSpeech
    case cancelled
    case failure(MeetingDiarizerError)
  }

  static let configuration: OfflineDiarizerConfig = {
    var configuration = OfflineDiarizerConfig.default
    configuration.zeroVoteReembed = .init(enabled: true, minDurationSeconds: 0.4)
    return configuration
  }()

  static let computeUnits: [String: MLComputeUnits] = [
    ModelNames.OfflineDiarizer.segmentationFile: .cpuOnly,
    ModelNames.OfflineDiarizer.fbankFile: .cpuOnly,
    ModelNames.OfflineDiarizer.embeddingFile: .all,
    ModelNames.OfflineDiarizer.pldaRhoFile: .all,
  ]

  private static let queue = DispatchQueue(label: "vocula.meeting.diarizer", qos: .utility)

  private let models: OfflineDiarizerModels

  public static func load(modelDirectory: URL) async throws -> ParakeetMeetingDiarizer {
    try await withCheckedThrowingContinuation { continuation in
      queue.async {
        do {
          continuation.resume(returning: try loadNow(from: modelDirectory))
        } catch {
          switch outcome(of: error, loading: true) {
          case .cancelled: continuation.resume(throwing: CancellationError())
          case .failure(let failure): continuation.resume(throwing: failure)
          case .noSpeech: continuation.resume(throwing: MeetingDiarizerError.model(code: 0))
          }
        }
      }
    }
  }

  public func turns(in samples: [Int16]) async throws -> [SpeakerTurn] {
    let manager = OfflineDiarizerManager(config: Self.configuration)
    manager.initialize(models: models)
    do {
      let result = try await manager.process(
        audioSource: Int16Source(samples: samples), audioLoadingSeconds: 0)
      return result.segments.map {
        SpeakerTurn(
          speaker: $0.speakerId, start: Double($0.startTimeSeconds),
          end: Double($0.endTimeSeconds))
      }
    } catch {
      switch Self.outcome(of: error, loading: false) {
      case .noSpeech: return []
      case .cancelled: throw CancellationError()
      case .failure(let failure): throw failure
      }
    }
  }

  static func outcome(of error: any Error, loading: Bool) -> Outcome {
    if error is CancellationError { return .cancelled }
    if let failure = error as? MeetingDiarizerError { return .failure(failure) }
    if let offline = error as? OfflineDiarizationError {
      guard let code = code(of: offline) else { return .noSpeech }
      return .failure(failure(code, loading: loading))
    }
    if let memory = error as? ANEMemoryUtils.ANEMemoryError {
      return .failure(failure(code(of: memory), loading: loading))
    }
    let bridged = error as NSError
    if bridged.domain == MLModelErrorDomain { return .failure(.model(code: bridged.code)) }
    let foundation = [NSCocoaErrorDomain, NSPOSIXErrorDomain, NSOSStatusErrorDomain]
    let code = foundation.contains(bridged.domain) ? bridged.code : 0
    return .failure(failure(code, loading: loading))
  }

  private static func failure(_ code: Int, loading: Bool) -> MeetingDiarizerError {
    loading ? .model(code: code) : .failed(code: code)
  }

  private static func code(of error: OfflineDiarizationError) -> Int? {
    switch error {
    case .noSpeechDetected: nil
    case .modelNotLoaded: 10
    case .invalidConfiguration: 11
    case .invalidBatchSize: 12
    case .processingFailed: 13
    case .exportFailed: 14
    case .invalidSpan: 15
    }
  }

  private static func code(of error: ANEMemoryUtils.ANEMemoryError) -> Int {
    switch error {
    case .allocationFailed: 30
    case .invalidShape: 31
    case .unsupportedDataType: 32
    case .invalidArrayBounds: 33
    }
  }

  private static func loadNow(from directory: URL) throws -> ParakeetMeetingDiarizer {
    let started = Date()
    let names = ModelNames.OfflineDiarizer.self
    let segmentation = try model(names.segmentationFile, in: directory)
    let fbank = try model(names.fbankFile, in: directory)
    let embedding = try model(names.embeddingFile, in: directory)
    let pldaRho = try model(names.pldaRhoFile, in: directory)
    try requireWhatTheExtractorTrapsOn(fbank: fbank, embedding: embedding)
    let psi = try MeetingDiarizerParameters.psi(
      from: Data(contentsOf: directory.appendingPathComponent(names.pldaParameters)))
    for loaded in [segmentation, fbank, embedding, pldaRho] { try predictSilence(loaded) }
    return ParakeetMeetingDiarizer(
      models: OfflineDiarizerModels(
        segmentationModel: segmentation, fbankModel: fbank, embeddingModel: embedding,
        pldaRhoModel: pldaRho, pldaPsi: psi,
        compilationDuration: Date().timeIntervalSince(started)))
  }

  private static func model(_ name: String, in directory: URL) throws -> MLModel {
    let configuration = MLModelConfiguration()
    configuration.computeUnits = computeUnits[name] ?? .cpuOnly
    configuration.allowLowPrecisionAccumulationOnGPU = true
    return try MLModel(
      contentsOf: directory.appendingPathComponent(name), configuration: configuration)
  }

  private static func requireWhatTheExtractorTrapsOn(fbank: MLModel, embedding: MLModel) throws {
    let fbankSide = fbank.modelDescription
    let embeddingInputs = embedding.modelDescription.inputDescriptionsByName
    guard fbankSide.inputDescriptionsByName["audio"]?.multiArrayConstraint != nil,
      fbankSide.outputDescriptionsByName["fbank_features"]?.type == .multiArray,
      embeddingInputs["fbank_features"]?.type == .multiArray,
      embeddingInputs["weights"]?.multiArrayConstraint != nil,
      embedding.modelDescription.outputDescriptionsByName["embedding"] != nil
    else { throw MeetingDiarizerError.model(code: 0) }
  }

  private static func predictSilence(_ model: MLModel) throws {
    var features: [String: MLFeatureValue] = [:]
    for (name, input) in model.modelDescription.inputDescriptionsByName {
      guard let constraint = input.multiArrayConstraint else {
        throw MeetingDiarizerError.model(code: 0)
      }
      let silence = try MLMultiArray(shape: constraint.shape, dataType: constraint.dataType)
      silence.withUnsafeMutableBytes { bytes, _ in
        bytes.initializeMemory(as: UInt8.self, repeating: 0)
      }
      features[name] = MLFeatureValue(multiArray: silence)
    }
    _ = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: features))
  }
}

private struct Int16Source: AudioSampleSource {
  let samples: [Int16]

  var sampleCount: Int { samples.count }

  func copySamples(into destination: UnsafeMutablePointer<Float>, offset: Int, count: Int) throws {
    let start = max(0, offset)
    guard count > 0, start < samples.count else { return }
    let end = start + min(count, samples.count - start)
    for index in start..<end { destination[index - start] = Float(samples[index]) / 32768 }
  }
}
