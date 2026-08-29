import Foundation

public protocol HistoryCipher: Sendable {
  func seal(_ plaintext: Data) throws -> Data
  func open(_ ciphertext: Data) throws -> Data
}

public struct PassthroughCipher: HistoryCipher {
  public init() {}
  public func seal(_ plaintext: Data) throws -> Data { plaintext }
  public func open(_ ciphertext: Data) throws -> Data { ciphertext }
}
