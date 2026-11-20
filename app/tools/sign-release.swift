// Release signing helper (Ed25519). Updates are only installed if their signature verifies
// against the public key embedded in the app, so only the holder of the private key can ship updates.
//   sign-release gen  <keyfile>        create a keypair; writes the private key, prints the public key
//   sign-release sign <keyfile> <file> print the base64 signature of <file>
//   sign-release pub  <keyfile>        print the public key
import CryptoKit
import Foundation

func fail(_ m: String) -> Never { FileHandle.standardError.write(Data((m + "\n").utf8)); exit(1) }
let a = CommandLine.arguments
guard a.count >= 3 else { fail("usage: sign-release gen|sign|pub <keyfile> [file]") }

func loadKey(_ path: String) -> Curve25519.Signing.PrivateKey {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8),
          let raw = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else { fail("cannot read key at \(path)") }
    return key
}

switch a[1] {
case "gen":
    if FileManager.default.fileExists(atPath: a[2]) { fail("\(a[2]) already exists; refusing to overwrite a signing key") }
    let key = Curve25519.Signing.PrivateKey()
    try FileManager.default.createDirectory(atPath: (a[2] as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: a[2], contents: Data(key.rawRepresentation.base64EncodedString().utf8),
                                   attributes: [.posixPermissions: 0o600])
    print(key.publicKey.rawRepresentation.base64EncodedString())
case "pub":
    print(loadKey(a[2]).publicKey.rawRepresentation.base64EncodedString())
case "sign":
    guard a.count >= 4, let data = FileManager.default.contents(atPath: a[3]) else { fail("cannot read file to sign") }
    print(try loadKey(a[2]).signature(for: data).base64EncodedString())
default:
    fail("unknown command \(a[1])")
}
