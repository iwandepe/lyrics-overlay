import AppKit
import SwiftUI

enum Corner: String, CaseIterable {
    case topRight = "Top right"
    case bottomLeft = "Bottom left"
    case topLeft = "Top left"
    case bottomRight = "Bottom right"
}

/// Lets the first click on a non-key panel reach the controls instead of being swallowed.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Borderless, transparent, always-on-top window that never steals focus.
/// It is click-through until the pointer is over it; then it becomes interactive
/// (hover effect, drag handle, clickable lines).
final class OverlayPanel: NSPanel {
    private static let originKey = "overlayTopLeft"
    static var pollingEnabled = true     // Capture turns this off so its script controls hover
    private static let forceHover = ProcessInfo.processInfo.environment["LYRICS_FORCE_HOVER"] != nil
    private let margin: CGFloat = 24
    private let controller: Controller
    private var pollTimer: Timer?
    private var lastInside = Date.distantPast

    init(controller: Controller) {
        self.controller = controller
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false

        let host = FirstMouseHostingView(rootView: LyricsView(clock: controller.clock, controller: controller))
        host.sizingOptions = [.intrinsicContentSize]
        contentView = host

        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: self, queue: .main) { [weak self] _ in
            self?.saveTopLeft()
        }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in self?.pollMouse() }
    }

    // MARK: Hover

    private func pollMouse() {
        guard Self.pollingEnabled else { return }
        if Self.forceHover { controller.hovering = true; return }
        guard isVisible else {
            if controller.hovering { controller.hovering = false }
            return
        }
        let inside = frame.insetBy(dx: -3, dy: -3).contains(NSEvent.mouseLocation)
        if inside { lastInside = Date() }
        let hover = inside || Date().timeIntervalSince(lastInside) < 0.3
        if ignoresMouseEvents == hover { ignoresMouseEvents = !hover }
        if controller.hovering != hover { controller.hovering = hover }
    }

    // MARK: Position

    private var fitted: CGSize {
        let s = contentView?.fittingSize ?? .zero
        return s.width > 0 ? s : CGSize(width: 380, height: 120)
    }

    /// Re-fits to the content (lyrics vs. status text) keeping the top-left corner fixed.
    func refit() {
        let size = fitted
        let top = frame.maxY
        setFrame(NSRect(x: frame.minX, y: top - size.height, width: size.width, height: size.height), display: true)
    }

    func place(in corner: Corner) {
        guard let screen = NSScreen.main else { return }
        let size = fitted
        let area = screen.visibleFrame
        let x = (corner == .topRight || corner == .bottomRight) ? area.maxX - size.width - margin : area.minX + margin
        let top = (corner == .topRight || corner == .topLeft) ? area.maxY - margin : area.minY + margin + size.height
        setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height), display: true)
    }

    /// Uses the last position the user dragged to, if it's still on a screen; otherwise the corner.
    func restoreOrPlace(default corner: Corner) {
        if let p = Self.savedTopLeft(), Self.isOnScreen(p) {
            let size = fitted
            setFrame(NSRect(x: p.x, y: p.y - size.height, width: size.width, height: size.height), display: true)
        } else {
            place(in: corner)
        }
    }

    private static func savedTopLeft() -> NSPoint? {
        guard let a = UserDefaults.standard.array(forKey: originKey) as? [Double], a.count == 2 else { return nil }
        return NSPoint(x: a[0], y: a[1])
    }

    private static func isOnScreen(_ p: NSPoint) -> Bool {
        NSScreen.screens.contains { $0.visibleFrame.insetBy(dx: 10, dy: 10).contains(p) }
    }

    private func saveTopLeft() {
        UserDefaults.standard.set([frame.minX, frame.maxY], forKey: Self.originKey)
    }
}
