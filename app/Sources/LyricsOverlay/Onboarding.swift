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
    private static let browserIDs = ["app.zen-browser.zen", "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition"]

    /// Downloads the signed extension and opens the saved file in Zen (else Firefox). The browser shows its own
    /// "Add extension?" prompt. Opening a local file works regardless of how GitHub serves the download.
    static func install(completion: @escaping (Result<Void, ExtensionFile.Failure>) -> Void) {
        guard let url = Config.extensionInstallURL else {
            completion(.failure(.init(message: "Developer build: in Zen or Firefox open about:debugging#/runtime/this-firefox, choose “Load Temporary Add-on…” and pick extension/manifest.json.")))
            return
        }
        Task {
            do {
                let file = try await ExtensionFile.download(from: url)
                DispatchQueue.main.async {
                    if ProcessInfo.processInfo.environment["LYRICS_EXTENSION_DRYRUN"] != nil {
                        print("[extension] saved \(file.path)")        // tests: don't launch a browser
                        completion(.success(()))
                    } else {
                        open(file, completion: completion)
                    }
                }
            } catch {
                DispatchQueue.main.async { completion(.failure(.init(message: error.localizedDescription))) }
            }
        }
    }

    private static func open(_ file: URL, completion: @escaping (Result<Void, ExtensionFile.Failure>) -> Void) {
        let ws = NSWorkspace.shared
        let fallback = "The file is saved; in Zen or Firefox use Add-ons → ⚙ → Install Add-on From File."
        guard let app = browserIDs.lazy.compactMap({ ws.urlForApplication(withBundleIdentifier: $0) }).first else {
            ws.activateFileViewerSelecting([file])
            completion(.failure(.init(message: "Couldn't find Zen or Firefox. " + fallback)))
            return
        }
        ws.open([file], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            DispatchQueue.main.async {
                if let error {
                    ws.activateFileViewerSelecting([file])
                    completion(.failure(.init(message: "Couldn't open it in the browser (\(error.localizedDescription)). " + fallback)))
                } else {
                    completion(.success(()))
                }
            }
        }
    }
}

enum InstallState: Equatable {
    case idle, working, opened
    case failed(String)

    /// Debug: LYRICS_ONBOARD_INSTALL_STATE=working|opened|failed renders that state in snapshots.
    static var initial: InstallState {
        switch ProcessInfo.processInfo.environment["LYRICS_ONBOARD_INSTALL_STATE"] {
        case "working": return .working
        case "opened": return .opened
        case "failed": return .failed("The extension file hasn't been published yet.")
        default: return .idle
        }
    }
}

struct OnboardingView: View {
    @ObservedObject var controller: Controller
    var done: () -> Void
    @State private var loginOn = LoginItem.isEnabled
    @State private var install = InstallState.initial

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
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Button(install == .working ? "Downloading…" : "Install extension", action: startInstall)
                            .disabled(install == .working)
                        if install == .opened {
                            Text("Now click Add in your browser.").foregroundStyle(.secondary)
                        }
                    }
                    if case .failed(let message) = install {
                        Text(message).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                        if let page = Config.releasesPageURL {
                            Button("Open download page") { NSWorkspace.shared.open(page) }
                        }
                    }
                }
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

    private func startInstall() {
        install = .working
        ExtensionInstaller.install { result in
            switch result {
            case .success: install = .opened
            case .failure(let f): install = .failed(f.message)
            }
        }
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
