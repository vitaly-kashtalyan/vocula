import Foundation

public struct AppSettings: @unchecked Sendable {
  public let defaults: UserDefaults

  private final class SessionPause: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    static let shared = SessionPause()
    var isPaused: Bool {
      get { lock.withLock { value } }
      set { lock.withLock { value = newValue } }
    }
  }

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  public static let historyEnabledKey = "history.enabled"
  public static let historyEnabledDefault = true
  public static let languageCodesKey = "language.codes"
  public static let languageCodesDefault = LanguageSelection.default.stored
  public static let autoDetectLanguageKey = "language.autoDetect"
  public static let autoDetectLanguageDefault = LanguageSelection.default.autoDetect
  public static let pinnedLanguageKey = "language.pinned"
  public static let pinnedLanguageDefault = ""
  public static let licenceKeyKey = "licence.key"
  public static let licenceKeyDefault = ""
  public static let microphonePriorityKey = "audio.microphonePriority"
  public static let microphonePriorityDefault = ""
  public static let microphonePriorityMigratedKey = "audio.microphonePriorityMigrated"
  public static let microphoneNamesBlankedKey = "audio.microphoneNamesBlanked"
  public static let transcriptionModelKey = "model.transcription"
  public static let transcriptionModelDefault = ModelManifest.defaultTranscriptionModel

  public var historyEnabled: Bool {
    get { defaults.object(forKey: Self.historyEnabledKey) as? Bool ?? Self.historyEnabledDefault }
    nonmutating set { defaults.set(newValue, forKey: Self.historyEnabledKey) }
  }

  public var sessionOnlyPause: Bool {
    get { SessionPause.shared.isPaused }
    nonmutating set { SessionPause.shared.isPaused = newValue }
  }

  public var isRecordingHistory: Bool { historyEnabled && !sessionOnlyPause }

  public var languages: LanguageSelection {
    get {
      LanguageSelection(
        stored: defaults.string(forKey: Self.languageCodesKey) ?? Self.languageCodesDefault,
        autoDetect: defaults.object(forKey: Self.autoDetectLanguageKey) as? Bool
          ?? Self.autoDetectLanguageDefault,
        pinned: defaults.string(forKey: Self.pinnedLanguageKey)
          ?? Self.pinnedLanguageDefault)
    }
    nonmutating set {
      defaults.set(newValue.stored, forKey: Self.languageCodesKey)
      defaults.set(newValue.autoDetect, forKey: Self.autoDetectLanguageKey)
      defaults.set(newValue.pinned, forKey: Self.pinnedLanguageKey)
    }
  }

  private static func codesKey(_ family: ModelFamily) -> String {
    "\(languageCodesKey).\(family.rawValue)"
  }

  private static func autoDetectKey(_ family: ModelFamily) -> String {
    "\(autoDetectLanguageKey).\(family.rawValue)"
  }

  private static func pinnedKey(_ family: ModelFamily) -> String {
    "\(pinnedLanguageKey).\(family.rawValue)"
  }

  public func storedLanguages(for family: ModelFamily) -> LanguageSelection? {
    guard let stored = defaults.string(forKey: Self.codesKey(family)) else { return nil }
    return LanguageSelection(
      stored: stored,
      autoDetect: defaults.object(forKey: Self.autoDetectKey(family)) as? Bool
        ?? Self.autoDetectLanguageDefault,
      pinned: defaults.string(forKey: Self.pinnedKey(family)) ?? Self.pinnedLanguageDefault)
  }

  public func setLanguages(_ selection: LanguageSelection, for family: ModelFamily) {
    defaults.set(selection.stored, forKey: Self.codesKey(family))
    defaults.set(selection.autoDetect, forKey: Self.autoDetectKey(family))
    defaults.set(selection.pinned, forKey: Self.pinnedKey(family))
  }

  public func rememberLanguages(for family: ModelFamily) {
    setLanguages(languages, for: family)
  }

  public func restoreLanguages(for family: ModelFamily) {
    languages = storedLanguages(for: family) ?? EngineLanguages.narrow(languages, to: family)
  }

  public func switchEngine(from outgoing: ModelFamily, to incoming: ModelFamily) {
    guard outgoing != incoming else { return }
    rememberLanguages(for: outgoing)
    restoreLanguages(for: incoming)
  }

  public var licenceKey: String {
    get { defaults.string(forKey: Self.licenceKeyKey) ?? Self.licenceKeyDefault }
    nonmutating set { defaults.set(newValue, forKey: Self.licenceKeyKey) }
  }

  public var microphonePriority: MicrophonePriorityList {
    get {
      MicrophonePriorityList(
        encoded: defaults.string(forKey: Self.microphonePriorityKey)
          ?? Self.microphonePriorityDefault)
    }
    nonmutating set { defaults.set(newValue.encoded(), forKey: Self.microphonePriorityKey) }
  }

  public var microphoneNamesBlanked: Bool {
    get { defaults.bool(forKey: Self.microphoneNamesBlankedKey) }
    nonmutating set { defaults.set(newValue, forKey: Self.microphoneNamesBlankedKey) }
  }

  public var microphonePriorityMigrated: Bool {
    get { defaults.bool(forKey: Self.microphonePriorityMigratedKey) }
    nonmutating set { defaults.set(newValue, forKey: Self.microphonePriorityMigratedKey) }
  }

  public var transcriptionModel: ModelID {
    get {
      ModelID(rawValue: defaults.string(forKey: Self.transcriptionModelKey) ?? "")
        ?? Self.transcriptionModelDefault
    }
    nonmutating set { defaults.set(newValue.rawValue, forKey: Self.transcriptionModelKey) }
  }

  public var appearance: AppearancePreference {
    get { AppearancePreference(stored: defaults.string(forKey: AppearancePreference.storageKey)) }
    nonmutating set { defaults.set(newValue.rawValue, forKey: AppearancePreference.storageKey) }
  }

  public var hasCompletedOnboarding: Bool {
    get { defaults.bool(forKey: "onboarding.completed") }
    nonmutating set { defaults.set(newValue, forKey: "onboarding.completed") }
  }
}
