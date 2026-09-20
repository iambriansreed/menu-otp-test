import AppKit
import OTPCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Posted by a second launch so the running instance (same data directory,
    /// passed as the object) opens Settings instead of the launch doing nothing.
    static let showSettingsNotification = Notification.Name("com.iambrian.menu-otp.show-settings")

    let environment = AppEnvironment.current()
    private var instanceLock: InstanceLock?
    private(set) var model: AccountsModel!
    private(set) var statusItem: NSStatusItem!
    private(set) var menuController: MenuPanelController!
    private(set) var settingsController: SettingsWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only; Settings flips this to .regular while it's open
        NSApp.setActivationPolicy(.accessory)

        let dataDirectory = environment.dataDirectory
        try? FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        guard let lock = InstanceLock(path: dataDirectory.appendingPathComponent("instance.lock")) else {
            // Another instance owns this data directory and keeps running. Quitting
            // before anything is read means this one can never write behind its back.
            if environment.selfTest || environment.snapshotDirectory != nil {
                // Exiting 0 here would let a test run "pass" without running
                FileHandle.standardError.write(Data(
                    "\(AppEnvironment.appName) is already running with \(dataDirectory.path); quit it first.\n".utf8
                ))
                exit(2)
            }
            // Ask the running instance to open Settings, so launching again always
            // leads somewhere (the status item can be hidden behind the notch)
            DistributedNotificationCenter.default().postNotificationName(
                Self.showSettingsNotification, object: dataDirectory.path, userInfo: nil, deliverImmediately: true
            )
            NSApp.terminate(nil)
            return
        }
        instanceLock = lock

        let keyProvider: KeyProvider = environment.isDemo
            ? InMemoryKeyProvider()
            : KeychainKeyProvider(service: AppEnvironment.bundleID)
        let favicons = FaviconService()
        model = AccountsModel(
            store: AccountStore(fileURL: dataDirectory.appendingPathComponent("accounts.enc"), keyProvider: keyProvider),
            lookupFavicon: { await favicons.favicon(for: $0) },
            copyToClipboard: { Clipboard.copy($0) }
        )

        var setAside: URL?
        do {
            if let demoFile = environment.demoFile {
                model.loadDemo(fromText: try String(contentsOf: demoFile, encoding: .utf8))
            } else {
                setAside = try model.load()
            }
        } catch {
            // Never run without the real accounts loaded: the first save would
            // replace them with whatever is in memory. (Activate first: an
            // accessory app's alert can otherwise open behind other windows.)
            NSApp.activate()
            let alert = NSAlert()
            alert.messageText = "\(AppEnvironment.appName) couldn't open its accounts"
            alert.informativeText = "\(error.localizedDescription)\n\nNothing was changed. "
                + "If macOS asked for Keychain access, open the app again and choose Always Allow."
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        MainMenu.install(appName: AppEnvironment.appName)
        statusItem = makeStatusItem()
        settingsController = SettingsWindowController(
            model: model,
            loginItem: environment.isDemo ? DemoLoginItem() : MainAppLoginItem()
        )
        menuController = MenuPanelController(
            model: model,
            statusItem: statusItem,
            appName: AppEnvironment.appName,
            openSettings: { [weak self] in self?.settingsController.show() }
        )
        model.onChange = { [weak self] in self?.menuController.refreshIfVisible() }
        DistributedNotificationCenter.default().addObserver(
            forName: Self.showSettingsNotification, object: dataDirectory.path, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.settingsController.show() }
        }
        if let setAside { showSetAsideAlert(setAside) }

        if environment.selfTest {
            SelfTest(app: self).start()
            return
        }
        if let directory = environment.snapshotDirectory {
            Snapshots(app: self, directory: directory).start()
            return
        }

        Task {
            let result = await model.backfillIcons()
            NSLog("Icon backfill: found %d of %d", result.found, result.wanted)
        }
    }

    /// Opening the app again (Finder, Spotlight, the Dock) while it runs opens
    /// Settings: the way back in when the status item is hidden behind the notch or
    /// by a menu bar manager.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsController?.show()
        return false
    }

    /// The store existed but couldn't be decrypted (its Keychain key was deleted or
    /// replaced), so it was moved aside and the app started empty. Say so rather
    /// than let the user think their accounts vanished.
    private func showSetAsideAlert(_ file: URL) {
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "\(AppEnvironment.appName) couldn't read its saved accounts"
        alert.informativeText = "The file was moved to \(file.path) and the app started with no "
            + "accounts. This happens when the Keychain item holding its encryption key was "
            + "deleted or replaced. Your secrets are still in that file, but they can only be "
            + "read with the original key."
        alert.runModal()
    }

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = item.button else { return item }
        if let image = NSImage(named: "StatusIcon") {
            image.size = NSSize(width: 16, height: 16)
            // A template image is drawn from its alpha alone, so macOS tints it to match
            // the menu bar: dark on a light bar, light on a dark one, inverted while the
            // item is highlighted. The artwork's own white would be invisible on a light bar.
            image.isTemplate = true
            button.image = image
        } else {
            // Only when run outside the .app bundle (no Resources)
            button.image = NSImage(systemSymbolName: "key.fill", accessibilityDescription: AppEnvironment.appName)
        }
        button.toolTip = "\(AppEnvironment.appName) - Click to view accounts"
        button.target = self
        button.action = #selector(statusItemClicked)
        // Right-click opens the same menu, as in the Electron app
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        return item
    }

    @objc private func statusItemClicked() {
        menuController.toggle()
    }
}
