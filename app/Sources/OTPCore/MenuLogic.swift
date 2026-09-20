import Foundation

/// One row of the menu-bar popover.
public struct MenuRow: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case header
        case item
        case separator
    }

    public enum Action: Equatable, Sendable {
        /// Resolved by identity at click time, never by index, so a click still finds
        /// the right account if Settings reordered the list since the menu opened.
        case copy(AccountIdentity)
        case settings
        case quit
    }

    public var kind: Kind
    public var label: String
    public var action: Action?
    /// The account's raw `icon` string (emoji or data URL), if any.
    public var icon: String?
    /// Right-aligned hint, e.g. "⌘Q".
    public var accelerator: String?

    public init(kind: Kind, label: String = "", action: Action? = nil, icon: String? = nil, accelerator: String? = nil) {
        self.kind = kind
        self.label = label
        self.action = action
        self.icon = icon
        self.accelerator = accelerator
    }

    public var isSelectable: Bool { kind == .item && action != nil }
}

public enum MenuRows {
    public static func build(accounts: [Account], lastClicked: Account?, appName: String) -> [MenuRow] {
        var rows: [MenuRow] = []
        if let lastClicked {
            rows.append(MenuRow(kind: .header, label: "Last clicked: \(lastClicked.label)"))
        }
        if accounts.isEmpty {
            // True first run only. Every account being hidden is a deliberate choice
            // and gets no nudge.
            rows.append(MenuRow(kind: .item, label: "Add Your First Account...", action: .settings))
        } else {
            for account in accounts where !account.hidden {
                rows.append(MenuRow(kind: .item, label: account.label, action: .copy(account.identity), icon: account.icon))
            }
        }
        rows.append(MenuRow(kind: .separator))
        rows.append(MenuRow(kind: .item, label: "\(appName) Settings...", action: .settings))
        rows.append(MenuRow(kind: .item, label: "Quit \(appName)", action: .quit, accelerator: "⌘Q"))
        return rows
    }
}

/// Keyboard/pointer highlight over the popover's rows. Arrow keys step through
/// selectable rows only and wrap at both ends, like a native menu.
public struct MenuSelection: Equatable, Sendable {
    public private(set) var selectable: [Int]
    public private(set) var active: Int?

    public init(rows: [MenuRow]) {
        selectable = rows.indices.filter { rows[$0].isSelectable }
        active = nil
    }

    public mutating func move(_ delta: Int) {
        guard !selectable.isEmpty else { return }
        guard let active, let at = selectable.firstIndex(of: active) else {
            self.active = delta > 0 ? selectable.first : selectable.last
            return
        }
        let count = selectable.count
        self.active = selectable[((at + delta) % count + count) % count]
    }

    /// Pointer hover: only selectable rows highlight; anything else clears.
    public mutating func hover(_ index: Int?) {
        if let index, selectable.contains(index) { active = index } else { active = nil }
    }
}

/// Status-item click handling. A click on an open menu closes it. The guard stops
/// the click that *just* dismissed the menu (via resign-key firing first) from
/// immediately reopening it.
public struct MenuToggleGate: Sendable {
    public static let reopenGuard: TimeInterval = 0.25

    public enum Decision: Equatable, Sendable {
        case show
        case hide
        case ignore
    }

    private var hiddenAt = Date.distantPast

    public init() {}

    public mutating func didHide(at date: Date) {
        hiddenAt = date
    }

    public func onClick(isVisible: Bool, now: Date) -> Decision {
        if isVisible { return .hide }
        return now.timeIntervalSince(hiddenAt) > Self.reopenGuard ? .show : .ignore
    }
}
