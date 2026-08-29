import Security
import Testing

@testable import Vocula

struct KeychainCipherTests {
  @Test("An absent item is the only status that may mint a fresh key")
  func absentItemMintsAKey() {
    #expect(KeychainCipher.meansNoKeyExists(errSecItemNotFound))
  }

  @Test(
    "An unreachable key is never mistaken for an absent one",
    arguments: [
      errSecInteractionNotAllowed, errSecAuthFailed,
      errSecUserCanceled, errSecNotAvailable,
      errSecInvalidKeychain, errSecDecode, errSecSuccess,
    ])
  func unreachableKeyIsNotAbsent(_ status: OSStatus) {
    #expect(KeychainCipher.meansNoKeyExists(status) == false)
  }
}
