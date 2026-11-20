import Foundation
import Combine

/// Glue: browser state in -> lyrics lookup -> clock / overlay visibility out.
/// Also owns the UI-facing state (hover, scroll mode, per-song sync offset).
final class Controller: ObservableObject {
    let clock = PlaybackClock()
    var onVisibilityChange: ((Bool) -> Void)?

    @Published var hovering = false
    /// true: lyrics follow the song. false: you scroll freely.
    @Published var autoScroll: Bool {
        didSet { UserDefaults.standard.set(autoScroll, forKey: "autoScroll") }
    }
    /// Saved correction for the current song (positive = show lyrics earlier).
    @Published private(set) var userOffset: Double = 0
    @Published private(set) var toast: String?
    /// For the setup guide.
    @Published var extensionConnected = false
    @Published private(set) var songSeen = false

    /// Lines are shown this much early: the display refreshes every 50ms and fades in over 250ms,
    /// and you want to read a line just before it's sung, not as it starts.
    private static let lead = 0.3

    private let service = LyricsService()
    private let store = SyncStore()
    private var currentKey: String?
    private var toastToken = 0

    init() {
        autoScroll = UserDefaults.standard.object(forKey: "autoScroll") as? Bool ?? true
    }

    // MARK: Browser state

    func handle(_ s: PlayerState) {
        // Hide during ads; the song's lyrics resume when the next report arrives.
        if s.ad == true {
            clock.pause()
            onVisibilityChange?(false)
            return
        }
        onVisibilityChange?(true)
        if !songSeen { songSeen = true }

        let q = TitleCleaner.query(title: s.title, artist: s.artist, channel: s.channel)
        let key = "\(q.artist ?? "")|\(q.track)"

        if key != currentKey {
            currentKey = key
            applyOffset(store.offset(for: key))
            clock.load(lines: [], status: "Searching lyrics…")
            log("now playing: \(q.artist ?? "?") – \(q.track)  (video \(fmt(s.duration)), raw title: \(s.title))")
            Task { [weak self] in
                let match = await self?.service.lyrics(for: q, duration: s.duration)
                DispatchQueue.main.async {
                    guard let self, self.currentKey == key else { return }   // song changed meanwhile
                    if let m = match {
                        self.log("matched: \(m.artistName) – \(m.trackName)  (lrclib \(fmt(m.duration)), first line at \(fmt(m.lines.first?.time)))")
                        self.clock.load(lines: m.lines)
                    } else {
                        self.log("no synced lyrics found")
                        self.clock.load(lines: [], status: "No synced lyrics for “\(q.track)”")
                    }
                }
            }
        }

        clock.sync(position: s.position ?? 0, playing: s.playing ?? false, rate: s.rate ?? 1)
    }

    // MARK: Sync fixes

    /// "This line is being sung right now": saves the shift for this song.
    func syncLine(_ index: Int) {
        guard currentKey != nil, clock.lines.indices.contains(index) else { return }
        let v = SyncMath.shift(lineTime: clock.lines[index].time, position: clock.position)
        setOffset(v)
        showToast(String(format: "Synced · saved %+.2fs", v))
    }

    /// Shift the current song's lyrics. Positive = show lines earlier.
    func nudge(_ delta: Double) { setOffset(((userOffset + delta) * 20).rounded() / 20) }

    func resetOffset() {
        setOffset(0)
        showToast("Sync reset")
    }

    private func setOffset(_ v: Double) {
        guard let key = currentKey else { return }
        store.set(v, for: key)
        applyOffset(v)
        log("offset for \(key): \(v)s")
    }

    private func applyOffset(_ v: Double) {
        userOffset = v
        clock.offset = Self.lead + v
    }

    private func showToast(_ text: String) {
        toastToken += 1
        let token = toastToken
        toast = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            if self?.toastToken == token { self?.toast = nil }
        }
    }

    // MARK: Demo / logging

    func showDemo() {
        currentKey = "demo"
        applyOffset(store.offset(for: "demo"))
        clock.load(lines: LRC.parse(SampleLyrics.lrc))
        clock.seek(to: 0)
        clock.play(from: 0)
        onVisibilityChange?(true)
    }

    private func log(_ s: String) { print("[lyrics] \(s)") }
}

private func fmt(_ d: Double?) -> String { d.map { String(format: "%.1fs", $0) } ?? "?" }
