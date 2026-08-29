import Foundation

public enum ErrorCode {
  public static func code(forRawReason raw: String, inputIsSilenced: Bool = false) -> String? {
    if raw == SessionFailure.silentInput.rawValue {
      return inputIsSilenced ? "VOC-MIC-02" : "VOC-MIC-01"
    }
    if let failure = SessionFailure(rawValue: raw) {
      return code(for: failure)
    }
    if let deny = InsertDenyReason(rawValue: raw) { return code(for: deny) }
    return nil
  }

  public static func code(for failure: SessionFailure) -> String {
    switch failure {
    case .silentInput: return "VOC-MIC-01"
    case .engineFailed: return "VOC-ENG-01"
    case .passTimeout: return "VOC-ENG-02"
    case .queueTimeout: return "VOC-ENG-03"
    case .emptyTranscript: return "VOC-ENG-04"
    case .overflow: return "VOC-ENG-05"
    case .insertionFailed: return "VOC-PASTE-01"
    }
  }

  public static func code(for deny: InsertDenyReason) -> String {
    switch deny {
    case .secureField: return "VOC-PASTE-02"
    case .secureInputRaised: return "VOC-PASTE-03"
    case .appChanged: return "VOC-PASTE-04"
    case .windowChanged: return "VOC-PASTE-05"
    case .elementChanged: return "VOC-PASTE-06"
    }
  }

  public static let noSpeech = "VOC-MIC-03"

  public static var all: [String] {
    SessionFailure.allCases.map(code(for:))
      + InsertDenyReason.allCases.map(code(for:))
      + ["VOC-MIC-02", noSpeech]
  }
}
