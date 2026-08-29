// swift scripts/sign-licence.swift --generate
// VOCULA_SIGNING_KEY=$(security find-generic-password -w -s vocula-signing) \
//   swift scripts/sign-licence.swift buyer@example.com
//
// Substituted, never typed: a `VAR=value cmd` prefix is an ordinary command
// line, so a written-out key lands in ~/.zsh_history in clear text.
import CryptoKit
import Foundation

func base64URL(_ data: Data) -> String {
  data.base64EncodedString()
    .replacingOccurrences(of: "+", with: "-")
    .replacingOccurrences(of: "/", with: "_")
    .replacingOccurrences(of: "=", with: "")
}

func data(base64URL text: String) -> Data? {
  var s = text.replacingOccurrences(of: "-", with: "+")
    .replacingOccurrences(of: "_", with: "/")
  switch s.count % 4 {
  case 0: break
  case 2: s += "=="
  case 3: s += "="
  default: return nil
  }
  return Data(base64Encoded: s)
}

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data((message + "\n").utf8))
  exit(1)
}

let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.first == "--generate" {
  let key = Curve25519.Signing.PrivateKey()
  print("PRIVATE  \(base64URL(key.rawRepresentation))")
  print("PUBLIC   \(base64URL(key.publicKey.rawRepresentation))")
  print("")
  print("Keep PRIVATE out of this repository and out of every build. It lives")
  print("in exactly one place: the secret of whatever signs on a sale. Store it")
  print("with: security add-generic-password -a vocula -s vocula-signing -w")
  print("")
  print("Put PUBLIC at the FRONT of LicenceVerifier.publicKeysBase64URL and")
  print("leave the entries already there, unless nothing was ever SOLD under")
  print("one. The front entry is what mints; the rest are what keeps licences")
  print("already sold working. Deleting one is how a generation of licences is")
  print("revoked, and is the only way to.")
  print("")
  print("Do NOT commit a signed licence as a test fixture. A payload is a bare")
  print("holder string with no expiry, so any licence in the tree is a working")
  print("licence for everyone who clones it.")
  print("")
  print("Whatever mints on a sale must normalise the holder the way this script")
  print("does — trimmed, lowercased against a FIXED locale — or the same buyer")
  print("gets two different licences from the shop and from a re-issue by hand.")
  exit(0)
}

guard let typed = arguments.first, arguments.count == 1 else {
  fail("usage: sign-licence.swift --generate | <holder>   (VOCULA_SIGNING_KEY required)")
}

// The locale is fixed, never the machine's: on a Turkish Mac "I".lowercased()
// is "ı", and one address would mint two licences depending on where this ran.
let holder =
  typed
  .trimmingCharacters(in: .whitespacesAndNewlines)
  .lowercased(with: Locale(identifier: "en_US_POSIX"))
guard !holder.isEmpty else {
  fail("the holder is empty once trimmed")
}
guard let secret = ProcessInfo.processInfo.environment["VOCULA_SIGNING_KEY"],
  let secretBytes = data(base64URL: secret),
  let signingKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: secretBytes)
else {
  fail("VOCULA_SIGNING_KEY must hold the base64url private key from --generate")
}

let payload = Data(holder.utf8)
guard let signature = try? signingKey.signature(for: payload) else {
  fail("signing failed")
}
FileHandle.standardError.write(Data("signed: \(holder)\n".utf8))
print("\(base64URL(payload)).\(base64URL(signature))")
