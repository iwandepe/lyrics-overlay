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

    /// Tests: serve the extension file from a local server instead of GitHub.
    private static var extensionOverride: URL? {
        ProcessInfo.processInfo.environment["LYRICS_EXTENSION_URL"].flatMap { URL(string: $0) }
    }

    /// ~/Library/Application Support/LyricsOverlay (override: LYRICS_DATA_DIR, used by tests).
    /// Not ~/Downloads: apps get a macOS privacy prompt for that folder.
    static var dataDirectory: URL {
        if let custom = ProcessInfo.processInfo.environment["LYRICS_DATA_DIR"] {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LyricsOverlay", isDirectory: true)
    }

    static var updatesConfigured: Bool { feedOverride != nil || !githubRepo.hasPrefix("OWNER/") }

    static var feedURL: URL {
        feedOverride ?? URL(string: "https://api.github.com/repos/\(githubRepo)/releases/latest")!
    }

    static var releasesPageURL: URL? {
        githubRepo.hasPrefix("OWNER/") ? nil : URL(string: "https://github.com/\(githubRepo)/releases/latest")
    }

    static var extensionInstallURL: URL? {
        if let o = extensionOverride { return o }
        return githubRepo.hasPrefix("OWNER/") ? nil
            : URL(string: "https://github.com/\(githubRepo)/releases/latest/download/\(extensionAsset)")
    }

    static var versionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }
    static var version: Version { Version(versionString) ?? Version("0.0.0")! }

    /// False when running the bare dev binary (.build/LyricsOverlay) instead of the .app.
    static var isBundled: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    /// Downloads must be HTTPS. Plain HTTP is allowed only to loopback, and only with a test override.
    static func isAllowedDownload(_ url: URL) -> Bool {
        if url.scheme == "https" { return true }
        return (feedOverride != nil || extensionOverride != nil) && url.scheme == "http" && (url.host == "127.0.0.1" || url.host == "localhost")
    }
}
