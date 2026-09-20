import AppKit
import OTPCore
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model: AccountsModel
    private let loginItem: LoginItem
    private(set) var window: NSWindow?
    /// What the next window opens with (snapshots use this to show an edit panel).
    var initialState = SettingsView.InitialState()

    init(model: AccountsModel, loginItem: LoginItem) {
        self.model = model
        self.loginItem = loginItem
    }

    func show() {
        let isNew = window == nil
        if window == nil {
            let hosting = NSHostingController(
                rootView: SettingsView(model: model, loginItem: loginItem, initial: initialState)
            )
            // The window's size is the user's; don't let SwiftUI's ideal size drive it
            hosting.sizingOptions = []
            let window = NSWindow(contentViewController: hosting)
            window.title = "\(AppEnvironment.appName) Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 480, height: 600))
            window.contentMinSize = NSSize(width: 380, height: 400)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        // In the Dock and Cmd-Tab only while Settings is open. Activating is right
        // here (unlike the popover): this is an ordinary window the user asked for.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        if isNew {
            // AppKit gives a new window's first text field (Add Account's URL field) the
            // keyboard focus; Settings should open with none. Deferred a turn so it
            // runs after SwiftUI's first layout has set that focus up.
            DispatchQueue.main.async { [weak window] in window?.makeFirstResponder(nil) }
        }
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        // Fresh window and form state next time, as in the Electron app
        window = nil
        NSApp.setActivationPolicy(.accessory)
    }
}
