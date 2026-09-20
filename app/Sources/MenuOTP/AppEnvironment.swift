import Foundation

/// Launch mode and data location, resolved once at startup.
struct AppEnvironment {
    static let appName = "Menu OTP"
    static let bundleID = "com.iambrian.menu-otp"

    /// "0.1.0 (57)", read from the running bundle so it is never typed in Swift: the
    /// version is CFBundleShortVersionString in app/Resources/Info.plist (the one place it
    /// is set; see .scripts/version.mjs), and the build number is stamped into the built
    /// bundle by app/scripts/bundle.sh. Nil when run outside a bundle (`swift run`), which
    /// has no Info.plist to read.
    static var versionText: String? {
        let info = Bundle.main.infoDictionary
        guard let version = info?["CFBundleShortVersionString"] as? String else { return nil }
        guard let build = info?["CFBundleVersion"] as? String else { return version }
        return "\(version) (\(build))"
    }

    /// Set by `MENU_OTP_DEMO_FILE` (app/scripts/demo.sh). Demo mode loads accounts from
    /// that file of otpauth:// URLs, keeps data in a temp directory with a throwaway
    /// in-memory key, and never touches the real store, the Keychain or the login
    /// item. It has its own instance lock, so it runs alongside the real app.
    let demoFile: URL?
    let dataDirectory: URL
    /// `--self-test`: run the scripted UI checks in SelfTest.swift, then exit.
    let selfTest: Bool
    /// `--snapshot <dir>`: screenshot the menu and Settings into <dir>, then exit.
    let snapshotDirectory: URL?

    var isDemo: Bool { demoFile != nil }

    static func current(_ info: ProcessInfo = .processInfo) -> AppEnvironment {
        let demoFile = info.environment["MENU_OTP_DEMO_FILE"]
            .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
        // MENU_OTP_DEMO_DATA_DIR (demo mode only) gives a demo run its own data
        // directory, and so its own instance lock: app/scripts/demo.sh uses it for
        // --self-test and --snapshot so they run beside an interactive demo copy.
        let demoDataDirectory = info.environment["MENU_OTP_DEMO_DATA_DIR"]
            .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("menu-otp-demo")
        let dataDirectory = demoFile != nil
            ? demoDataDirectory
            : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(appName)

        // The test hooks only exist in demo mode, so they can never run against
        // real accounts or the Keychain.
        let args = info.arguments
        var snapshotDirectory: URL?
        if demoFile != nil, let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            snapshotDirectory = URL(fileURLWithPath: args[i + 1])
        }
        return AppEnvironment(
            demoFile: demoFile,
            dataDirectory: dataDirectory,
            selfTest: demoFile != nil && args.contains("--self-test"),
            snapshotDirectory: snapshotDirectory
        )
    }
}
