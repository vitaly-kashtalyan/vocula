import VoculaKit

@MainActor
enum MicrophonePriorityMigration {
  private static let legacyInputDeviceUIDKey = "audio.inputDeviceUID"

  static func runIfNeeded(settings: AppSettings, snapshot: AudioInputSnapshot) {
    guard !settings.microphonePriorityMigrated else { return }
    let legacyUID = settings.defaults.string(forKey: legacyInputDeviceUIDKey) ?? ""
    let legacyName = legacyUID.isEmpty ? "" : (snapshot.name(uid: legacyUID) ?? "")
    settings.microphonePriority = MicrophonePriorityList.migrated(
      legacyUID: legacyUID, legacyName: legacyName,
      builtInUID: snapshot.builtInUID,
      builtInName: snapshot.builtInName ?? "",
      systemDefaultUID: snapshot.systemDefaultUID,
      systemDefaultName: snapshot.systemDefaultName ?? "",
      connected: snapshot.devices.map { RankedInputDevice(uid: $0.uid, name: $0.name) })
    settings.microphonePriorityMigrated = true
    settings.microphoneNamesBlanked = true
  }

  static func blankLegacyNamesIfNeeded(settings: AppSettings) {
    guard !settings.microphoneNamesBlanked else { return }
    let blanked = settings.microphonePriority.blankingLegacyPlaceholderNames()
    if blanked != settings.microphonePriority {
      settings.microphonePriority = blanked
    }
    settings.microphoneNamesBlanked = true
  }

  static func reconcile(settings: AppSettings, snapshot: AudioInputSnapshot) {
    let ranked = snapshot.devices.map { RankedInputDevice(uid: $0.uid, name: $0.name) }
    let current = settings.microphonePriority
    let reconciled = current.purgedOfKnownSyntheticDevices()
      .reconciled(with: ranked, builtInUID: snapshot.builtInUID ?? "")
    if reconciled != current {
      settings.microphonePriority = reconciled
    }
  }
}
