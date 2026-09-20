import AppKit
import OTPCore

/// `app/scripts/demo.sh --snapshot <dir>`: puts the popover and Settings on screen in
/// a few states and saves each window with `screencapture -l`, so the UI can be
/// checked visually without clicking anything. Demo mode only. (Offscreen
/// rendering was tried and doesn't work: cacheDisplay drops SwiftUI-drawn content
/// and ImageRenderer draws placeholders for AppKit-backed controls.)
@MainActor
final class Snapshots {
    private let app: AppDelegate
    private let directory: URL

    init(app: AppDelegate, directory: URL) {
        self.app = app
        self.directory = directory
    }

    func start() {
        Task { @MainActor in
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let savedClipboard = Clipboard.snapshot()
            await run()
            Clipboard.restore(savedClipboard)
            exit(0)
        }
    }

    private func run() async {
        let menu = app.menuController!
        let settings = app.settingsController!
        for _ in 0..<50 where MenuPanelController.placedFrame(of: app.statusItem) == nil {
            try? await Task.sleep(for: .milliseconds(100))
        }

        // Demo URLs carry no icons: give a few accounts one of each kind, and hide
        // one, so every row style is on screen. With --real-icons (for the website's
        // screenshots) the icons are the services' real favicons instead, fetched
        // from the icon services. (Demo mode: this only ever writes to the throwaway
        // demo directory.)
        if CommandLine.arguments.contains("--real-icons") {
            await app.model.backfillIcons()
        }
        report {
            try app.model.mutate { list in
                guard list.count >= 3 else { return }
                if !CommandLine.arguments.contains("--real-icons") {
                    list[0].icon = "💳"
                    list[1].icon = Self.sampleFavicon()
                }
                list[2].hidden = true
            }
        }

        menu.show()
        await settle()
        capture(menu.panel, "menu")

        menu.highlightForTesting(1)
        await settle()
        capture(menu.panel, "menu-highlighted")

        // The last account row. In a menu taller than the screen it must have
        // scrolled into view; with the stock demo data nothing scrolls.
        let accountRows = menu.rowsForTesting.indices.filter { index in
            if case .copy = menu.rowsForTesting[index].action { return true }
            return false
        }
        if let last = accountRows.last {
            menu.highlightForTesting(last)
            await settle()
            capture(menu.panel, "menu-last-row")
        }

        menu.activate(index: 0)
        await settle()
        capture(menu.panel, "menu-copied")
        menu.hide()

        menu.show()
        await settle()
        capture(menu.panel, "menu-last-clicked")
        menu.hide()

        settings.show()
        await settle(0.6)
        capture(settings.window, "settings")
        settings.close()

        settings.initialState = .init(editing: app.model.accounts.first?.identity, addTab: .manual)
        settings.show()
        await settle(0.6)
        capture(settings.window, "settings-editing")
        settings.close()

        settings.initialState = .init(addTab: .importFile)
        settings.show()
        await settle(0.6)
        capture(settings.window, "settings-import")
        settings.close()

        settings.initialState = .init(reordering: true)
        settings.show()
        await settle(0.6)
        capture(settings.window, "settings-reorder")
        settings.close()
    }

    /// A 32x32 PNG data URL, standing in for a fetched favicon.
    static func sampleFavicon() -> String {
        let image = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
            NSColor.systemOrange.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2)).fill()
            return true
        }
        guard let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return "" }
        return "data:image/png;base64," + png.base64EncodedString()
    }

    private func capture(_ window: NSWindow?, _ name: String) {
        guard let window else {
            print("snapshot \(name): FAILED (no window)")
            return
        }
        let url = directory.appendingPathComponent("\(name).png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-o", "-l", String(window.windowNumber), url.path]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            print("snapshot \(name): FAILED (\(error.localizedDescription))")
            return
        }
        print("snapshot \(name): \(process.terminationStatus == 0 ? url.path : "FAILED (exit \(process.terminationStatus))")")
    }

    private func settle(_ seconds: Double = 0.3) async {
        try? await Task.sleep(for: .seconds(seconds))
    }
}
