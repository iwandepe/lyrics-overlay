import Foundation

enum SyncMath {
    /// Shift (seconds) that makes `lineTime` line up with playback `position`.
    /// Positive = lyrics were late, so show them earlier. Rounded to 0.05s.
    static func shift(lineTime: TimeInterval, position: TimeInterval) -> Double {
        ((lineTime - position) * 20).rounded() / 20
    }
}

/// Per-song sync corrections, saved as readable JSON at
/// ~/Library/Application Support/LyricsOverlay/sync-offsets.json
/// (override the folder with LYRICS_DATA_DIR, used by tests).
final class SyncStore {
    private struct Entry: Codable {
        var offset: Double
        var updated: Date
    }

    private var entries: [String: Entry] = [:]
    private let url: URL

    init() {
        let fm = FileManager.default
        let dir: URL
        if let custom = ProcessInfo.processInfo.environment["LYRICS_DATA_DIR"] {
            dir = URL(fileURLWithPath: custom, isDirectory: true)
        } else {
            dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("LyricsOverlay", isDirectory: true)
        }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("sync-offsets.json")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: url),
           let loaded = try? decoder.decode([String: Entry].self, from: data) {
            entries = loaded
        } else if !fm.fileExists(atPath: url.path),
                  let old = UserDefaults.standard.dictionary(forKey: "offsets") as? [String: Double] {
            // One-time import of offsets saved by the first version (UserDefaults).
            for (k, v) in old where v != 0 { entries[k] = Entry(offset: v, updated: Date()) }
            save()
        }
    }

    func offset(for key: String) -> Double { entries[key]?.offset ?? 0 }

    /// Saving 0 removes the entry.
    func set(_ offset: Double, for key: String) {
        if offset == 0 { entries[key] = nil } else { entries[key] = Entry(offset: offset, updated: Date()) }
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(entries) { try? data.write(to: url, options: .atomic) }
    }
}
