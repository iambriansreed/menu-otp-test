import AppKit
import OTPCore
import SwiftUI

/// Opens, sizes, positions, drives and dismisses the popover.
@MainActor
final class MenuPanelController {
    // The popover sizes to its content between these, the way a native menu does
    nonisolated static let minWidth: CGFloat = 220
    nonisolated static let maxWidth: CGFloat = 460
    nonisolated static let edgeGap: CGFloat = 6
    /// A just-shown panel can lose key status for a moment while focus settles,
    /// especially over a full-screen Space. Only dismiss if it's still not key
    /// after this long, or the menu flashes open and shut.
    nonisolated static let blurGrace: TimeInterval = 0.15

    let panel = MenuPanel()
    private let highlight = MenuHighlight()
    private let hostingView: MenuHostingView
    /// Never in a window; only asked for its fittingSize (SwiftUI's ideal size).
    /// Has its own highlight so its row-frame reports can't overwrite the real ones.
    private let measuringHighlight = MenuHighlight()
    private lazy var measuringView = NSHostingView(rootView: MenuView(content: .rows([]), highlight: measuringHighlight))
    private let model: AccountsModel
    private let statusItem: NSStatusItem
    private let appName: String
    private let openSettings: () -> Void

    private(set) var content: MenuContent = .rows([])
    private var rows: [MenuRow] = []
    private var selection = MenuSelection(rows: [])
    private var gate = MenuToggleGate()
    private var outsideClickMonitor: Any?

    init(model: AccountsModel, statusItem: NSStatusItem, appName: String, openSettings: @escaping () -> Void) {
        self.model = model
        self.statusItem = statusItem
        self.appName = appName
        self.openSettings = openSettings
        hostingView = MenuHostingView(rootView: MenuView(content: .rows([]), highlight: highlight))
        // The controller sizes the panel itself. Left at the default, NSHostingView
        // adds min/max-size constraints that collapse the panel to 0x0.
        hostingView.sizingOptions = []
        hostingView.frame = panel.effectView.bounds
        hostingView.autoresizingMask = [.width, .height]
        panel.effectView.addSubview(hostingView)

        hostingView.rowAt = { [weak self] point in
            self?.highlight.rowFrames.first { $0.value.contains(point) }?.key
        }
        hostingView.onHover = { [weak self] index in self?.hover(index) }
        hostingView.onClick = { [weak self] index in self?.activate(index: index) }
        panel.keyHandler = { [weak self] event in self?.handleKey(event) ?? false }

        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.blurGrace) {
                guard let self, self.panel.isVisible, !self.panel.isKeyWindow else { return }
                self.hide()
            }
        }

        // The panel joins every Space, so a Space swipe or Cmd-Tab would otherwise
        // leave it hanging over whatever comes next; a real menu closes then too
        // (queue: .main delivers on the main thread, hence assumeIsolated.)
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
        workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) {
            [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let pid = app?.processIdentifier
            MainActor.assumeIsolated {
                if pid != ProcessInfo.processInfo.processIdentifier { self?.hide() }
            }
        }
    }

    /// The status item's frame and screen, once it has been placed in a menu bar.
    /// Judged against the screen's full frame, not `visibleFrame`: with an
    /// auto-hiding menu bar (always the case in a full-screen Space) the visible
    /// frame covers the menu bar's strip too, and a placed item would look unplaced.
    /// Just after launch the item's window sits at a placeholder origin near the
    /// bottom-left of the screen, which the top-half test rejects.
    static func placedFrame(of item: NSStatusItem) -> (frame: NSRect, screen: NSScreen)? {
        guard let button = item.button, let window = button.window, let screen = window.screen else { return nil }
        let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
        guard frame.midY > screen.frame.midY else { return nil }
        return (frame, screen)
    }

    var isVisible: Bool { panel.isVisible }

    /// Status item click. Checks the panel's real visibility first, so a click on an
    /// open menu closes it instead of racing the deferred resign-key hide.
    func toggle() {
        switch gate.onClick(isVisible: panel.isVisible, now: Date()) {
        case .show: show()
        case .hide: hide()
        case .ignore: break
        }
    }

    func show() {
        // Content and frame are settled before the panel is on screen, so it never
        // flashes at the wrong size. No NSApp.activate() — see MenuPanel.
        showRows()
        panel.orderFrontRegardless()
        panel.makeKey()
        // Status items stay highlighted while their menu is open
        statusItem.button?.highlight(true)
        // Joining the active Space can resize a panel out from under the frame just
        // set, so assert it once more now that it's actually on screen.
        layout()
        installOutsideClickMonitor()
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        statusItem.button?.highlight(false)
        gate.didHide(at: Date())
        removeOutsideClickMonitor()
    }

    /// The accounts changed. Redraw an open menu, but leave a "Copied" confirmation
    /// on screen rather than yanking it away mid-read.
    func refreshIfVisible() {
        guard panel.isVisible, case .rows = content else { return }
        // Keep the highlighted row across the rebuild, found by what it does (an
        // account's identity), so a background change mid-launch doesn't reset the
        // pointer or keyboard selection
        let kept = selection.active.flatMap { rows.indices.contains($0) ? rows[$0].action : nil }
        showRows()
        if let kept, let index = rows.firstIndex(where: { $0.action == kept }) { hover(index) }
    }

    func activate(index: Int) {
        guard case .rows = content, rows.indices.contains(index), let action = rows[index].action else { return }
        switch action {
        case .quit:
            hide()
            NSApp.terminate(nil)
        case .settings:
            hide()
            openSettings()
        case .copy(let identity):
            // A malformed secret (hand-edited store, old demo file) can't produce a
            // code; nothing is copied and nothing changes
            guard let copied = model.copyCode(for: identity) else {
                NSSound.beep()
                return
            }
            // The confirmation stays until the panel loses focus; no timer
            selection = MenuSelection(rows: [])
            highlight.active = nil
            setContent(.copied(issuer: copied.issuer, code: copied.code))
        }
    }

    // MARK: Test hooks (SelfTest / Snapshots, demo mode only)

    var rowsForTesting: [MenuRow] { rows }
    var highlightedIndexForTesting: Int? { highlight.active }
    func highlightForTesting(_ index: Int?) { hover(index) }

    /// Sends a synthetic mouse event through MenuHostingView's own handlers, the path
    /// real pointer input takes (hit-testing the row frames SwiftUI reports), at a
    /// point `yFromTop` points below the panel's top edge, horizontally centred.
    func pointerForTesting(_ type: NSEvent.EventType, yFromTop: CGFloat) {
        let location = NSPoint(x: panel.frame.width / 2, y: panel.frame.height - yFromTop)
        guard let event = NSEvent.mouseEvent(
            with: type, location: location, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 0
        ) else { return }
        switch type {
        case .mouseMoved: hostingView.mouseMoved(with: event)
        case .leftMouseUp: hostingView.mouseUp(with: event)
        default: break
        }
    }

    // MARK: Private

    private func showRows() {
        rows = MenuRows.build(accounts: model.accounts, lastClicked: model.lastClicked, appName: appName)
        selection = MenuSelection(rows: rows)
        highlight.active = nil
        setContent(.rows(rows))
    }

    private func setContent(_ newContent: MenuContent) {
        content = newContent
        // Don't clear highlight.rowFrames here: SwiftUI only re-reports row frames
        // when they change, so a reopened menu with identical rows would never
        // refill them and hover and clicks would find no row. The preference itself
        // goes empty when the content has no rows (the Copied confirmation).
        layout()
    }

    /// Measures the content, clamps it, and sits the panel under the status item,
    /// inside the visible frame of the screen the status item is on.
    private func layout() {
        hostingView.rootView = displayedView(scrollable: false)
        // Measured on a separate view: the displayed one has sizingOptions = [],
        // which also turns off its fittingSize.
        measuringView.rootView = MenuView(content: content, highlight: measuringHighlight)
        let natural = measuringView.fittingSize
        let placed = Self.placedFrame(of: statusItem)
        guard let screen = placed?.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame

        let width = ceil(min(max(natural.width, Self.minWidth), Self.maxWidth))
        // Hang 2pt under the status item. If it isn't placed yet (just after
        // launch), hang from the top of the visible frame under the pointer instead.
        let top = placed.map { min($0.frame.minY, screen.frame.maxY) - 2 } ?? visible.maxY - 2
        let available = top - visible.minY - Self.edgeGap
        let height = ceil(max(min(natural.height, available), 1))
        if height < natural.height {
            hostingView.rootView = displayedView(scrollable: true)
        }
        let anchorX = placed?.frame.midX ?? NSEvent.mouseLocation.x
        let x = round(min(
            max(anchorX - width / 2, visible.minX + Self.edgeGap),
            visible.maxX - width - Self.edgeGap
        ))
        panel.setFrame(NSRect(x: x, y: top - height, width: width, height: height), display: true)
    }

    private func displayedView(scrollable: Bool) -> MenuView {
        MenuView(content: content, highlight: highlight, scrollable: scrollable) { [weak self] index in
            self?.activate(index: index)
        }
    }

    private func hover(_ index: Int?) {
        selection.hover(index)
        highlight.active = selection.active
    }

    private func move(_ delta: Int) {
        selection.move(delta)
        highlight.active = selection.active
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53: // Escape
            hide()
        case _ where event.modifierFlags.contains(.command)
            && event.charactersIgnoringModifiers?.lowercased() == "q":
            // By character, not key code: key codes are positions on an ANSI
            // keyboard, so code 12 ("Q" here) is A on AZERTY and ' on Dvorak, and
            // matching it would quit on ⌘A there. Lowercased because the character
            // is "Q" under Caps Lock. The main menu's Quit item handles ⌘Q before
            // the event ever reaches this panel; this is the fallback for when the
            // menu doesn't match.
            hide()
            NSApp.terminate(nil)
        case 125: // ↓
            move(1)
        case 126: // ↑
            move(-1)
        case 36, 76, 49: // Return, keypad Enter, Space
            if let active = selection.active { activate(index: active) }
        default:
            return false
        }
        return true
    }

    /// Clicks in other apps never reach this process as local events. A global
    /// monitor sees them (mouse monitors need no Accessibility permission).
    private func installOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            self?.hide()
        }
    }

    private func removeOutsideClickMonitor() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
    }
}
