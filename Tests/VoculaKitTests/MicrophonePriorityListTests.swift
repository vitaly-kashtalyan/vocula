import Testing

@testable import VoculaKit

@Suite("Microphone priority list")
struct MicrophonePriorityListTests {
  private let builtIn = RankedInputDevice(uid: "built-in", name: "MacBook Pro Microphone")
  private let usb = RankedInputDevice(uid: "usb-1", name: "USB Interface")
  private let bt = RankedInputDevice(uid: "bt-1", name: "AirPods Pro")

  @Test("a drag across two rows lands where it was dropped, rather than swapping")
  func movedToIndexInserts() {
    let list = MicrophonePriorityList(devices: [builtIn, usb, bt])
    #expect(list.moved(uid: "bt-1", to: 0).devices.map(\.uid) == ["bt-1", "built-in", "usb-1"])
    #expect(list.moved(uid: "built-in", to: 2).devices.map(\.uid) == ["usb-1", "bt-1", "built-in"])
  }

  @Test("a drag onto its own row, past either end, or of an unknown device changes nothing")
  func movedToIndexRefusesNonMoves() {
    let list = MicrophonePriorityList(devices: [builtIn, usb, bt])
    #expect(list.moved(uid: "usb-1", to: 1) == list)
    #expect(list.moved(uid: "built-in", to: -4).devices.map(\.uid) == list.devices.map(\.uid))
    #expect(list.moved(uid: "usb-1", to: 99).devices.map(\.uid) == ["built-in", "bt-1", "usb-1"])
    #expect(list.moved(uid: "absent", to: 0) == list)
  }

  @Test("purging drops a known-synthetic aggregate entry and keeps real devices, order preserved")
  func purgeDropsKnownSyntheticDevices() {
    let aggregate = RankedInputDevice(
      uid: "CADefaultDeviceAggregate-68644-0",
      name: "CADefaultDeviceAggregate-68644-0")
    let list = MicrophonePriorityList(devices: [builtIn, aggregate, usb])
    let result = list.purgedOfKnownSyntheticDevices()
    #expect(result.devices.map(\.uid) == ["built-in", "usb-1"])
  }

  @Test("purging a list with nothing synthetic is a no-op")
  func purgeIsANoOpWithoutSyntheticDevices() {
    let list = MicrophonePriorityList(devices: [builtIn, usb])
    #expect(list.purgedOfKnownSyntheticDevices() == list)
  }

  @Test("a list of only synthetic devices purges to empty, and reconciling re-seeds the built-in")
  func purgeOfAllSyntheticDevicesReSeedsBuiltIn() {
    let aggregate = RankedInputDevice(
      uid: "CADefaultDeviceAggregate-68644-0",
      name: "CADefaultDeviceAggregate-68644-0")
    let list = MicrophonePriorityList(devices: [aggregate])
    let purged = list.purgedOfKnownSyntheticDevices()
    #expect(purged.devices.isEmpty)
    let result = purged.reconciled(with: [builtIn], builtInUID: builtIn.uid)
    #expect(result.devices.map(\.uid) == ["built-in"])
  }

  @Test("purging then reconciling drops the aggregate for good — it is not re-appended")
  func purgeThenReconcileDropsAggregateForGood() {
    let aggregate = RankedInputDevice(
      uid: "CADefaultDeviceAggregate-68644-0",
      name: "CADefaultDeviceAggregate-68644-0")
    let list = MicrophonePriorityList(devices: [builtIn, aggregate, usb])
    let result = list.purgedOfKnownSyntheticDevices()
      .reconciled(with: [builtIn, usb], builtInUID: builtIn.uid)
    #expect(result.devices.map(\.uid) == ["built-in", "usb-1"])
  }

  @Test("reconciling an empty list inserts the built-in device first")
  func reconcileSeedsBuiltIn() {
    let list = MicrophonePriorityList()
    let result = list.reconciled(with: [builtIn, usb], builtInUID: builtIn.uid)
    #expect(result.devices.map(\.uid) == ["built-in", "usb-1"])
  }

  @Test("reconciling appends unseen devices at the bottom, in the order given")
  func reconcileAppendsAtBottom() {
    let list = MicrophonePriorityList(devices: [builtIn])
    let result = list.reconciled(with: [builtIn, usb, bt], builtInUID: builtIn.uid)
    #expect(result.devices.map(\.uid) == ["built-in", "usb-1", "bt-1"])
  }

  @Test("reconciling twice with the same input is a no-op")
  func reconcileIsIdempotent() {
    let list = MicrophonePriorityList(devices: [builtIn])
    let once = list.reconciled(with: [builtIn, usb], builtInUID: builtIn.uid)
    let twice = once.reconciled(with: [builtIn, usb], builtInUID: builtIn.uid)
    #expect(once == twice)
  }

  @Test("reconciling never duplicates a uid already ranked")
  func reconcileNeverDuplicates() {
    let list = MicrophonePriorityList(devices: [usb, builtIn])
    let result = list.reconciled(with: [builtIn, usb], builtInUID: builtIn.uid)
    #expect(result.devices.map(\.uid) == ["usb-1", "built-in"])
  }

  @Test("reconciling refreshes a stale name without changing order")
  func reconcileRefreshesStaleName() {
    let stale = RankedInputDevice(uid: "usb-1", name: "Unknown device")
    let list = MicrophonePriorityList(devices: [builtIn, stale])
    let liveUSB = RankedInputDevice(uid: "usb-1", name: "USB Interface")
    let result = list.reconciled(with: [builtIn, liveUSB], builtInUID: builtIn.uid)
    #expect(result.devices.map(\.uid) == ["built-in", "usb-1"])
    #expect(result.devices.last?.name == "USB Interface")
  }

  @Test("firstAvailable returns the highest-ranked connected device")
  func firstAvailablePicksTopConnected() {
    let list = MicrophonePriorityList(devices: [bt, usb, builtIn])
    #expect(list.firstAvailable(in: ["usb-1", "built-in"])?.uid == "usb-1")
  }

  @Test("firstAvailable falls through to the built-in floor")
  func firstAvailableFallsToBuiltIn() {
    let list = MicrophonePriorityList(devices: [bt, usb, builtIn])
    #expect(list.firstAvailable(in: ["built-in"])?.uid == "built-in")
  }

  @Test("firstAvailable returns nil when nothing ranked is connected")
  func firstAvailableReturnsNilWhenNothingConnected() {
    let list = MicrophonePriorityList(devices: [bt, usb])
    #expect(list.firstAvailable(in: []) == nil)
  }

  @Test("movedUp and movedDown swap adjacent entries")
  func moveSwapsAdjacent() {
    let list = MicrophonePriorityList(devices: [builtIn, usb, bt])
    #expect(list.movedUp(uid: "usb-1").devices.map(\.uid) == ["usb-1", "built-in", "bt-1"])
    #expect(list.movedDown(uid: "usb-1").devices.map(\.uid) == ["built-in", "bt-1", "usb-1"])
  }

  @Test("movedUp at the top and movedDown at the bottom are no-ops")
  func moveNoOpsAtBoundaries() {
    let list = MicrophonePriorityList(devices: [builtIn, usb])
    #expect(list.movedUp(uid: "built-in") == list)
    #expect(list.movedDown(uid: "usb-1") == list)
  }

  @Test("moving an unknown uid is a no-op")
  func moveNoOpsForUnknownUID() {
    let list = MicrophonePriorityList(devices: [builtIn])
    #expect(list.movedUp(uid: "ghost") == list)
    #expect(list.movedDown(uid: "ghost") == list)
    #expect(list.movedToTop(uid: "ghost") == list)
  }

  @Test("movedToTop promotes a device to index 0")
  func moveToTopPromotes() {
    let list = MicrophonePriorityList(devices: [builtIn, usb, bt])
    #expect(list.movedToTop(uid: "bt-1").devices.map(\.uid) == ["bt-1", "built-in", "usb-1"])
  }

  @Test("encoding and decoding round-trips")
  func encodingRoundTrips() {
    let list = MicrophonePriorityList(devices: [builtIn, usb])
    let decoded = MicrophonePriorityList(encoded: list.encoded())
    #expect(decoded == list)
  }

  @Test("decoding garbage or empty text yields an empty list")
  func decodingGarbageYieldsEmpty() {
    #expect(MicrophonePriorityList(encoded: "").devices.isEmpty)
    #expect(MicrophonePriorityList(encoded: "not json").devices.isEmpty)
  }

  @Test("migrating a non-empty legacy uid seeds it ahead of built-in")
  func migratedSeedsLegacyAheadOfBuiltIn() {
    let result = MicrophonePriorityList.migrated(
      legacyUID: "usb-1", legacyName: "USB Interface",
      builtInUID: "built-in", builtInName: "MacBook Pro Microphone",
      connected: [builtIn, usb, bt])
    #expect(result.devices.map(\.uid) == ["usb-1", "built-in", "bt-1"])
  }

  @Test("migrating an empty legacy uid seeds only built-in")
  func migratedSeedsBuiltInOnly() {
    let result = MicrophonePriorityList.migrated(
      legacyUID: "", legacyName: "",
      builtInUID: "built-in", builtInName: "MacBook Pro Microphone",
      connected: [builtIn, usb])
    #expect(result.devices.map(\.uid) == ["built-in", "usb-1"])
  }

  @Test(
    "migrating with no built-in microphone seeds the system default instead of an arbitrary device")
  func migratedSeedsSystemDefaultWhenNoBuiltIn() {
    let systemDefault = RankedInputDevice(uid: "sys-1", name: "USB Audio Interface")
    let result = MicrophonePriorityList.migrated(
      legacyUID: "", legacyName: "",
      builtInUID: nil, builtInName: "",
      systemDefaultUID: "sys-1", systemDefaultName: "USB Audio Interface",
      connected: [systemDefault, usb])
    #expect(result.devices.map(\.uid) == ["sys-1", "usb-1"])
  }

  @Test("a migration that cannot name a device stores no prose for it")
  func migrationStoresNoCopy() {
    let result = MicrophonePriorityList.migrated(
      legacyUID: "legacy-1", legacyName: "",
      builtInUID: "built-in", builtInName: "",
      systemDefaultUID: nil, systemDefaultName: "",
      connected: [])
    #expect(result.devices.map(\.uid) == ["legacy-1", "built-in"])
    #expect(result.devices.allSatisfy { $0.name.isEmpty })
  }

  @Test("an empty stored name is resolved at render, not in storage")
  func displayNameResolvesEmpty() {
    #expect(RankedInputDevice(uid: "u", name: "").displayName == "Unknown device")
    #expect(RankedInputDevice(uid: "u", name: "AirPods Pro").displayName == "AirPods Pro")
  }

  @Test("blanking clears exactly the three sentinels an older build wrote")
  func blankingClearsOnlyThePlaceholders() {
    let list = MicrophonePriorityList(devices: [
      RankedInputDevice(uid: "a", name: "Built-in Microphone"),
      RankedInputDevice(uid: "b", name: "the system default microphone"),
      RankedInputDevice(uid: "c", name: "Unknown device"),
      RankedInputDevice(uid: "d", name: "AirPods Pro"),
    ])
    let blanked = list.blankingLegacyPlaceholderNames()
    #expect(blanked.devices.map(\.name) == ["", "", "", "AirPods Pro"])
  }

  @Test("blanking keeps the order the user set")
  func blankingPreservesOrder() {
    let list = MicrophonePriorityList(devices: [
      RankedInputDevice(uid: "usb-1", name: "USB Interface"),
      RankedInputDevice(uid: "built-in", name: "Built-in Microphone"),
      RankedInputDevice(uid: "bt-1", name: "AirPods Pro"),
    ])
    let blanked = list.blankingLegacyPlaceholderNames()
    #expect(blanked.devices.map(\.uid) == ["usb-1", "built-in", "bt-1"])
  }

  @Test("blanking is a no-op when nothing was ever named by the old migration")
  func blankingIsANoOpOtherwise() {
    let list = MicrophonePriorityList(devices: [
      RankedInputDevice(uid: "built-in", name: "MacBook Pro Microphone")
    ])
    #expect(list.blankingLegacyPlaceholderNames() == list)
  }
}
