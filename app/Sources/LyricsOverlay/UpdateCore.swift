import CryptoKit
import Foundation

/// Public half of the release-signing key (private half: ~/.config/lyrics-overlay/signing.key, never committed).
/// Updates are installed only if their signature verifies against this key. If the key is ever lost or
/// replaced, installed copies can't auto-update and people must reinstall, so back the private key up.
enum UpdateKey {
    static let publicKeyBase64 = "78QjGqys71RgdVPXuoBQ/osZYzs6UudLsJYAEpZzbxQ="
}

struct ReleaseInfo: Equatable {
    let version: Version
    let notes: String
    let zipURL: URL
    let signatureURL: URL

    static func == (a: ReleaseInfo, b: ReleaseInfo) -> Bool { a.version == b.version && a.zipURL == b.zipURL }
}

enum ReleaseFeed {
    private struct Asset: Decodable { let name: String; let browser_download_url: String }
    private struct Release: Decodable {
        let tag_name: String
        let body: String?
        let draft: Bool?
        let prerelease: Bool?
        let assets: [Asset]
    }

    /// Parses a GitHub "latest release" payload. Returns nil unless it has a version tag plus both the
    /// zip and its .sig asset, all on allowed URLs.
    static func parse(_ data: Data) -> ReleaseInfo? {
        guard let r = try? JSONDecoder().decode(Release.self, from: data),
              r.draft != true, r.prerelease != true,
              let version = Version(r.tag_name),
              let zip = r.assets.first(where: { $0.name == Config.zipAsset }),
              let sig = r.assets.first(where: { $0.name == Config.zipAsset + ".sig" }),
              let zipURL = URL(string: zip.browser_download_url), Config.isAllowedDownload(zipURL),
              let sigURL = URL(string: sig.browser_download_url), Config.isAllowedDownload(sigURL)
        else { return nil }
        return ReleaseInfo(version: version, notes: r.body ?? "", zipURL: zipURL, signatureURL: sigURL)
    }
}

enum UpdateVerifier {
    /// signatureBase64 is the text of the release's .sig asset.
    static func verify(_ data: Data, signatureBase64: String, publicKeyBase64: String = UpdateKey.publicKeyBase64) -> Bool {
        guard let keyData = Data(base64Encoded: publicKeyBase64),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
              let sig = Data(base64Encoded: signatureBase64.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return false }
        return key.isValidSignature(sig, for: data)
    }
}
