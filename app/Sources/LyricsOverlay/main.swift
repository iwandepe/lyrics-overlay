import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let controller = Controller()
    private let server = BridgeServer()
    private let updater = Updater()
    private let onboarding = OnboardingWindow()
    private var panel: OverlayPanel!
    private var statusItem: NSStatusItem!
    private var connectionItem: NSMenuItem!
    private var offsetItem: NSMenuItem!
    private var autoScrollItem: NSMenuItem!
    private var updateItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var corner: Corner = .topRight
    private var overlayEnabled = true     // user toggle from the menu
    private var overlayWanted = false     // controller: music is playing and not an ad
    private var manualUpdateCheck = false // the user asked, so report "up to date" / errors
    private var updateTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = OverlayPanel(controller: controller)
        panel.restoreOrPlace(default: corner)

        // Grow / shrink the panel when switching between lyrics and a status message.
        controller.clock.$lines
            .map(\.isEmpty)
            .removeDuplicates()
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.panel.refit() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self?.panel.refit() }
            }
            .store(in: &cancellables)

        controller.onVisibilityChange = { [weak self] wanted in
            self?.overlayWanted = wanted
            self?.refreshPanel()
        }

        buildMenu()
        controller.$userOffset
            .sink { [weak self] v in self?.offsetItem.title = String(format: "Sync offset: %+.2fs", v) }
            .store(in: &cancellables)
        controller.$autoScroll
            .sink { [weak self] on in self?.autoScrollItem.state = on ? .on : .off }
            .store(in: &cancellables)

        // If a monitor is unplugged, don't leave the overlay stranded off-screen.
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.panel.restoreOrPlace(default: self.corner)
        }

        server.onState = { [weak self] state in self?.controller.handle(state) }
        server.onConnectionCount = { [weak self] n in
            self?.connectionItem.title = n > 0 ? "Extension: connected" : "Extension: not connected"
            self?.controller.extensionConnected = n > 0
        }
        do { try server.start() } catch { print("Could not start bridge server: \(error)") }

        setUpUpdates()

        if CommandLine.arguments.contains("--demo") { controller.showDemo() }

        // First launch of the installed app: walk through setup.
        let forceOnboarding = ProcessInfo.processInfo.environment["LYRICS_ONBOARD"] != nil
        if (Config.isBundled && OnboardingWindow.needed) || forceOnboarding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self else { return }
                self.onboarding.show(controller: self.controller)
            }
        }

        if ProcessInfo.processInfo.environment["LYRICS_INSTALL_EXTENSION_NOW"] != nil {   // tests: run the installer without the UI
            ExtensionInstaller.install { result in
                if case .failure(let f) = result { print("[extension] failed: \(f.message)") }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
            }
        }

        if let path = ProcessInfo.processInfo.environment["LYRICS_ONBOARD_SNAPSHOT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.onboarding.snapshot(to: path)
                NSApp.terminate(nil)
            }
        }

        if let dir = ProcessInfo.processInfo.environment["LYRICS_CAPTURE"] {
            Capture.run(panel: panel, controller: controller, dir: dir)
        }

        // Debug: LYRICS_SNAPSHOT=/path.png LYRICS_SNAPSHOT_AT=14 renders the overlay to a PNG and exits.
        // Add LYRICS_FORCE_HOVER=1 to render the hovered state.
        if let path = ProcessInfo.processInfo.environment["LYRICS_SNAPSHOT"] {
            let at = Double(ProcessInfo.processInfo.environment["LYRICS_SNAPSHOT_AT"] ?? "") ?? 5
            DispatchQueue.main.asyncAfter(deadline: .now() + at) { [weak self] in
                if let v = self?.panel.contentView,
                   let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                    v.cacheDisplay(in: v.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                }
                NSApp.terminate(nil)
            }
        }
    }

    private func refreshPanel() {
        if overlayEnabled && overlayWanted {
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    // MARK: Updates

    private func setUpUpdates() {
        updater.relaunch = { NSApp.terminate(nil) }
        updater.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] s in self?.updateStateChanged(s) }
            .store(in: &cancellables)

        // Quiet background checks for the installed app: shortly after launch, then every 6 hours.
        // (LYRICS_UPDATE_AUTOINSTALL is for rehearsing the whole update flow locally.)
        guard Config.updatesConfigured, Config.isBundled || ProcessInfo.processInfo.environment["LYRICS_UPDATE_AUTOINSTALL"] != nil else { return }
        let first = ProcessInfo.processInfo.environment["LYRICS_UPDATE_AUTOINSTALL"] != nil ? 1.0 : 10.0
        DispatchQueue.main.asyncAfter(deadline: .now() + first) { [weak self] in self?.updater.check() }
        updateTimer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in self?.updater.check() }
    }

    private func updateStateChanged(_ s: Updater.State) {
        switch s {
        case .idle:
            updateItem.title = "Check for Updates…"
        case .checking:
            updateItem.title = "Checking for updates…"
        case .upToDate:
            updateItem.title = "Check for Updates…"
            statusItem.button?.title = "♪"
            if manualUpdateCheck { alert("You're up to date", "Lyrics Overlay \(Config.versionString) is the latest version.") }
            manualUpdateCheck = false
        case .available(let r):
            updateItem.title = "⬆︎ Update to v\(r.version)…"
            statusItem.button?.title = "♪•"
            if ProcessInfo.processInfo.environment["LYRICS_UPDATE_AUTOINSTALL"] != nil {
                updater.install(r)
            } else if manualUpdateCheck {
                promptToUpdate(r)
            }
            manualUpdateCheck = false
        case .installing:
            updateItem.title = "Installing update…"
        case .failed(let message):
            updateItem.title = "Check for Updates…"
            if manualUpdateCheck { alert("Couldn't update", message) }
            manualUpdateCheck = false
            print("[update] \(message)")
        }
    }

    private func promptToUpdate(_ r: ReleaseInfo) {
        let a = NSAlert()
        a.messageText = "Lyrics Overlay \(r.version) is available"
        let notes = r.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        a.informativeText = "You have \(Config.versionString).\(notes.isEmpty ? "" : "\n\n" + String(notes.prefix(600)))"
        a.addButton(withTitle: "Update & Restart")
        a.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn { updater.install(r) }
    }

    private func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }

    @objc private func updateClicked() {
        if case .available(let r) = updater.state {
            promptToUpdate(r)
        } else {
            manualUpdateCheck = true
            updater.check()
        }
    }

    // MARK: Menu

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "♪"

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(NSMenuItem(title: "Lyrics Overlay \(Config.versionString)", action: nil, keyEquivalent: ""))
        connectionItem = NSMenuItem(title: "Extension: not connected", action: nil, keyEquivalent: "")
        menu.addItem(connectionItem)
        menu.addItem(.separator())

        // Moving: hover the overlay and drag its top bar, or snap to a corner here.
        for c in Corner.allCases {
            let item = NSMenuItem(title: "Move to \(c.rawValue.lowercased())", action: #selector(pickCorner(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = c
            menu.addItem(item)
        }
        menu.addItem(.separator())

        autoScrollItem = NSMenuItem(title: "Auto-scroll lyrics", action: #selector(toggleAutoScroll), keyEquivalent: "")
        autoScrollItem.target = self
        autoScrollItem.state = controller.autoScroll ? .on : .off
        menu.addItem(autoScrollItem)

        offsetItem = NSMenuItem(title: "Sync offset: +0.00s", action: nil, keyEquivalent: "")
        menu.addItem(offsetItem)
        for (title, sel) in [("Show lyrics earlier (+0.25s)", #selector(earlier)),
                             ("Show lyrics later (−0.25s)", #selector(later))] {
            let item = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        let reset = NSMenuItem(title: "Reset sync for this song", action: #selector(resetSync), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)
        menu.addItem(.separator())

        let toggle = NSMenuItem(title: "Show overlay", action: #selector(toggleOverlay(_:)), keyEquivalent: "")
        toggle.target = self
        toggle.state = .on
        menu.addItem(toggle)

        loginItem = NSMenuItem(title: "Launch at login", action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.isEnabled = LoginItem.isAvailable
        menu.addItem(loginItem)
        menu.addItem(.separator())

        updateItem = NSMenuItem(title: "Check for Updates…", action: #selector(updateClicked), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)
        let setup = NSMenuItem(title: "Setup guide…", action: #selector(showSetup), keyEquivalent: "")
        setup.target = self
        menu.addItem(setup)
        let demo = NSMenuItem(title: "Demo lyrics", action: #selector(runDemo), keyEquivalent: "")
        demo.target = self
        menu.addItem(demo)
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        loginItem.state = LoginItem.isEnabled ? .on : .off
    }

    @objc private func pickCorner(_ sender: NSMenuItem) {
        guard let c = sender.representedObject as? Corner else { return }
        corner = c
        panel.place(in: c)
    }

    @objc private func toggleAutoScroll() { controller.autoScroll.toggle() }
    @objc private func toggleOverlay(_ sender: NSMenuItem) {
        overlayEnabled.toggle()
        sender.state = overlayEnabled ? .on : .off
        refreshPanel()
    }
    @objc private func toggleLogin() {
        do { try LoginItem.set(!LoginItem.isEnabled) } catch { alert("Couldn't change login item", error.localizedDescription) }
    }
    @objc private func showSetup() { onboarding.show(controller: controller) }
    @objc private func earlier() { controller.nudge(0.25) }
    @objc private func later() { controller.nudge(-0.25) }
    @objc private func resetSync() { controller.resetOffset() }
    @objc private func runDemo() { controller.showDemo() }
}

setvbuf(stdout, nil, _IOLBF, 0)       // line-buffered, so logs survive when output is redirected to a file
let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // no Dock icon; lives in the menu bar
let delegate = AppDelegate()
app.delegate = delegate
app.run()
