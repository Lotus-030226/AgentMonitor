// swift-tools-version: 6.0
// Modified by Lotus for Agent Monitor. See docs/UPSTREAM.md.
import PackageDescription
import Foundation

var localTestTargets: [Target] = []
let packageDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let excludedDesktopResources = ["Resources/clawd-sprites.json"].filter {
    FileManager.default.fileExists(atPath: packageDirectory.appendingPathComponent("Sources/AgentHUDDesktop").appendingPathComponent($0).path)
}
if FileManager.default.fileExists(atPath: packageDirectory.appendingPathComponent("Tests").path) {
    localTestTargets = [
        .testTarget(name: "AgentHUDSupportTests", dependencies: ["AgentHUDSupport"]),
        .testTarget(name: "AgentHUDCoreTests", dependencies: ["AgentHUDCore", "AgentHUDSupport"],
                    resources: [.copy("Providers/Kit/Zstandard/Fixtures")]),
        .testTarget(name: "AgentHUDDesktopTests", dependencies: ["AgentHUDDesktop", "LocalMonitorUI", "LocalMonitorCore"]),
        .testTarget(name: "LocalMonitorCoreTests", dependencies: ["LocalMonitorCore"]),
    ]
}

let package = Package(
    name: "AgentHUDOpen",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AgentHUDSupport", targets: ["AgentHUDSupport"]),
        .library(name: "AgentHUDCore", targets: ["AgentHUDCore"]),
        .library(name: "AgentHUDDesktop", targets: ["AgentHUDDesktop"]),
        .executable(name: "AgentHUDOpen", targets: ["AgentHUDOpenApp"]),
        .executable(name: "AgentMonitor", targets: ["AgentHUDOpenApp"]),
    ],
    targets: [
        .target(name: "AgentHUDSupport", swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(name: "AgentHUDCore", dependencies: ["AgentHUDSupport"], swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(name: "AgentHUDDesktop", dependencies: ["AgentHUDCore"], exclude: excludedDesktopResources,
                resources: [.process("Resources")], swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(name: "LocalMonitorCore", swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(name: "LocalMonitorUI", dependencies: ["LocalMonitorCore", "AgentHUDDesktop"], swiftSettings: [.swiftLanguageMode(.v6)]),
        .executableTarget(name: "AgentHUDOpenApp", dependencies: ["AgentHUDDesktop", "AgentHUDCore", "LocalMonitorUI", "LocalMonitorCore"], swiftSettings: [.swiftLanguageMode(.v6)]),
    ] + localTestTargets
)
