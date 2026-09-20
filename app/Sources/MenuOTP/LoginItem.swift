import ServiceManagement

/// "Open at login", behind a protocol so demo mode never registers a throwaway
/// build folder with launchd.
@MainActor
protocol LoginItem: AnyObject {
    var isEnabled: Bool { get }
    /// Registered, but the user still has to allow it in System Settings.
    var needsApproval: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

/// Registers whichever bundle is running, so toggle it from the copy in
/// /Applications, not from build/.
@MainActor
final class MainAppLoginItem: LoginItem {
    var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

@MainActor
final class DemoLoginItem: LoginItem {
    private(set) var isEnabled = false
    var needsApproval: Bool { false }
    func setEnabled(_ enabled: Bool) { isEnabled = enabled }
}
