import Foundation

struct SongQuery: Equatable {
    var artist: String?
    var track: String
}

/// Turns messy YouTube metadata ("Artist - Song (Official Video) [4K]") into
/// something LRCLIB can match.
enum TitleCleaner {
    private static func rx(_ s: String, _ pattern: String, _ template: String = "", ci: Bool = true) -> String {
        s.replacingOccurrences(of: pattern, with: template,
                               options: ci ? [.regularExpression, .caseInsensitive] : [.regularExpression])
    }

    private static let bracketNoise =
        #"\s*[\(\[\{【][^\)\]\}】]*\b(?:official|video|audio|lyrics?|mv|m\/v|hd|hq|4k|8k|remaster(?:ed)?|visuali[sz]er|clip|explicit|feat\.?|ft\.?|featuring)\b[^\)\]\}】]*[\)\]\}】]"#
    private static let trailingPipe = #"\s*[|｜].*$"#
    private static let trailingDashNoise =
        #"\s*[-–—:]\s*(?:official\s+)?(?:music\s+)?(?:video|audio|lyrics?(?:\s+video)?|visuali[sz]er)\s*$"#
    private static let trailingOfficial = #"\s+official\s+(?:music\s+)?(?:video|audio|lyric video)\s*$"#
    private static let featSuffix = #"\s+(?:feat|ft|featuring)\b\.?\s+.*$"#

    static func stripNoise(_ s: String) -> String {
        var t = s
        t = rx(t, bracketNoise)
        t = rx(t, trailingPipe)
        t = rx(t, trailingDashNoise)
        t = rx(t, trailingOfficial)
        return tidy(t)
    }

    static func stripFeat(_ s: String) -> String { tidy(rx(s, featSuffix)) }

    static func tidy(_ s: String) -> String {
        var t = rx(s, #"\s{2,}"#, " ")
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”"))
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func cleanChannel(_ c: String) -> String {
        var s = rx(c, #"\s*-\s*Topic$"#)
        let hadVevo = s.range(of: "vevo", options: .caseInsensitive) != nil
        s = rx(s, #"\s*VEVO$"#)
        s = rx(s, #"\s+official$"#)
        if hadVevo { s = rx(s, #"([a-z])([A-Z])"#, "$1 $2", ci: false) }   // TaylorSwift -> Taylor Swift
        return tidy(s)
    }

    /// `artist` is trusted when present (YouTube Music supplies a real one);
    /// otherwise we split "Artist - Song" from the title, then fall back to the channel name.
    static func query(title: String, artist: String?, channel: String?) -> SongQuery {
        let cleaned = stripNoise(title)

        if let a = artist?.trimmingCharacters(in: .whitespaces), !a.isEmpty {
            return SongQuery(artist: tidy(a), track: stripFeat(cleaned))
        }

        let seps = [" - ", " – ", " — "]
        let hit = seps.compactMap { cleaned.range(of: $0) }.min { $0.lowerBound < $1.lowerBound }
        if let r = hit {
            let left = stripFeat(String(cleaned[..<r.lowerBound]))
            let right = stripFeat(String(cleaned[r.upperBound...]))
            if !left.isEmpty, !right.isEmpty { return SongQuery(artist: left, track: right) }
        }

        let ch = channel.map(cleanChannel).flatMap { $0.isEmpty ? nil : $0 }
        return SongQuery(artist: ch, track: stripFeat(cleaned))
    }
}
