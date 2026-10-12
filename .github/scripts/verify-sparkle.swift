import CryptoKit
import Foundation

let key = try Curve25519.Signing.PublicKey(rawRepresentation: Data(base64Encoded: "AGCY8w5vHirVfGGDGc8Szc5iuOqupZSh9pMj/Qs67XI=")!)
let archive = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let signatureText = try String(contentsOfFile: CommandLine.arguments[2], encoding: .utf8)
guard let signature = Data(base64Encoded: signatureText), key.isValidSignature(signature, for: archive) else {
    fatalError("Sparkle signature does not match the app's update public key")
}
