import SwiftUI
import AppKit

struct LyricsView: View {
    @ObservedObject var clock: PlaybackClock
    @ObservedObject var controller: Controller
    @State private var hoveredRow: Int?

    private let listHeight: CGFloat = 172
    private let statusHeight: CGFloat = 84
    private let headerHeight: CGFloat = 30

    var body: some View {
        // The header floats over the top edge (it doesn't take its own row), so the lyrics
        // area fills the whole widget and the current line sits at its true vertical center.
        ZStack(alignment: .top) {
            if clock.lines.isEmpty { statusView } else { list }
            header
        }
        .frame(width: 380)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))   // header fade must not square the corners
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.black.opacity(controller.hovering ? 0.78 : 0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(controller.hovering ? 0.22 : 0), lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.15), value: controller.hovering)
    }

    // MARK: Header (drag handle + controls, visible on hover)

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.5))
            if let t = controller.toast {
                Text(t)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.green.opacity(0.9))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)

            pill(controller.autoScroll ? "Auto" : "Manual",
                 icon: controller.autoScroll ? "arrow.down.to.line.compact" : "hand.point.up.left") {
                controller.autoScroll.toggle()
            }
            .help("Auto: lyrics follow the song. Manual: scroll them yourself.")

            if !clock.lines.isEmpty {
                HStack(spacing: 4) {
                    iconButton("minus", help: "Show lyrics later (−0.25s)") { controller.nudge(-0.25) }
                    Text(String(format: "%+.2fs", controller.userOffset))
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.8))
                    iconButton("plus", help: "Show lyrics earlier (+0.25s)") { controller.nudge(0.25) }
                    if controller.userOffset != 0 {
                        iconButton("arrow.counterclockwise", help: "Reset sync for this song") { controller.resetOffset() }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: headerHeight)
        .background(
            ZStack {
                Color(red: 0.075, green: 0.07, blue: 0.08)    // solid: lyrics never show through the bar
                DragHandle()
            }
        )
        .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.09)).frame(height: 1) }
        .opacity(controller.hovering ? 1 : 0)                 // last, so the whole bar (not just its buttons) fades away
    }

    private func pill(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                Text(label)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(.white.opacity(0.16)))
        }
        .buttonStyle(.plain)
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(.white.opacity(0.16)))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: Lyrics

    private var statusView: some View {
        Text(clock.status ?? "No lyrics")
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.7))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .frame(height: statusHeight)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    Spacer().frame(height: listHeight / 2 - 16)   // lets the first/last line reach the center
                    ForEach(Array(clock.lines.enumerated()), id: \.offset) { i, line in
                        row(i, line)
                    }
                    Spacer().frame(height: listHeight / 2 - 16)
                }
                .padding(.horizontal, 8)
            }
            .scrollDisabled(controller.autoScroll)
            .frame(height: listHeight)
            .mask(listMask)
            .onAppear { scroll(proxy, animated: false) }
            .onChange(of: clock.lines) { _ in scroll(proxy, animated: false) }
            .onChange(of: clock.currentIndex) { _ in if controller.autoScroll { scroll(proxy) } }
            .onChange(of: controller.autoScroll) { on in if on { scroll(proxy) } }
        }
    }

    /// Fades the lyrics out at the top and bottom. While the header is showing, the lyrics are fully
    /// hidden behind its height (plus a small gap) and fade in just below it, so they never run into the bar.
    private var listMask: some View {
        let hovering = controller.hovering
        let gap: CGFloat = 8     // clear space under the bar so no half-hidden glyphs peek out
        let clearUntil = hovering ? (headerHeight + gap) / listHeight : 0
        let solidFrom = hovering ? (headerHeight + gap + 22) / listHeight : 0.14
        return LinearGradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: .clear, location: clearUntil),
            .init(color: .black, location: solidFrom),
            .init(color: .black, location: 0.86),
            .init(color: .clear, location: 1),
        ], startPoint: .top, endPoint: .bottom)
    }

    private func scroll(_ proxy: ScrollViewProxy, animated: Bool = true) {
        let target = clock.currentIndex ?? 0
        if animated {
            withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(target, anchor: .center) }
        } else {
            proxy.scrollTo(target, anchor: .center)
        }
    }

    private func row(_ i: Int, _ line: LyricLine) -> some View {
        let isCurrent = i == clock.currentIndex
        let hovered = hoveredRow == i
        return Text(line.text.isEmpty ? "♪" : line.text)
            .font(.system(size: isCurrent ? 19 : 15, weight: isCurrent ? .bold : .regular, design: .rounded))
            .foregroundStyle(.white.opacity(isCurrent ? 1 : (hovered ? 0.95 : 0.5)))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(hovered ? 0.14 : 0)))
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { hoveredRow = i } else if hoveredRow == i { hoveredRow = nil }
            }
            .onTapGesture { controller.syncLine(i) }
            .help("Click when this line is being sung to fix sync for this song")
            .animation(.easeOut(duration: 0.12), value: hovered)
            .id(i)
    }
}

/// Invisible view that lets the user drag the whole window by this area.
struct DragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
}
