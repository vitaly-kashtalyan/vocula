import CryptoKit
import Foundation
import Security
import VoculaKit

struct MeetingKeychain: Sendable {
  var copyMatching: @Sendable (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus
  var add: @Sendable (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus

  static let system = MeetingKeychain(copyMatching: SecItemCopyMatching, add: SecItemAdd)
}

struct MeetingSeal: HistoryCipher {
  enum Failure: Error {
    case sealFailed
  }

  let key: SymmetricKey

  init(key: SymmetricKey) { self.key = key }

  func seal(_ plaintext: Data) throws -> Data {
    guard let sealed = try AES.GCM.seal(plaintext, using: key).combined else {
      throw Failure.sealFailed
    }
    return sealed
  }

  func open(_ ciphertext: Data) throws -> Data {
    try AES.GCM.open(try AES.GCM.SealedBox(combined: ciphertext), using: key)
  }
}

enum MeetingKey {
  static func query() -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "app.vocula.mac",
      kSecAttrAccount as String: "meetings",
    ]
  }

  static func cipher(
    keychain: MeetingKeychain = .system,
    isSecondCopy: Bool = VoculaAppDelegate.isSecondCopy
  ) throws -> MeetingSeal {
    if isSecondCopy { throw MeetingFailure.secondCopy }
    var lookup = query()
    lookup[kSecReturnData as String] = true
    var item: CFTypeRef?
    let status = keychain.copyMatching(lookup as CFDictionary, &item)
    let existing = status == errSecSuccess ? item as? Data : nil
    switch MeetingKeyRule.step(afterLookup: status, keyByteCount: existing?.count) {
    case .use:
      return MeetingSeal(key: SymmetricKey(data: existing ?? Data()))
    case .mint:
      let fresh = SymmetricKey(size: .bits256)
      var attributes = query()
      attributes[kSecValueData as String] = fresh.withUnsafeBytes { Data($0) }
      attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
      let added = keychain.add(attributes as CFDictionary, nil)
      guard added == errSecSuccess else {
        throw MeetingFailure.failed(step: "key", code: Int32(added))
      }
      return MeetingSeal(key: fresh)
    case .refuse(let code):
      throw MeetingFailure.failed(step: "key", code: code)
    }
  }
}
