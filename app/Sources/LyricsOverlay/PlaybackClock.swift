import Foundation
import Combine

/// Keeps its own clock so lyrics stay in sync even when the source (a throttled
/// background browser tab) only reports on play / pause / seek events.
final class PlaybackClock: ObservableObject {
    @Published private(set) var lines: [LyricLine] = []
    @Published private(set) var currentIndex: Int?
    @Published private(set) var isPlaying = false
    @Published private(set) var status: String? = "Waiting for music…"

    private var anchorPosition: TimeInterval = 0
    private var anchorDate = Date()
    private var rate: Double = 1

    /// Per-song correction in seconds. Positive shows lyrics earlier.
    var offset: TimeInterval = 0 { didSet { tick() } }
    private var timer: Timer?

    var position: TimeInterval {
        isPlaying ? anchorPosition + Date().timeIntervalSince(anchorDate) * rate : anchorPosition
    }

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    /// `status` is shown when `lines` is empty (e.g. "Searching lyrics…").
    func load(lines: [LyricLine], status: String? = nil) {
        self.lines = lines
        self.status = status
        tick()
    }

    func play(from position: TimeInterval? = nil) {
        anchorPosition = position ?? self.position
        anchorDate = Date()
        isPlaying = true
        tick()
    }

    func pause() {
        anchorPosition = position
        isPlaying = false
        tick()
    }

    func seek(to position: TimeInterval) {
        anchorPosition = position
        anchorDate = Date()
        tick()
    }

    /// Applies a report from the browser. Only re-anchors when we've drifted,
    /// so regular heartbeats don't make the highlighted line jitter.
    func sync(position p: TimeInterval, playing: Bool, rate newRate: Double = 1) {
        if playing {
            if !isPlaying || abs(position - p) > 0.4 || newRate != rate {
                anchorPosition = p
                anchorDate = Date()
                rate = newRate
                isPlaying = true
            }
        } else {
            isPlaying = false
            anchorPosition = p
        }
        tick()
    }

    private func tick() {
        let idx = LRC.currentIndex(in: lines, at: position + offset)
        if idx != currentIndex { currentIndex = idx }
    }
}
