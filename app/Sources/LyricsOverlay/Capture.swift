import AppKit

/// Marketing helper: `LYRICS_CAPTURE=/dir` plays a scripted ~16s demo (lyrics advancing, hover,
/// a click-to-fix) and writes transparent 2x PNG frames of the overlay, then exits.
/// Driven by docs/make-assets.sh. Not used in normal operation.
enum Capture {
    static let fps = 10.0
    static let seconds = 16.0

    static func run(panel: OverlayPanel, controller: Controller, dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        OverlayPanel.pollingEnabled = false          // the script controls hover, not the real pointer
        controller.autoScroll = true
        controller.showDemo()
        controller.clock.seek(to: 7)
        controller.clock.play(from: 7)
        controller.nudge(-2.0)                        // start with lyrics 2s late, then "fix" them

        var frame = 0
        var clicked = false
        Timer.scheduledTimer(withTimeInterval: 1 / fps, repeats: true) { timer in
            let t = Double(frame) / fps
            controller.hovering = t >= 9.5 && t < 14.5
            if t >= 11.6 && !clicked {
                clicked = true
                // The line sung at this moment is the one after the highlighted one.
                controller.syncLine((controller.clock.currentIndex ?? 0) + 1)
            }
            write(panel.contentView, to: String(format: "%@/frame_%03d.png", dir, frame))
            frame += 1
            if Double(frame) / fps >= seconds { timer.invalidate(); NSApp.terminate(nil) }
        }
    }

    private static func write(_ v: NSView?, to path: String) {
        guard let v, let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(v.bounds.width * 2), pixelsHigh: Int(v.bounds.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = v.bounds.size                      // 2x pixels for the same point size
        v.cacheDisplay(in: v.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
