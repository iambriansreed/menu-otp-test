import AppKit

// Top-level code runs on the main thread; say so, since AppDelegate is @MainActor
MainActor.assumeIsolated {
    let delegate = AppDelegate()
    let app = NSApplication.shared
    app.delegate = delegate
    app.run()
}
