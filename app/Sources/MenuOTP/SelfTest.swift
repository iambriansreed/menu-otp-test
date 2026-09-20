import AppKit
import OTPCore

/// `app/scripts/demo.sh --self-test`: drives the real popover and Settings window
/// through the same entry points a click or key press uses, prints one PASS/FAIL
/// line per check, and exits 0 only if everything passed. Demo mode only.
@MainActor
final class SelfTest {
    private let app: AppDelegate
    private var failures = 0

    init(app: AppDelegate) {
        self.app = app
    }

    func start() {
        Task { @MainActor in
            let savedClipboard = Clipboard.snapshot()
            await run()
            Clipboard.restore(savedClipboard)
            print(failures == 0 ? "SELF-TEST PASSED" : "SELF-TEST FAILED: \(failures) check(s)")
            fflush(stdout)
            exit(failures == 0 ? 0 : 1)
        }
    }

    private func check(_ name: String, _ condition: Bool) {
        print("\(condition ? "PASS" : "FAIL")  \(name)")
        if !condition { failures += 1 }
    }

    private func run() async {
        let model = app.model!
        let menu = app.menuController!
        let settings = app.settingsController!

        // The status item is placed in the menu bar asynchronously after launch
        for _ in 0..<50 where MenuPanelController.placedFrame(of: app.statusItem) == nil {
            try? await Task.sleep(for: .milliseconds(100))
        }
        check("status item is in the menu bar", MenuPanelController.placedFrame(of: app.statusItem) != nil)
        check("status item has an icon", app.statusItem.button?.image != nil)
        check("demo accounts loaded", !model.accounts.isEmpty)

        // Open
        menu.toggle()
        await settle()
        check("click opens the menu", menu.isVisible)
        check("menu takes key focus", menu.panel.isKeyWindow)
        check("status item is highlighted while the menu is open", app.statusItem.button?.isHighlighted == true)
        let frame = menu.panel.frame
        check("menu width is within 220...460", (220...460).contains(frame.width))
        if let placed = MenuPanelController.placedFrame(of: app.statusItem) {
            check("menu hangs 2pt under the status item", abs(frame.maxY - (placed.frame.minY - 2)) < 1.5)
        }
        let visible = model.accounts.filter { !$0.hidden }
        check("one row per visible account + separator, Settings, Quit", menu.rowsForTesting.count == visible.count + 3)

        // Keyboard: ↓ then Return copies the first account
        menu.panel.sendEvent(key(125))
        check("down arrow highlights the first row", menu.highlightedIndexForTesting == 0)
        let before = Date()
        menu.panel.sendEvent(key(36))
        await settle()
        let first = visible[0]
        let possible = [before, before.addingTimeInterval(TOTP.period)].compactMap { try? TOTP.code(secret: first.secret, at: $0) }
        check("return copies the highlighted account's code", possible.contains(NSPasteboard.general.string(forType: .string) ?? "-"))
        check("copied code is marked concealed", NSPasteboard.general.types?.contains(Clipboard.concealedType) == true)
        check("menu shows the Copied confirmation", { if case .copied = menu.content { return true } else { return false } }())
        check("menu stays open after copying", menu.isVisible)
        check("last clicked is recorded", model.lastClicked?.identity == first.identity)

        // The pointer path: MenuHostingView's handlers hit-test the row frames SwiftUI
        // reports. The keyboard checks above never exercise it.
        func pointAtFirstRow() -> CGFloat? {
            // Probe down from the top edge until a row answers
            stride(from: 10.0, through: 120.0, by: 5.0).first { y in
                menu.pointerForTesting(.mouseMoved, yFromTop: y)
                return menu.highlightedIndexForTesting != nil
            }
        }
        menu.panel.sendEvent(key(53))
        try? await Task.sleep(for: .milliseconds(300))
        menu.show()
        await settle()
        check("pointer hover highlights a row", pointAtFirstRow() != nil)
        // Reopening shows identical rows, so SwiftUI reports no new row frames; the
        // frames from the last open must still be there
        menu.hide()
        try? await Task.sleep(for: .milliseconds(300))
        menu.show()
        await settle()
        let rowY = pointAtFirstRow()
        check("pointer hover still works after closing and reopening", rowY != nil)
        menu.pointerForTesting(.leftMouseUp, yFromTop: rowY ?? 0)
        await settle()
        check("pointer click copies after reopening", { if case .copied = menu.content { return true } else { return false } }())

        // Dismiss and the reopen guard
        menu.panel.sendEvent(key(53))
        await settle()
        check("escape closes the menu", !menu.isVisible)
        check("status item highlight clears on close", app.statusItem.button?.isHighlighted == false)
        menu.toggle()
        await settle()
        check("a click right after closing doesn't reopen it", !menu.isVisible)
        try? await Task.sleep(for: .milliseconds(300))
        menu.toggle()
        await settle()
        check("a later click reopens it", menu.isVisible)
        check("reopened menu starts with the Last clicked header", menu.rowsForTesting.first?.kind == .header)
        menu.toggle()
        await settle()
        check("clicking the status item again closes it", !menu.isVisible)

        // Live refresh while open. The refresh is synchronous (mutate -> onChange ->
        // refreshIfVisible), so check straight away: waiting would leave room for a
        // stray click elsewhere to dismiss the menu, correctly, and skip the refresh.
        menu.show()
        await settle()
        let rowCount = menu.rowsForTesting.count
        let quitRow = menu.rowsForTesting.firstIndex { $0.action == .quit }
        menu.highlightForTesting(quitRow)
        let wasOpen = menu.isVisible
        report { try model.toggleHidden(first.identity) }
        check("hiding an account refreshes the open menu", wasOpen && menu.rowsForTesting.count == rowCount - 1)
        let highlighted = menu.highlightedIndexForTesting.map { menu.rowsForTesting[$0].action }
        check("the highlighted row survives a refresh", highlighted == .quit)
        report { try model.toggleHidden(first.identity) }

        // Switching Space dismisses (the panel is on every Space)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        await settle()
        check("a Space change closes the menu", !menu.isVisible)
        menu.hide()

        // Settings
        settings.show()
        await settle()
        check("Settings opens", settings.window?.isVisible == true)
        check("Settings is titled", settings.window?.title == "\(AppEnvironment.appName) Settings")
        check("Settings opens without the cursor in a text field", !(settings.window?.firstResponder is NSTextView))
        // A List holds clicks on text fields in its rows for the double-click interval
        check("Settings uses no List outside reorder mode", !containsTable(settings.window?.contentView))
        check("app is in the Dock while Settings is open", NSApp.activationPolicy() == .regular)
        settings.close()
        await settle()
        check("closing Settings leaves the Dock", NSApp.activationPolicy() == .accessory)

        settings.initialState = .init(reordering: true)
        settings.show()
        await settle()
        check("reorder mode uses a native List (for its drag and drop)", containsTable(settings.window?.contentView))
        settings.close()
        await settle()

        settings.initialState = .init(addTab: .importFile, openFilePicker: true)
        settings.show()
        for _ in 0..<30 where settings.window?.attachedSheet == nil {
            try? await Task.sleep(for: .milliseconds(100))
        }
        check("Import's file picker is a sheet on the Settings window", settings.window?.attachedSheet != nil)
        if let window = settings.window, let sheet = window.attachedSheet { window.endSheet(sheet) }
        await settle()
        settings.close()
        await settle()
        settings.initialState = .init()

        // Opening Settings from the menu row
        menu.show()
        await settle()
        if let settingsRow = menu.rowsForTesting.firstIndex(where: { $0.action == .settings }) {
            menu.activate(index: settingsRow)
            await settle()
            check("the Settings row opens Settings and closes the menu", settings.window?.isVisible == true && !menu.isVisible)
            settings.close()
        } else {
            check("menu has a Settings row", false)
        }

        // Launching again while running (Finder, Spotlight) opens Settings
        await settle()
        _ = app.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
        await settle()
        check("reopening the app opens Settings", settings.window?.isVisible == true)
        settings.close()
        await settle()
    }

    private func containsTable(_ view: NSView?) -> Bool {
        guard let view else { return false }
        return view is NSTableView || view.subviews.contains { containsTable($0) }
    }

    private func key(_ keyCode: UInt16) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: app.menuController.panel.windowNumber, context: nil,
            characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: keyCode
        )!
    }

    private func settle() async {
        try? await Task.sleep(for: .milliseconds(200))
    }
}
