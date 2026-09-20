import AppKit

/// The borderless window standing in for the status item's menu. A real NSMenu
/// can't draw icons greyed-out until hovered, nor change its row metrics.
///
/// Non-activating is what makes it usable over a full-screen app: showing an
/// ordinary window activates the app, macOS answers by switching to the app's
/// Space, and the focus churn from that switch immediately dismisses the menu. A
/// non-activating panel takes key focus (for arrow keys and Escape) without
/// activating anything. So nothing here may ever call NSApp.activate().
final class MenuPanel: NSPanel {
    static let cornerRadius: CGFloat = 10

    /// Sees every keyDown before normal dispatch; returns true when it handled it.
    var keyHandler: ((NSEvent) -> Bool)?

    let effectView = NSVisualEffectView()

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .popUpMenu
        // Join whichever Space is active, full-screen ones included, the way a real
        // menu-bar menu does, instead of forcing a Space switch
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none

        // The blurred material menus are drawn with
        effectView.material = .menu
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.maskImage = Self.roundedMask(radius: Self.cornerRadius)
        contentView = effectView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, keyHandler?(event) == true { return }
        super.sendEvent(event)
    }

    /// Behind-window vibrancy ignores layer corner radii; a stretchable mask image
    /// is the supported way to round it.
    static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
