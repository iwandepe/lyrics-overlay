import SwiftUI
import AppKit
import ServiceManagement

enum LoginItem {
    static var isAvailable: Bool { Config.isBundled }
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool) throws {
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        if on && SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    }
}

enum ExtensionInstaller {
    /// Opens the signed extension in Zen if installed, otherwise Firefox, otherwise the default browser.
    static func open() {
        guard let url = Config.extensionInstallURL else {
            let a = NSAlert()
            a.messageText = "Extension download isn't set up yet"
            a.informativeText = "Developer build: in Zen or Firefox open about:debugging#/runtime/this-firefox, choose “Load Temporary Add-on…” and pick extension/manifest.json."
            a.runModal()
            return
        }
        let ws = NSWorkspace.shared
        for id in ["app.zen-browser.zen", "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition"] {
            if let app = ws.urlForApplication(withBundleIdentifier: id) {
                ws.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
                return
            }
        }
        ws.open(url)
    }
}

struct OnboardingView: View {
    @ObservedObject var controller: Controller
    var done: () -> Void
    @State private var loginOn = LoginItem.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to Lyrics Overlay").font(.title2.bold())
                    Text("Synced lyrics that float over your screen while music plays in your browser.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }

            step("The app is running", done: true, detail: "Look for ♪ in your menu bar.")
            step("Add the browser extension", done: controller.extensionConnected,
                 detail: controller.extensionConnected ? "Connected." : "Works in Zen and Firefox. Click Add when the browser asks.") {
                Button("Install extension") { ExtensionInstaller.open() }
            }
            step("Play a song on YouTube", done: controller.songSeen,
                 detail: controller.songSeen ? "Lyrics are on their way. Hover them to move or fix timing." : "Any tab will do, even in the background.")

            if LoginItem.isAvailable {
                Toggle("Open Lyrics Overlay when I log in", isOn: $loginOn)
                    .onChange(of: loginOn) { on in
                        do { try LoginItem.set(on) } catch { loginOn = LoginItem.isEnabled }
                    }
            }

            HStack {
                Spacer()
                Button("Done", action: done).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 500)
    }

    private func step(_ title: String, done: Bool, detail: String) -> some View {
        step(title, done: done, detail: detail) { EmptyView() }
    }

    private func step<A: View>(_ title: String, done: Bool, detail: String, @ViewBuilder action: () -> A) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(done ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                action()
            }
            Spacer(minLength: 0)
        }
    }
}

final class OnboardingWindow: NSObject, NSWindowDelegate {
    static let doneKey = "didOnboard"
    private var window: NSWindow?

    static var needed: Bool { !UserDefaults.standard.bool(forKey: doneKey) }

    func show(controller: Controller) {
        if window == nil {
            let host = NSHostingController(rootView: OnboardingView(controller: controller) { [weak self] in self?.window?.close() })
            let w = NSWindow(contentViewController: host)
            w.title = "Lyrics Overlay Setup"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Debug: renders the guide to a PNG (LYRICS_ONBOARD_SNAPSHOT).
    func snapshot(to path: String) {
        guard let v = window?.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
        v.cacheDisplay(in: v.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    func windowWillClose(_ notification: Notification) {
        UserDefaults.standard.set(true, forKey: Self.doneKey)
        window = nil
    }
}
