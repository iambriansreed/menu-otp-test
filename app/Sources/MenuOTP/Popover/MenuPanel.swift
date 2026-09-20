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

    /// Sits over the material and under the menu content; see the tint note in init().
    ///
    /// It draws rather than setting a layer colour because resolving a dynamic NSColor to a
    /// CGColor freezes it at whatever appearance was current then; drawing re-resolves it,
    /// and AppKit already redraws a view when the effective appearance changes.
    private final class TintView: NSView {
        /// Black at 50% in dark mode, nothing in light mode.
        private static let tint = NSColor(name: "menuTint") { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(white: 0, alpha: isDark ? 0.5 : 0)
        }

        // The content above must stay clickable; this view is decoration only.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func draw(_ dirtyRect: NSRect) {
            Self.tint.setFill()
            dirtyRect.fill()
        }
    }

    private let tintView = TintView()

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

        // .menu is the material a menu is *meant* to use, but in dark mode it lands well
        // short of the real thing: measured against a real NSMenu on the same backdrop, it
        // renders 50,50,50 where the menu renders 25,25,25 — noticeably lighter than the
        // menus either side of ours in the menu bar. Nothing on the effect view closes the
        // gap (isEmphasized, a forced vibrantDark/darkAqua appearance and .popover were all
        // measured and change nothing), so a tint layer over the material does it: 50%
        // black takes 50 to exactly 25.
        //
        // The tint is a dynamic colour rather than a constant because that correction is a
        // dark-mode one. Light mode is left alone: its material already reads as a light
        // menu, and dropping 50% black over it would be plainly wrong.
        tintView.frame = effectView.bounds
        tintView.autoresizingMask = [.width, .height]
        effectView.addSubview(tintView)
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
