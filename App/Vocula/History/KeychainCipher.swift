import CryptoKit
import Foundation
import Security
import VoculaKit

struct KeychainCipher: HistoryCipher {
  enum Failure: Error {
    case keyUnavailable(OSStatus)
    case sealFailed
  }

  private let account: String

  init(account: String = "history") { self.account = account }

  func seal(_ plaintext: Data) throws -> Data {
    guard let sealed = try AES.GCM.seal(plaintext, using: key()).combined else {
      throw Failure.sealFailed
    }
    return sealed
  }

  func open(_ ciphertext: Data) throws -> Data {
    try AES.GCM.open(try AES.GCM.SealedBox(combined: ciphertext), using: key())
  }

  private func key() throws -> SymmetricKey {
    switch read() {
    case .found(let existing):
      return existing
    case .absent:
      let fresh = SymmetricKey(size: .bits256)
      try store(fresh)
      return fresh
    case .unavailable(let status):
      throw Failure.keyUnavailable(status)
    }
  }

  private enum Lookup {
    case found(SymmetricKey)
    case absent
    case unavailable(OSStatus)
  }

  static func meansNoKeyExists(_ status: OSStatus) -> Bool {
    status == errSecItemNotFound
  }

  private func query() -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "app.vocula.mac",
      kSecAttrAccount as String: account,
    ]
  }

  private func read() -> Lookup {
    var request = query()
    request[kSecReturnData as String] = true
    var item: CFTypeRef?
    let status = SecItemCopyMatching(request as CFDictionary, &item)
    if status == errSecSuccess, let data = item as? Data {
      return .found(SymmetricKey(data: data))
    }
    return Self.meansNoKeyExists(status) ? .absent : .unavailable(status)
  }

  private func store(_ key: SymmetricKey) throws {
    var request = query()
    request[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
    request[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    SecItemDelete(query() as CFDictionary)
    let status = SecItemAdd(request as CFDictionary, nil)
    guard status == errSecSuccess else { throw Failure.keyUnavailable(status) }
  }
}
