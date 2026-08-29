import Foundation

public enum BindingCapture {
  static let functionKeyCodes: Set<UInt16> = [0x69, 0x6B, 0x71, 0x6A, 0x40, 0x4F, 0x50, 0x5A]

  public static func binding(from captured: CapturedKey) -> KeyBinding {
    guard let keyCode = captured.keyCode else {
      let klass: BindingClass =
        captured.modifiers == [.function]
          || captured.modifiers.rawValue.nonzeroBitCount <= 1
        ? .singleModifier : .modifierPair
      return KeyBinding(klass: klass, keyCode: nil, modifiers: captured.modifiers)
    }
    if functionKeyCodes.contains(keyCode), captured.modifiers.isEmpty {
      return KeyBinding(klass: .functionKey, keyCode: keyCode, modifiers: [])
    }
    return KeyBinding(klass: .comboWithKey, keyCode: keyCode, modifiers: captured.modifiers)
  }
}

public enum LiveCheckTiming {
  public static let timeout: Duration = .seconds(5)
}

public enum LiveCheckOutcome: String, Sendable, Equatable, CaseIterable {
  case working
  case nothingArrived
  case pressWithoutRelease
  case releaseWithoutPress
}

public struct LiveCheck: Sendable {
  public let timeout: Duration
  private var sawPress = false
  private var sawRelease = false
  public private(set) var outcome: LiveCheckOutcome?

  public init(timeout: Duration = LiveCheckTiming.timeout) { self.timeout = timeout }

  public mutating func observe(_ event: LiveCheckEvent) {
    guard outcome == nil else { return }
    switch event {
    case .press:
      sawPress = true
      if sawRelease { outcome = .working }
    case .release:
      sawRelease = true
      if sawPress { outcome = .working }
    case .timeout:
      switch (sawPress, sawRelease) {
      case (true, true): outcome = .working
      case (true, false): outcome = .pressWithoutRelease
      case (false, true): outcome = .releaseWithoutPress
      case (false, false): outcome = .nothingArrived
      }
    }
  }

  public static func explanationKey(for outcome: LiveCheckOutcome) -> String {
    switch outcome {
    case .working: return "livecheck.working"
    case .nothingArrived: return "livecheck.nothingArrived"
    case .pressWithoutRelease: return "livecheck.pressWithoutRelease"
    case .releaseWithoutPress: return "livecheck.releaseWithoutPress"
    }
  }

  public static func explanation(for outcome: LiveCheckOutcome) -> String {
    switch outcome {
    case .working:
      return String(
        localized: "livecheck.working",
        defaultValue: "The key is fully visible — the binding is saved.", bundle: .module,
        comment: "Live-check result: press and release both reached the tap.")
    case .nothingArrived:
      return String(
        localized: "livecheck.nothingArrived",
        defaultValue:
          "The key does not arrive at all. Likely causes: another interceptor took it (Raycast, Alfred, Karabiner, BetterTouchTool, a corporate agent), external keyboard firmware, or secure input is active right now. Choose another key.",
        bundle: .module,
        comment:
          "Live-check result: nothing reached the tap. The four app names are products and are never translated."
      )
    case .pressWithoutRelease:
      return String(
        localized: "livecheck.pressWithoutRelease",
        defaultValue:
          "The press arrived without the release: the hold gesture will not work on this key. Choose another key.",
        bundle: .module,
        comment:
          "Live-check result: the release never came. Must stay clearly distinct from livecheck.releaseWithoutPress — they differ by four words in English."
      )
    case .releaseWithoutPress:
      return String(
        localized: "livecheck.releaseWithoutPress",
        defaultValue:
          "The release arrived without the press: the hold gesture will not work on this key. Choose another key.",
        bundle: .module,
        comment:
          "Live-check result: the press never came. Must stay clearly distinct from livecheck.pressWithoutRelease."
      )
    }
  }
}
