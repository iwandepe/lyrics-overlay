import Foundation

/// Downloads the signed Firefox extension (.xpi) and saves it locally so the browser can install it
/// from a file. Firefox verifies Mozilla's signature itself when installing, so a tampered file is rejected there.
enum ExtensionFile {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// An .xpi is a zip: it starts with "PK\u{3}\u{4}". Rejects HTML error pages and truncated downloads.
    static func isPlausible(_ data: Data) -> Bool {
        data.count > 200 && data.count < 5_000_000 && data.prefix(4) == Data([0x50, 0x4B, 0x03, 0x04])
    }

    static var localURL: URL { Config.dataDirectory.appendingPathComponent(Config.extensionAsset) }

    /// Returns the saved file's URL. An existing saved copy is only replaced by a valid download.
    static func download(from url: URL, session: URLSession = URLSession(configuration: .ephemeral)) async throws -> URL {
        guard Config.isAllowedDownload(url) else { throw Failure(message: "Refusing to download from \(url.host ?? "that address").") }
        let (data, resp) = try await session.data(from: url)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 404 { throw Failure(message: "The extension file hasn't been published yet.") }
        guard code == 200 else { throw Failure(message: "The download failed (HTTP \(code)).") }
        guard isPlausible(data) else { throw Failure(message: "The download isn't a valid extension file.") }
        try FileManager.default.createDirectory(at: Config.dataDirectory, withIntermediateDirectories: true)
        try data.write(to: localURL, options: .atomic)
        return localURL
    }
}
