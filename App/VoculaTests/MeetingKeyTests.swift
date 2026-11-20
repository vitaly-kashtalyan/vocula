import CryptoKit
import Foundation
import Security
import Testing
import VoculaKit

@testable import Vocula

private final class RecordingKeychain: @unchecked Sendable {
  enum Call: Equatable { case copy, add }

  private let lock = NSLock()
  private var recorded: [Call] = []
  private var addedAttributes: [String: Any] = [:]
  private let lookupStatus: OSStatus
  private let lookupData: Data?
  private let addStatus: OSStatus

  init(lookupStatus: OSStatus, lookupData: Data? = nil, addStatus: OSStatus = errSecSuccess) {
    self.lookupStatus = lookupStatus
    self.addStatus = addStatus
    self.lookupData = lookupData
  }

  var calls: [Call] { lock.withLock { recorded } }
  var added: [String: Any] { lock.withLock { addedAttributes } }

  var keychain: MeetingKeychain {
    MeetingKeychain(
      copyMatching: { _, result in
        self.lock.withLock { self.recorded.append(.copy) }
        if let data = self.lookupData { result?.pointee = data as CFData }
        return self.lookupStatus
      },
      add: { attributes, _ in
        self.lock.withLock {
          self.recorded.append(.add)
          self.addedAttributes = attributes as? [String: Any] ?? [:]
        }
        return self.addStatus
      })
  }
}

@Suite("Meeting key")
struct MeetingKeyTests {
  @Test func theItemIsTheMeetingsOwn() {
    let query = MeetingKey.query()
    #expect(query[kSecAttrService as String] as? String == "app.vocula.mac")
    #expect(query[kSecAttrAccount as String] as? String == "meetings")
    #expect(query[kSecClass as String] as? String == kSecClassGenericPassword as String)
  }

  @Test func theRuleMatchesSecurity() {
    #expect(MeetingKeyRule.itemNotFound == errSecItemNotFound)
  }

  @Test func aSecondCopyTouchesNoKeychain() {
    let recording = RecordingKeychain(lookupStatus: errSecItemNotFound)
    #expect(throws: MeetingFailure.secondCopy) {
      try MeetingKey.cipher(keychain: recording.keychain, mayMint: true)
    }
    #expect(recording.calls == [])
  }

  @Test func anExistingKeyTakesOneLookup() throws {
    let key = SymmetricKey(size: .bits256)
    let recording = RecordingKeychain(
      lookupStatus: errSecSuccess, lookupData: key.withUnsafeBytes { Data($0) })
    let cipher = try MeetingKey.cipher(
      keychain: recording.keychain, isSecondCopy: false, mayMint: true)
    #expect(recording.calls == [.copy])
    let plaintext = Data("meeting".utf8)
    #expect(try MeetingSeal(key: key).open(try cipher.seal(plaintext)) == plaintext)
  }

  @Test func aMissingKeyIsMintedWithoutADelete() throws {
    let recording = RecordingKeychain(lookupStatus: errSecItemNotFound)
    let cipher = try MeetingKey.cipher(
      keychain: recording.keychain, isSecondCopy: false, mayMint: true)
    #expect(recording.calls == [.copy, .add])
    #expect(recording.added[kSecAttrService as String] as? String == "app.vocula.mac")
    #expect(recording.added[kSecAttrAccount as String] as? String == "meetings")
    let stored = try #require(recording.added[kSecValueData as String] as? Data)
    let plaintext = Data("meeting".utf8)
    #expect(
      try MeetingSeal(key: SymmetricKey(data: stored)).open(try cipher.seal(plaintext)) == plaintext
    )
    #expect(
      recording.added[kSecAttrAccessible as String] as? String
        == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
    #expect((recording.added[kSecValueData as String] as? Data)?.count == 32)
  }

  @Test func aRefusedAddFailsTheKey() {
    let recording = RecordingKeychain(lookupStatus: errSecItemNotFound, addStatus: -25299)
    #expect(throws: MeetingFailure.failed(step: "key", code: -25299)) {
      try MeetingKey.cipher(keychain: recording.keychain, isSecondCopy: false, mayMint: true)
    }
    #expect(recording.calls == [.copy, .add])
  }

  @Test func aLockedKeychainMintsNothing() {
    let recording = RecordingKeychain(lookupStatus: -25308)
    #expect(throws: MeetingFailure.failed(step: "key", code: -25308)) {
      try MeetingKey.cipher(keychain: recording.keychain, isSecondCopy: false, mayMint: true)
    }
    #expect(recording.calls == [.copy])
  }

  @Test func theExistingKeyLookupNeverAdds() {
    let recording = RecordingKeychain(lookupStatus: errSecItemNotFound)
    #expect(throws: MeetingFailure.failed(step: "key", code: errSecItemNotFound)) {
      try MeetingKey.cipher(keychain: recording.keychain, isSecondCopy: false, mayMint: false)
    }
    #expect(recording.calls == [.copy])
  }

  @Test func theExistingKeyLookupRefusesASecondCopy() {
    let recording = RecordingKeychain(lookupStatus: errSecItemNotFound)
    #expect(throws: MeetingFailure.secondCopy) {
      try MeetingKey.cipher(keychain: recording.keychain, mayMint: false)
    }
    #expect(recording.calls == [])
  }

  @Test func aSealOpensOnlyWithItsKey() throws {
    let plaintext = Data("meeting".utf8)
    let seal = MeetingSeal(key: SymmetricKey(size: .bits256))
    let sealed = try seal.seal(plaintext)
    #expect(sealed != plaintext)
    #expect(try seal.open(sealed) == plaintext)
    #expect(throws: (any Error).self) {
      try MeetingSeal(key: SymmetricKey(size: .bits256)).open(sealed)
    }
  }
}
