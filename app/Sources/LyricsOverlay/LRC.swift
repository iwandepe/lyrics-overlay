import Foundation

struct LyricLine: Equatable {
    let time: TimeInterval
    let text: String
}

enum LRC {
    /// Parses synced lyrics like `[01:23.45] some line`. Supports multiple
    /// timestamps per line and ignores metadata tags such as `[ar:Artist]`.
    static func parse(_ raw: String) -> [LyricLine] {
        let pattern = #"\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        var lines: [LyricLine] = []
        for rawLine in raw.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            let ns = line as NSString
            let matches = regex.matches(in: line, range: NSRange(location: 0, length: ns.length))
            guard let last = matches.last else { continue }
            let text = ns.substring(from: last.range.upperBound).trimmingCharacters(in: .whitespaces)

            for m in matches {
                let min = Double(ns.substring(with: m.range(at: 1))) ?? 0
                let sec = Double(ns.substring(with: m.range(at: 2))) ?? 0
                var frac = 0.0
                if m.range(at: 3).location != NSNotFound {
                    let f = ns.substring(with: m.range(at: 3))
                    frac = (Double(f) ?? 0) / pow(10, Double(f.count))
                }
                lines.append(LyricLine(time: min * 60 + sec + frac, text: text))
            }
        }
        return lines.sorted { $0.time < $1.time }
    }

    /// Index of the line being sung at `position`, or nil before the first line.
    static func currentIndex(in lines: [LyricLine], at position: TimeInterval) -> Int? {
        var lo = 0, hi = lines.count - 1, found: Int?
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lines[mid].time <= position { found = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        return found
    }
}
