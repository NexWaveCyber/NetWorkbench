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
        .library(name: "CommandLibrary", targets: ["CommandLibrary"]),
        .library(name: "InternetIntel", targets: ["InternetIntel"]),
        .library(name: "DeviceKit", targets: ["DeviceKit"]),
        .library(name: "SNMPEngine", targets: ["SNMPEngine"]),
        .library(name: "ConfigKit", targets: ["ConfigKit"]),
        .library(name: "ParserKit", targets: ["ParserKit"]),
        .library(name: "PacketKit", targets: ["PacketKit"]),
        .library(name: "ReportingKit", targets: ["ReportingKit"]),
        .library(name: "WiFiKit", targets: ["WiFiKit"]),
        .library(name: "TimeSeriesKit", targets: ["TimeSeriesKit"]),
        .library(name: "TerminalKit", targets: ["TerminalKit"])
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
        .target(
            name: "DeviceKit",
            dependencies: ["NetworkCore", "PersistenceKit", "SecurityKit", "PingEngine"],
            path: "Sources/DeviceKit"
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
            dependencies: ["NetworkCore", "PingEngine", "InternetIntel"],
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
        .target(
            name: "InternetIntel",
            dependencies: ["NetworkCore"],
            path: "Sources/InternetIntel"
        ),
        .target(
            name: "SNMPEngine",
            dependencies: ["NetworkCore"],
            path: "Sources/SNMPEngine"
        ),
        .target(
            name: "ConfigKit",
            dependencies: ["NetworkCore", "SecurityKit"],
            path: "Sources/ConfigKit"
        ),
        .target(
            name: "ParserKit",
            dependencies: ["NetworkCore", "DeviceKit"],
            path: "Sources/ParserKit"
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
                "CommandLibrary",
                "InternetIntel",
                "DeviceKit",
                "SNMPEngine",
                "ConfigKit",
                "ParserKit",
                "PacketKit",
                "ReportingKit",
                "WiFiKit",
                "TimeSeriesKit",
                "TerminalKit"
            ],
            path: "Sources/NexWaveApp"
        ),
        .target(
            name: "TerminalKit",
            dependencies: ["NetworkCore", "DeviceKit", "CommandLibrary"],
            path: "Sources/TerminalKit"
        ),
        .target(
            name: "WiFiKit",
            dependencies: ["NetworkCore", "DeviceKit"],
            path: "Sources/WiFiKit"
        ),
        .target(
            name: "TimeSeriesKit",
            dependencies: ["NetworkCore", "PersistenceKit", "PingEngine"],
            path: "Sources/TimeSeriesKit"
        ),
        .target(
            name: "PacketKit",
            dependencies: ["NetworkCore"],
            path: "Sources/PacketKit"
        ),
        .target(
            name: "ReportingKit",
            dependencies: [
                "NetworkCore",
                "DiagnosticsEngine",
                "InvestigationKit",
                "DeviceKit",
                "ConfigKit",
                "SecurityKit",
                "PacketKit"
            ],
            path: "Sources/ReportingKit"
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
        ),
        .testTarget(
            name: "InternetIntelTests",
            dependencies: ["InternetIntel", "NetworkCore"],
            path: "Tests/InternetIntelTests"
        ),
        .testTarget(
            name: "DeviceKitTests",
            dependencies: ["DeviceKit", "NetworkCore", "PersistenceKit", "SecurityKit"],
            path: "Tests/DeviceKitTests"
        ),
        .testTarget(
            name: "SNMPEngineTests",
            dependencies: ["SNMPEngine", "NetworkCore"],
            path: "Tests/SNMPEngineTests"
        ),
        .testTarget(
            name: "ConfigKitTests",
            dependencies: ["ConfigKit", "NetworkCore"],
            path: "Tests/ConfigKitTests"
        ),
        .testTarget(
            name: "ParserKitTests",
            dependencies: ["ParserKit", "NetworkCore"],
            path: "Tests/ParserKitTests"
        ),
        .testTarget(
            name: "PacketKitTests",
            dependencies: ["PacketKit", "NetworkCore"],
            path: "Tests/PacketKitTests"
        ),
        .testTarget(
            name: "ReportingKitTests",
            dependencies: ["ReportingKit", "NetworkCore", "InvestigationKit", "SecurityKit"],
            path: "Tests/ReportingKitTests"
        ),
        .testTarget(
            name: "WiFiKitTests",
            dependencies: ["WiFiKit", "NetworkCore", "DeviceKit"],
            path: "Tests/WiFiKitTests"
        ),
        .testTarget(
            name: "TimeSeriesKitTests",
            dependencies: ["TimeSeriesKit", "PersistenceKit", "NetworkCore"],
            path: "Tests/TimeSeriesKitTests"
        ),
        .testTarget(
            name: "TerminalKitTests",
            dependencies: ["TerminalKit", "NetworkCore"],
            path: "Tests/TerminalKitTests"
        )
    ]
)
