import Foundation
import Combine

struct UpdateError: LocalizedError {
    let message: String
    init(_ m: String) { message = m }
    var errorDescription: String? { message }
}

/// Checks GitHub Releases for a newer version and installs it in place.
/// Safety: the download is only installed if its Ed25519 signature verifies against the key embedded in
/// the app (see UpdateCore.swift), and the unpacked app must have the same bundle id and the announced version.
final class Updater: ObservableObject {
    enum State: Equatable {
        case idle, checking, upToDate
        case available(ReleaseInfo)
        case installing
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    /// Called once the swap helper is running; the app should quit so the helper can replace it.
    var relaunch: (() -> Void)?

    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 30
        c.httpAdditionalHeaders = ["User-Agent": "lyrics-overlay-updater"]
        return URLSession(configuration: c)
    }()

    private func set(_ s: State) { DispatchQueue.main.async { self.state = s } }

    // MARK: Check

    func check() {
        guard Config.updatesConfigured else {
            set(.failed("Updates aren't set up in this build yet."))
            return
        }
        if state == .installing || state == .checking { return }
        set(.checking)
        Task {
            do {
                var req = URLRequest(url: Config.feedURL)
                req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                let (data, resp) = try await session.data(for: req)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if code == 404 { set(.upToDate); return }           // no releases published yet
                guard code == 200 else { throw UpdateError("The update server answered with an error (\(code)).") }
                guard let release = ReleaseFeed.parse(data) else { throw UpdateError("Couldn't read the latest release.") }
                set(release.version > Config.version ? .available(release) : .upToDate)
            } catch {
                set(.failed(error.localizedDescription))
            }
        }
    }

    // MARK: Install

    func install(_ release: ReleaseInfo) {
        guard Config.isBundled else {
            set(.failed("Updating works for the installed app, not a development build."))
            return
        }
        set(.installing)
        Task {
            var staging: URL?
            do {
                let target = Bundle.main.bundleURL
                let parent = target.deletingLastPathComponent()
                guard FileManager.default.isWritableFile(atPath: parent.path) else {
                    throw UpdateError("No permission to update the app in \(parent.path). Download the new version manually.")
                }

                let zip = try await download(release.zipURL)
                let sig = String(decoding: try await download(release.signatureURL), as: UTF8.self)
                guard UpdateVerifier.verify(zip, signatureBase64: sig) else {
                    throw UpdateError("The update's signature is invalid, so it was not installed.")
                }

                // Stage next to the app so the final swap is an atomic rename on the same volume.
                let dir = parent.appendingPathComponent(".LyricsOverlay-update-\(UUID().uuidString)")
                staging = dir
                let unpacked = dir.appendingPathComponent("unpacked")
                try FileManager.default.createDirectory(at: unpacked, withIntermediateDirectories: true)
                let zipFile = dir.appendingPathComponent("update.zip")
                try zip.write(to: zipFile)
                try run("/usr/bin/ditto", ["-x", "-k", zipFile.path, unpacked.path])

                guard let newApp = try FileManager.default.contentsOfDirectory(at: unpacked, includingPropertiesForKeys: nil)
                    .first(where: { $0.pathExtension == "app" }),
                      let info = Bundle(url: newApp)?.infoDictionary,
                      info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
                      let v = (info["CFBundleShortVersionString"] as? String).flatMap(Version.init), v == release.version
                else { throw UpdateError("The downloaded update didn't match what was announced, so it was not installed.") }

                try startSwapHelper(target: target, newApp: newApp, staging: dir)
                DispatchQueue.main.async { self.relaunch?() }
            } catch {
                if let s = staging { try? FileManager.default.removeItem(at: s) }
                set(.failed(error.localizedDescription))
            }
        }
    }

    private func download(_ url: URL) async throws -> Data {
        guard Config.isAllowedDownload(url) else { throw UpdateError("Refusing to download from \(url.absoluteString).") }
        let (data, resp) = try await session.data(from: url)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError("The download failed.") }
        guard data.count < 200_000_000 else { throw UpdateError("The download is unexpectedly large.") }
        return data
    }

    private func run(_ tool: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw UpdateError("Couldn't unpack the update.") }
    }

    /// A detached shell waits for this process to exit, swaps the bundles (rolling back on failure),
    /// cleans up, and reopens the app. An app can't replace itself while it's running.
    private func startSwapHelper(target: URL, newApp: URL, staging: URL) throws {
        let script = """
        while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
        bak="$2.old"
        rm -rf "$bak"
        if mv "$2" "$bak" && mv "$3" "$2"; then
          rm -rf "$bak"
        else
          [ -e "$bak" ] && [ ! -e "$2" ] && mv "$bak" "$2"
        fi
        rm -rf "$4"
        /usr/bin/open "$2"
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script, "sh", String(ProcessInfo.processInfo.processIdentifier),
                       target.path, newApp.path, staging.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
    }
}
