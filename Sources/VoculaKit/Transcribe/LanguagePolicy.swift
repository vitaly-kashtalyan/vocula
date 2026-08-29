import Foundation

public struct LanguageSelection: Sendable, Equatable {
  public let codes: [String]
  public let autoDetect: Bool
  public let pinned: String

  public static let fallbackCode = "en"
  public static let `default` = LanguageSelection(codes: [fallbackCode], autoDetect: true)

  public init(codes: [String], autoDetect: Bool, pinned: String = "") {
    var seen = Set<String>()
    let cleaned =
      codes
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty && seen.insert($0).inserted }
    let resolved = cleaned.isEmpty ? [Self.fallbackCode] : cleaned
    self.codes = resolved
    self.autoDetect = autoDetect
    self.pinned = (!autoDetect && resolved.contains(pinned)) ? pinned : resolved[0]
  }

  public init(stored: String, autoDetect: Bool, pinned: String = "") {
    self.init(
      codes: stored.split(separator: ",").map(String.init),
      autoDetect: autoDetect, pinned: pinned)
  }

  public func cycled() -> LanguageSelection {
    guard !autoDetect else {
      return LanguageSelection(codes: codes, autoDetect: false, pinned: codes[0])
    }
    guard let index = codes.firstIndex(of: pinned), index + 1 < codes.count else {
      return LanguageSelection(codes: codes, autoDetect: true)
    }
    return LanguageSelection(codes: codes, autoDetect: false, pinned: codes[index + 1])
  }

  public var stored: String { codes.joined(separator: ",") }

  public static func pinned(_ code: String) -> LanguageSelection {
    LanguageSelection(codes: [code], autoDetect: false)
  }

  public func toggling(_ code: String) -> LanguageSelection {
    guard autoDetect else {
      return LanguageSelection(
        codes: codes.contains(code) ? codes : codes + [code],
        autoDetect: false, pinned: code)
    }
    guard let index = codes.firstIndex(of: code) else {
      return LanguageSelection(codes: codes + [code], autoDetect: true)
    }
    guard codes.count > 1 else { return self }
    var remaining = codes
    remaining.remove(at: index)
    return LanguageSelection(codes: remaining, autoDetect: true)
  }

  public func removing(_ code: String) -> LanguageSelection {
    guard codes.count > 1, codes.contains(code) else { return self }
    return LanguageSelection(
      codes: codes.filter { $0 != code },
      autoDetect: autoDetect, pinned: pinned)
  }

  public func settingAutoDetect(_ wanted: Bool) -> LanguageSelection {
    LanguageSelection(codes: codes, autoDetect: wanted, pinned: pinned)
  }

  public var needsDetection: Bool { autoDetect && codes.count > 1 }
}

public enum LanguagePolicy {
  public static func choose(
    probabilities: [String: Float],
    selection: LanguageSelection
  ) -> String {
    let first = selection.codes[0]
    guard selection.needsDetection else { return selection.pinned }
    return selection.codes.enumerated().max {
      ((probabilities[$0.element] ?? 0), -$0.offset)
        < ((probabilities[$1.element] ?? 0), -$1.offset)
    }?.element ?? first
  }
}

public enum LanguageDetectionReport {
  // Every floor is anchored to two measured populations: clean synthetic
  // speech scores the winner at 0.999 with the selection holding 0.9995 of the
  // mass, while the first real recordings from a bilingual speaker scored 0.29
  // and 0.11 with the selection holding 0.40 and 0.21.
  public static let unsureBelow: Float = 0.5
  public static let closeCall: Float = 0.1
  public static let selectionBelow: Float = 0.9

  // `langs` is HOW MANY were selected, never which: a stranger's log has to be
  // diagnosable, and the count plus the scores says "three languages, and the
  // detector put 79% of its mass outside them" — which is the diagnosis. Which
  // three is one question to the person, and it is on their Languages screen.
  //
  // NO LANGUAGE CODE. `language.cycle` deliberately records only whether
  // detection is on, and PRIVACY.md promises the log carries timings and
  // outcomes; which languages a person speaks is neither.
  //
  // **A CONFIDENTLY WRONG pick is invisible here and always will be.** Polish
  // heard as Russian at ru=0.62 pl=0.31 passes every rule below: the numbers
  // are healthy and no language-free statistic can know the speaker meant the
  // other one. What these rules see is the detector being UNSURE, which is the
  // other half of the same defect.
  public static func detail(
    session: Int, chosen: String, scores: [String: Float], peak: Float?
  ) -> String? {
    line(chosen: chosen, scores: scores, peak: peak).map { "session=\(session) " + $0 }
  }

  public static func line(
    chosen: String, scores: [String: Float], peak: Float? = nil
  ) -> String? {
    let ranked = scores.sorted {
      $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key
    }
    guard let mine = scores[chosen],
      let rival = ranked.first(where: { $0.key != chosen })
    else { return nil }
    let gap = mine - rival.value
    let selected = scores.values.reduce(0, +)
    // A NaN loses every comparison, so without naming it the whole line would
    // go quiet on exactly the run where the engine returned nonsense.
    let broken = mine.isNaN || rival.value.isNaN || selected.isNaN
    guard broken || mine < unsureBelow || gap < closeCall || selected < selectionBelow
    else { return nil }
    return "langs=\(scores.count) pct=\(percent(mine)) "
      + "nextPct=\(percent(rival.value)) selPct=\(percent(selected)) "
      + "gap=\(perMille(gap))"
      + (peak.map { " pk=\(perMille($0))" } ?? "")
  }

  private static func percent(_ value: Float) -> Int { whole(value, of: 100) }
  private static func perMille(_ value: Float) -> Int { whole(value, of: 1000) }

  // These are probabilities out of a C library. NaN is NOT caught by min/max —
  // `max(.nan, 0)` is `.nan` — and `Int(Float.nan)` traps, so it is answered
  // with a sentinel a reader cannot mistake for a measurement. The floor is
  // -1, not 0: `gap` is a difference, and clamping a negative one to zero
  // would report a chosen language that LOST as an exact tie.
  private static func whole(_ value: Float, of scale: Float) -> Int {
    guard !value.isNaN else { return notANumber }
    return Int((min(max(value, -1), 1) * scale).rounded())
  }

  public static let notANumber = -1
}
