import Foundation

enum Config {
    /// Where releases are published. If this is ever reset to a placeholder starting with "OWNER/",
    /// update checks and extension downloads switch off (so the app never talks to a repository
    /// that isn't yours). Keep in sync with REPO in install.sh.
    static let githubRepo = "iwandepe/lyrics-overlay"

    static let zipAsset = "LyricsOverlay.zip"                   // release assets: this, plus ".sig"
    static let extensionAsset = "lyrics-overlay-bridge.xpi"     // signed Firefox add-on

    /// Tests / local rehearsal: point the updater at a local JSON feed shaped like GitHub's releases API.
    private static var feedOverride: URL? {
        ProcessInfo.processInfo.environment["LYRICS_UPDATE_FEED"].flatMap { URL(string: $0) }
    }

    static var updatesConfigured: Bool { feedOverride != nil || !githubRepo.hasPrefix("OWNER/") }

    static var feedURL: URL {
        feedOverride ?? URL(string: "https://api.github.com/repos/\(githubRepo)/releases/latest")!
    }

    static var extensionInstallURL: URL? {
        githubRepo.hasPrefix("OWNER/") ? nil
            : URL(string: "https://github.com/\(githubRepo)/releases/latest/download/\(extensionAsset)")
    }

    static var versionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }
    static var version: Version { Version(versionString) ?? Version("0.0.0")! }

    /// False when running the bare dev binary (.build/LyricsOverlay) instead of the .app.
    static var isBundled: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    /// Downloads must be HTTPS. Plain HTTP is allowed only to loopback, and only with a test feed override.
    static func isAllowedDownload(_ url: URL) -> Bool {
        if url.scheme == "https" { return true }
        return feedOverride != nil && url.scheme == "http" && (url.host == "127.0.0.1" || url.host == "localhost")
    }
}
