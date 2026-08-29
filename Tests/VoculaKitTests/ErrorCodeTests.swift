import Testing

@testable import VoculaKit

struct ErrorCodeTests {
  @Test("every code is exactly what it has always been")
  func codesAreStable() {
    #expect(ErrorCode.code(for: .silentInput) == "VOC-MIC-01")
    #expect(
      ErrorCode.code(
        forRawReason: SessionFailure.silentInput.rawValue,
        inputIsSilenced: true) == "VOC-MIC-02")
    #expect(ErrorCode.noSpeech == "VOC-MIC-03")
    #expect(ErrorCode.code(for: .engineFailed) == "VOC-ENG-01")
    #expect(ErrorCode.code(for: .passTimeout) == "VOC-ENG-02")
    #expect(ErrorCode.code(for: .queueTimeout) == "VOC-ENG-03")
    #expect(ErrorCode.code(for: .emptyTranscript) == "VOC-ENG-04")
    #expect(ErrorCode.code(for: .overflow) == "VOC-ENG-05")
    #expect(ErrorCode.code(for: .insertionFailed) == "VOC-PASTE-01")
    #expect(ErrorCode.code(for: .secureField) == "VOC-PASTE-02")
    #expect(ErrorCode.code(for: .secureInputRaised) == "VOC-PASTE-03")
    #expect(ErrorCode.code(for: .appChanged) == "VOC-PASTE-04")
    #expect(ErrorCode.code(for: .windowChanged) == "VOC-PASTE-05")
    #expect(ErrorCode.code(for: .elementChanged) == "VOC-PASTE-06")
  }

  @Test("no code is used twice")
  func codesAreUnique() {
    let all = ErrorCode.all
    #expect(Set(all).count == all.count)
  }

  @Test("every failure and every denial has one")
  func everyCaseIsCovered() {
    for failure in SessionFailure.allCases {
      #expect(!ErrorCode.code(for: failure).isEmpty)
    }
    for deny in InsertDenyReason.allCases {
      #expect(!ErrorCode.code(for: deny).isEmpty)
    }
  }

  @Test("the user's message is a sentence, not a sentence and a code")
  func copyCarriesNoCode() {
    let copy = RefusalCopy.text(
      forRawReason: SessionFailure.silentInput.rawValue,
      historyIsRecording: false, inputIsSilenced: true)
    #expect(copy?.contains("VOC-") == false)
    #expect(copy?.contains("System Settings") == true)
    #expect(!RefusalCopy.noSpeechText.contains("VOC-"))
  }
}
