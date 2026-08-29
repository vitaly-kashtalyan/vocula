import Foundation

public enum SyntheticInputDevice {
  public static func isKnownSynthetic(uid: String, name: String) -> Bool {
    let prefix = "CADefaultDeviceAggregate"
    return uid.hasPrefix(prefix) || name.hasPrefix(prefix)
  }
}

public struct RankedInputDevice: Codable, Equatable, Sendable {
  public let uid: String
  public let name: String

  public init(uid: String, name: String) {
    self.uid = uid
    self.name = name
  }

  public var displayName: String {
    name.isEmpty
      ? String(
        localized: "microphone.unknownDevice", defaultValue: "Unknown device", bundle: .module,
        comment:
          "Row label for a ranked microphone that has not been seen connected since it was added, so macOS never gave us its name."
      )
      : name
  }
}

public struct MicrophonePriorityList: Codable, Equatable, Sendable {
  public private(set) var devices: [RankedInputDevice]

  public init(devices: [RankedInputDevice] = []) {
    self.devices = devices
  }

  public func reconciled(with connected: [RankedInputDevice], builtInUID: String)
    -> MicrophonePriorityList
  {
    var result = devices
    if !result.contains(where: { $0.uid == builtInUID }),
      let builtIn = connected.first(where: { $0.uid == builtInUID })
    {
      result.insert(builtIn, at: 0)
    }
    let connectedByUID = Dictionary(
      connected.map { ($0.uid, $0) }, uniquingKeysWith: { _, new in new })
    result = result.map { connectedByUID[$0.uid] ?? $0 }
    let known = Set(result.map(\.uid))
    for device in connected where !known.contains(device.uid) {
      result.append(device)
    }
    return MicrophonePriorityList(devices: result)
  }

  public static let legacyPlaceholderNames: Set<String> = [
    "Unknown device", "Built-in Microphone", "the system default microphone",
  ]

  public func blankingLegacyPlaceholderNames() -> MicrophonePriorityList {
    MicrophonePriorityList(
      devices: devices.map {
        Self.legacyPlaceholderNames.contains($0.name)
          ? RankedInputDevice(uid: $0.uid, name: "")
          : $0
      })
  }

  public func purgedOfKnownSyntheticDevices() -> MicrophonePriorityList {
    MicrophonePriorityList(
      devices: devices.filter {
        !SyntheticInputDevice.isKnownSynthetic(uid: $0.uid, name: $0.name)
      })
  }

  public func firstAvailable(in connectedUIDs: Set<String>) -> RankedInputDevice? {
    devices.first { connectedUIDs.contains($0.uid) }
  }

  public func movedUp(uid: String) -> MicrophonePriorityList { moved(uid: uid, by: -1) }
  public func movedDown(uid: String) -> MicrophonePriorityList { moved(uid: uid, by: 1) }

  public func movedToTop(uid: String) -> MicrophonePriorityList {
    guard let index = devices.firstIndex(where: { $0.uid == uid }), index > 0 else { return self }
    var result = devices
    let item = result.remove(at: index)
    result.insert(item, at: 0)
    return MicrophonePriorityList(devices: result)
  }

  public func moved(uid: String, to index: Int) -> MicrophonePriorityList {
    guard let from = devices.firstIndex(where: { $0.uid == uid }) else { return self }
    let target = min(max(0, index), devices.count - 1)
    guard target != from else { return self }
    var result = devices
    result.insert(result.remove(at: from), at: target)
    return MicrophonePriorityList(devices: result)
  }

  private func moved(uid: String, by offset: Int) -> MicrophonePriorityList {
    guard let index = devices.firstIndex(where: { $0.uid == uid }) else { return self }
    let target = index + offset
    guard devices.indices.contains(target) else { return self }
    var result = devices
    result.swapAt(index, target)
    return MicrophonePriorityList(devices: result)
  }

  public static func migrated(
    legacyUID: String, legacyName: String,
    builtInUID: String?, builtInName: String,
    systemDefaultUID: String? = nil, systemDefaultName: String = "",
    connected: [RankedInputDevice]
  ) -> MicrophonePriorityList {
    var seed: [RankedInputDevice] = []
    if !legacyUID.isEmpty {
      seed.append(RankedInputDevice(uid: legacyUID, name: legacyName))
    }
    if let builtInUID, !seed.contains(where: { $0.uid == builtInUID }) {
      seed.append(RankedInputDevice(uid: builtInUID, name: builtInName))
    } else if builtInUID == nil, let systemDefaultUID,
      !seed.contains(where: { $0.uid == systemDefaultUID })
    {
      seed.append(RankedInputDevice(uid: systemDefaultUID, name: systemDefaultName))
    }
    return MicrophonePriorityList(devices: seed).reconciled(
      with: connected, builtInUID: builtInUID ?? "")
  }

  public func encoded() -> String {
    guard let data = try? JSONEncoder().encode(self) else { return "" }
    return String(data: data, encoding: .utf8) ?? ""
  }

  public init(encoded string: String) {
    guard let data = string.data(using: .utf8),
      let decoded = try? JSONDecoder().decode(MicrophonePriorityList.self, from: data)
    else {
      self.devices = []
      return
    }
    self.devices = decoded.devices
  }
}
