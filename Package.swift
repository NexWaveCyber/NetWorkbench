// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacNetworkWorkbench",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "NexWaveApp", targets: ["NexWaveApp"]),
        .library(name: "NetworkCore", targets: ["NetworkCore"]),
        .library(name: "DiagnosticsEngine", targets: ["DiagnosticsEngine"]),
        .library(name: "PingEngine", targets: ["PingEngine"]),
        .library(name: "DNSEngine", targets: ["DNSEngine"]),
        .library(name: "TracerouteEngine", targets: ["TracerouteEngine"]),
        .library(name: "HTTPInspector", targets: ["HTTPInspector"]),
        .library(name: "InvestigationKit", targets: ["InvestigationKit"]),
        .library(name: "PersistenceKit", targets: ["PersistenceKit"]),
        .library(name: "SecurityKit", targets: ["SecurityKit"]),
        .library(name: "CommandLibrary", targets: ["CommandLibrary"])
    ],
    dependencies: [],
    targets: [
        // Infrastructure Layer
        .target(
            name: "NetworkCore",
            dependencies: [],
            path: "Sources/NetworkCore"
        ),
        .target(
            name: "SecurityKit",
            dependencies: [],
            path: "Sources/SecurityKit"
        ),
        .target(
            name: "PersistenceKit",
            dependencies: ["NetworkCore"],
            path: "Sources/PersistenceKit",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),

        // Core Tooling Layer
        .target(
            name: "PingEngine",
            dependencies: ["NetworkCore"],
            path: "Sources/PingEngine"
        ),
        .target(
            name: "DNSEngine",
            dependencies: ["NetworkCore"],
            path: "Sources/DNSEngine"
        ),
        .target(
            name: "TracerouteEngine",
            dependencies: ["NetworkCore", "PingEngine"],
            path: "Sources/TracerouteEngine"
        ),
        .target(
            name: "HTTPInspector",
            dependencies: ["NetworkCore"],
            path: "Sources/HTTPInspector"
        ),
        .target(
            name: "CommandLibrary",
            dependencies: ["NetworkCore"],
            path: "Sources/CommandLibrary"
        ),

        // Diagnostics & Correlation Layer
        .target(
            name: "DiagnosticsEngine",
            dependencies: [
                "NetworkCore",
                "PingEngine",
                "DNSEngine",
                "TracerouteEngine",
                "HTTPInspector"
            ],
            path: "Sources/DiagnosticsEngine"
        ),

        // Investigation & Workflow Layer
        .target(
            name: "InvestigationKit",
            dependencies: [
                "NetworkCore",
                "DiagnosticsEngine",
                "PersistenceKit"
            ],
            path: "Sources/InvestigationKit"
        ),

        // Native macOS Application Entry Point
        .executableTarget(
            name: "NexWaveApp",
            dependencies: [
                "NetworkCore",
                "DiagnosticsEngine",
                "PingEngine",
                "DNSEngine",
                "TracerouteEngine",
                "HTTPInspector",
                "InvestigationKit",
                "PersistenceKit",
                "SecurityKit",
                "CommandLibrary"
            ],
            path: "Sources/NexWaveApp"
        ),

        // Test Suites
        .testTarget(
            name: "NetworkCoreTests",
            dependencies: ["NetworkCore"],
            path: "Tests/NetworkCoreTests"
        ),
        .testTarget(
            name: "DiagnosticsEngineTests",
            dependencies: ["DiagnosticsEngine", "NetworkCore", "PingEngine"],
            path: "Tests/DiagnosticsEngineTests"
        ),
        .testTarget(
            name: "PingEngineTests",
            dependencies: ["PingEngine", "NetworkCore"],
            path: "Tests/PingEngineTests"
        ),
        .testTarget(
            name: "DNSEngineTests",
            dependencies: ["DNSEngine", "NetworkCore"],
            path: "Tests/DNSEngineTests"
        ),
        .testTarget(
            name: "PersistenceKitTests",
            dependencies: ["PersistenceKit", "NetworkCore", "InvestigationKit"],
            path: "Tests/PersistenceKitTests"
        )
    ]
)
