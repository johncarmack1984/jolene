// Checks an update archive's EdDSA signature against the public key in an app's Info.plist,
// which is the check every installed copy makes before it installs the archive.
//
//     swift Tools/verify-update-signature.swift Jolene.app SIGNATURE Jolene-1.2.3.zip
import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(1)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 3 else { fail("usage: verify-update-signature.swift APP SIGNATURE ARCHIVE") }
let (app, signatureText, archive) = (arguments[0], arguments[1], arguments[2])

guard let info = NSDictionary(contentsOfFile: "\(app)/Contents/Info.plist"),
      let keyText = info["SUPublicEDKey"] as? String,
      let keyData = Data(base64Encoded: keyText),
      let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData)
else { fail("\(app) has no usable SUPublicEDKey") }
guard let signature = Data(base64Encoded: signatureText) else { fail("The signature isn't base64.") }
guard let contents = FileManager.default.contents(atPath: archive) else { fail("Can't read \(archive)") }
guard key.isValidSignature(signature, for: contents) else {
    fail("\(archive) isn't signed with the key \(app) trusts, so installed copies would reject it.")
}
print("\(archive) is signed with the key \(app) trusts.")
