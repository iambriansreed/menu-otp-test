// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MenuOTP",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MenuOTP", targets: ["MenuOTP"]),
    ],
    targets: [
        // Everything testable: TOTP, storage, parsing, favicons, and the account/menu state
        // machines. No AppKit or SwiftUI in here, so `swift test` exercises it headlessly.
        .target(name: "OTPCore"),
        // AppKit/SwiftUI shell. Swift 5 language mode on purpose: AppKit callbacks,
        // NSEvent monitors and NotificationCenter observers fight Swift 6's strict
        // Sendable checking for no safety gain in a single-threaded UI layer.
        .executableTarget(
            name: "MenuOTP",
            dependencies: ["OTPCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "OTPCoreTests", dependencies: ["OTPCore"]),
    ]
)
