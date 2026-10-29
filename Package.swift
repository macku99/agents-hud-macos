// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AgentsHUD",
    platforms: [.macOS("27.0")],
    targets: [
        .target(name: "HerdrKit"),
        .target(name: "HerdrKitTesting", dependencies: ["HerdrKit"]),
        .target(name: "Transcript", dependencies: ["HerdrKit"]),
        .target(name: "HUDCore", dependencies: ["HerdrKit"]),
        .target(name: "DesktopSessions", dependencies: ["HerdrKit", "HUDCore"]),
        .target(name: "HUDApp", dependencies: ["HerdrKit", "HUDCore", "DesktopSessions", "Transcript"]),
        .executableTarget(name: "AgentsHUD", dependencies: ["HUDApp"]),
        .testTarget(name: "HerdrKitTests", dependencies: ["HerdrKit"]),
        .testTarget(name: "HerdrKitTestingTests", dependencies: ["HerdrKit", "HerdrKitTesting"]),
        .testTarget(name: "TranscriptTests", dependencies: ["Transcript", "HerdrKit"]),
        .testTarget(name: "HUDCoreTests", dependencies: ["HUDCore", "HerdrKit", "HerdrKitTesting"]),
        .testTarget(name: "DesktopSessionsTests", dependencies: ["DesktopSessions", "HUDCore", "HerdrKit"]),
        .testTarget(name: "HUDAppTests", dependencies: ["HUDApp", "HUDCore", "HerdrKit", "HerdrKitTesting"]),
    ]
)
