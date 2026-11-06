// Checks a Sparkle EdDSA signature against a public key, the way an installed Jumpr will.
//
//   swift scripts/verify-ed-signature.swift <public-key-base64> <signature-base64> <file>
//
// Exits 0 when the signature is valid. scripts/appcast.sh runs it with the key from the
// built app's Info.plist, so an appcast signed with a key the app does not carry is refused.
import CryptoKit
import Foundation

let args = CommandLine.arguments
guard args.count == 4 else {
    FileHandle.standardError.write(Data("usage: verify-ed-signature.swift <public-key> <signature> <file>\n".utf8))
    exit(2)
}
guard let keyData = Data(base64Encoded: args[1]), let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else {
    FileHandle.standardError.write(Data("not an Ed25519 public key (base64 of 32 bytes)\n".utf8))
    exit(2)
}
guard let signature = Data(base64Encoded: args[2]) else {
    FileHandle.standardError.write(Data("signature is not base64\n".utf8))
    exit(2)
}
guard let file = FileManager.default.contents(atPath: args[3]) else {
    FileHandle.standardError.write(Data("cannot read \(args[3])\n".utf8))
    exit(2)
}
exit(key.isValidSignature(signature, for: file) ? 0 : 1)
