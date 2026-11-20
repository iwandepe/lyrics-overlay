import Foundation

struct LyricsMatch {
    let lines: [LyricLine]
    let trackName: String
    let artistName: String
    let duration: Double?
}

/// Looks up synced lyrics on LRCLIB (https://lrclib.net), a free API with no key.
/// Only the cleaned song title / artist / duration are sent.
final class LyricsService {
    private struct Track: Decodable {
        var trackName: String?
        var artistName: String?
        var duration: Double?
        var syncedLyrics: String?
        var hasSynced: Bool { !(syncedLyrics ?? "").isEmpty }
    }

    private let session: URLSession
    private var cache: [String: LyricsMatch] = [:]

    init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 8
        cfg.httpAdditionalHeaders = ["User-Agent": "lyrics-overlay/0.1 (personal project)"]
        session = URLSession(configuration: cfg)
    }

    /// Returns synced lyrics plus which LRCLIB track matched, or nil when nothing suitable was found.
    func lyrics(for q: SongQuery, duration: Double?) async -> LyricsMatch? {
        let key = "\(q.artist ?? "")|\(q.track)"
        if let hit = cache[key] { return hit }

        var found: Track?

        // 1. Exact match (needs artist + duration).
        if let artist = q.artist, let d = duration, d > 0 {
            let items = [("track_name", q.track), ("artist_name", artist), ("duration", String(Int(d.rounded())))]
            if let t: Track = await fetch("get", items), t.hasSynced { found = t }
        }
        // 2. Structured search.
        if found == nil {
            var items = [("track_name", q.track)]
            if let a = q.artist { items.append(("artist_name", a)) }
            found = best(await search(items), duration: duration)
        }
        // 3. Free-text search.
        if found == nil {
            let text = [q.artist, q.track].compactMap { $0 }.joined(separator: " ")
            found = best(await search([("q", text)]), duration: duration)
        }

        guard let t = found, let raw = t.syncedLyrics else { return nil }
        let lines = LRC.parse(raw)
        guard !lines.isEmpty else { return nil }
        let match = LyricsMatch(lines: lines, trackName: t.trackName ?? q.track,
                                artistName: t.artistName ?? q.artist ?? "?", duration: t.duration)
        cache[key] = match
        return match
    }

    /// Among search hits with synced lyrics, picks the closest duration (within 15s when known).
    private func best(_ tracks: [Track], duration: Double?) -> Track? {
        let synced = tracks.filter(\.hasSynced)
        guard let d = duration, d > 0 else { return synced.first }
        let scored = synced.compactMap { t -> (Double, Track)? in
            guard let td = t.duration else { return nil }
            return (abs(td - d), t)
        }
        guard let top = scored.min(by: { $0.0 < $1.0 }), top.0 <= 15 else { return nil }
        return top.1
    }

    private func search(_ items: [(String, String)]) async -> [Track] {
        (await fetch("search", items) as [Track]?) ?? []
    }

    private func fetch<T: Decodable>(_ path: String, _ items: [(String, String)]) async -> T? {
        var c = URLComponents(string: "https://lrclib.net/api/\(path)")!
        c.queryItems = items.map { URLQueryItem(name: $0.0, value: $0.1) }
        guard let url = c.url else { return nil }
        do {
            let (data, resp) = try await session.data(from: url)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            return nil
        }
    }
}
