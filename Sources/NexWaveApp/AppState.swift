import SwiftUI
import NetworkCore
import DiagnosticsEngine
import InvestigationKit
import PersistenceKit
import CommandLibrary
import DeviceKit
import SNMPEngine
import TerminalKit
import TimeSeriesKit

public enum WorkspaceItem: String, CaseIterable, Identifiable, Sendable {
    case home = "Home / Dashboard"
    case diagnose = "Diagnose"
    case toolbox = "Toolbox"
    case wifi = "Wi-Fi Studio"
    case timeline = "Timeline Monitor"
    case devices = "Devices"
    case terminal = "Terminal & Console"
    case snmp = "SNMP Studio"
    case config = "Config Workbench"
    case packet = "Packet Workbench"
    case investigations = "Investigations"
    case environments = "Environments"
    case commandLibrary = "Command Library"
    case history = "History"
    case settings = "Settings"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .home: return "house.fill"
        case .diagnose: return "stethoscope"
        case .toolbox: return "wrench.and.screwdriver"
        case .wifi: return "wifi"
        case .timeline: return "chart.xyaxis.line"
        case .devices: return "server.rack"
        case .terminal: return "terminal.fill"
        case .snmp: return "chart.bar.xaxis"
        case .config: return "doc.text.magnifyingglass"
        case .packet: return "waveform.path.ecg"
        case .investigations: return "briefcase.fill"
        case .environments: return "network"
        case .commandLibrary: return "books.vertical.fill"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "gearshape.fill"
        }
    }
}

@Observable
public final class AppState: @unchecked Sendable {
    public var selectedWorkspace: WorkspaceItem = .home
    public var showCommandPalette: Bool = false

    // Target input in hero / diagnose
    public var targetInput: String = "api.example.com"
    public var customPort: UInt16? = nil
    public var classifiedTarget: NetworkTarget? = nil

    // Active Diagnosis
    public var isDiagnosing: Bool = false
    public var currentProgress: PipelineProgress? = nil
    public var latestResult: DiagnosticResult? = nil

    // Data Management
    public let database: SQLiteDatabase
    public let investigationManager: InvestigationManager
    public var investigations: [Investigation] = []
    public var recentHistory: [DiagnosticHistoryRecord] = []
    public var selectedInvestigation: Investigation? = nil

    // Phase 3: Device Management & Discovery
    public let deviceManager: DeviceManager
    public var managedDevices: [NetworkDevice] = []
    public var selectedDevice: NetworkDevice? = nil
    public var discoveredNeighbors: [DiscoveredNeighbor] = []
    public var isDiscoveringNeighbors: Bool = false
    public var lastNeighborDiscoveryTime: Date? = nil

    // Phase 6: Terminal & Console Sessions
    public let terminalManager: TerminalManager = TerminalManager()

    // Phase 7: Time-Series & Continuous Monitoring
    public let timeSeriesRepository: TimeSeriesRepository
    public let monitorService: BackgroundMonitorService

    // Alerts and feedback
    public var toastMessage: String? = nil

    public init() {
        do {
            let db = try SQLiteDatabase()
            self.database = db
            self.investigationManager = InvestigationManager(database: db)
            self.deviceManager = DeviceManager(database: db)
            let tsRepo = TimeSeriesRepository(database: db)
            self.timeSeriesRepository = tsRepo
            let monService = BackgroundMonitorService(repository: tsRepo)
            self.monitorService = monService

            self.investigations = (try? investigationManager.listInvestigations()) ?? []
            self.recentHistory = (try? investigationManager.fetchRecentHistory(limit: 20)) ?? []
            self.managedDevices = (try? deviceManager.listDevices()) ?? []
            if self.managedDevices.isEmpty {
                let seed1 = NetworkDevice(
                    name: "core-sw01.sfo",
                    hostname: "core-sw01.sfo.nexwave.net",
                    ipAddress: "192.168.1.1",
                    macAddress: "00:1C:58:29:41:A0",
                    vendor: .cisco,
                    role: .switchRole,
                    status: .online,
                    location: "SFO Data Center - Rack 14B",
                    tags: ["core", "distribution", "snmp-v2c"],
                    snmpConfig: SNMPDeviceConfig(community: "public", port: 161, version: "v2c")
                )
                let seed2 = NetworkDevice(
                    name: "edge-gw01",
                    hostname: "gw01.nexwave.internal",
                    ipAddress: "192.168.1.254",
                    macAddress: "00:0C:29:84:11:BC",
                    vendor: .fortinet,
                    role: .firewall,
                    status: .online,
                    location: "SFO Perimeter",
                    tags: ["firewall", "bgp-peer", "perimeter"],
                    snmpConfig: SNMPDeviceConfig(community: "public", port: 161, version: "v2c")
                )
                let seed3 = NetworkDevice(
                    name: "ap-floor3-east",
                    hostname: "ap3e.internal",
                    ipAddress: "192.168.1.50",
                    macAddress: "F0:9F:C2:11:22:33",
                    vendor: .ubiquiti,
                    role: .accessPoint,
                    status: .online,
                    location: "Building A, 3rd Floor",
                    tags: ["wifi", "poe", "access"]
                )
                try? deviceManager.createDevice(seed1)
                try? deviceManager.createDevice(seed2)
                try? deviceManager.createDevice(seed3)
                self.managedDevices = [seed1, seed2, seed3]
            }

            // Seed monitor targets if empty
            var existingTargets = (try? tsRepo.fetchTargets()) ?? []
            if existingTargets.isEmpty {
                let liveGW = MenuBarMonitorEngine.shared.defaultGateway.isEmpty ? "192.168.10.1" : MenuBarMonitorEngine.shared.defaultGateway
                let seedGW = MonitorTargetConfig(
                    target: liveGW,
                    name: "Local Default Gateway",
                    intervalSeconds: 2.5,
                    latencyThresholdMs: 30.0,
                    packetLossThresholdPct: 5.0,
                    isEnabled: true,
                    probeProtocol: .icmp
                )
                let seedCloudflare = MonitorTargetConfig(
                    target: "1.1.1.1",
                    name: "Cloudflare Edge DNS",
                    intervalSeconds: 2.5,
                    latencyThresholdMs: 50.0,
                    packetLossThresholdPct: 5.0,
                    isEnabled: true,
                    probeProtocol: .icmp
                )
                let seedGoogle = MonitorTargetConfig(
                    target: "8.8.8.8",
                    name: "Google Core Anycast",
                    intervalSeconds: 2.5,
                    latencyThresholdMs: 60.0,
                    packetLossThresholdPct: 5.0,
                    isEnabled: true,
                    probeProtocol: .icmp
                )
                try? tsRepo.insertOrUpdateTarget(config: seedGW)
                try? tsRepo.insertOrUpdateTarget(config: seedCloudflare)
                try? tsRepo.insertOrUpdateTarget(config: seedGoogle)
                existingTargets = [seedGW, seedCloudflare, seedGoogle]
            }

            Task {
                await monService.updateConfigs(existingTargets)
                await monService.startAll()
                try? tsRepo.pruneOldSamples(olderThanDays: 7)
            }
        } catch {
            fatalError("Failed to initialize SQLite persistence: \(error)")
        }

        self.updateTargetClassification(self.targetInput)
    }

    public func updateTargetClassification(_ text: String) {
        self.targetInput = text
        self.classifiedTarget = TargetClassifier.classify(text)
        if let target = self.classifiedTarget, case .url(let u) = target, let port = u.port {
            self.customPort = UInt16(port)
        }
    }

    @MainActor
    public func runDiagnosis(target: NetworkTarget, port: UInt16? = nil) async {
        self.isDiagnosing = true
        self.currentProgress = PipelineProgress(stage: .resolvingDNS, percentage: 0.05, message: "Initializing diagnostic pipeline...")

        let pipeline = DiagnosticPipeline()
        let customNetPort = (port ?? customPort).map { NetworkPort($0) }
        let result = await pipeline.execute(target: target, customPort: customNetPort) { progress in
            Task { @MainActor in
                self.currentProgress = progress
            }
        }

        self.latestResult = result
        self.isDiagnosing = false
        self.currentProgress = nil

        // Record history locally
        try? self.investigationManager.recordHistory(result: result)
        self.refreshHistory()
    }

    public func refreshInvestigations() {
        if let list = try? investigationManager.listInvestigations() {
            self.investigations = list
        }
    }

    public func refreshHistory() {
        if let list = try? investigationManager.fetchRecentHistory(limit: 20) {
            self.recentHistory = list
        }
    }

    public func createInvestigationFromLatestResult() {
        guard let result = latestResult else { return }
        let title = "Investigation: \(result.target.displayString) Connectivity"
        let desc = "Automated investigation initialized from diagnosis on \(Date().formatted()). \(result.overallSummary)"
        let severity: InvestigationSeverity = result.overallStatus == .critical || result.overallStatus == .unreachable ? .high : .medium

        if let inv = try? investigationManager.createInvestigation(title: title, description: desc, severity: severity) {
            try? investigationManager.attachDiagnosticResult(result, toInvestigationId: inv.id)
            self.refreshInvestigations()
            self.selectedInvestigation = inv
            self.selectedWorkspace = .investigations
            self.toastMessage = "Investigation created successfully."
        }
    }

    // MARK: - Phase 3: Device & Discovery Actions

    public func refreshManagedDevices() {
        if let list = try? deviceManager.listDevices() {
            self.managedDevices = list
        }
    }

    @MainActor
    public func runLocalDiscovery() async {
        self.isDiscoveringNeighbors = true
        let engine = LocalDiscoveryEngine()
        let neighbors = await engine.discoverNeighbors()
        self.discoveredNeighbors = neighbors
        self.lastNeighborDiscoveryTime = Date()
        self.isDiscoveringNeighbors = false
    }

    public func addDiscoveredNeighborToInventory(_ neighbor: DiscoveredNeighbor, role: DeviceRole, name: String) {
        let device = NetworkDevice(
            name: name.isEmpty ? (neighbor.hostname ?? neighbor.ip) : name,
            hostname: neighbor.hostname,
            ipAddress: neighbor.ip,
            macAddress: neighbor.mac,
            vendor: neighbor.vendor,
            role: role,
            status: .online,
            tags: ["discovered", neighbor.source.rawValue]
        )
        do {
            try deviceManager.saveDevice(device)
            refreshManagedDevices()
            self.toastMessage = "Enrolled \(device.name) into Managed Inventory"
        } catch {
            self.toastMessage = "Failed to save device: \(error.localizedDescription)"
        }
    }

    public func addManualDevice(_ device: NetworkDevice) {
        do {
            try deviceManager.saveDevice(device)
            refreshManagedDevices()
            self.toastMessage = "Saved device \(device.name)"
        } catch {
            self.toastMessage = "Failed to save device: \(error.localizedDescription)"
        }
    }

    public func deleteDevice(id: UUID) {
        do {
            try deviceManager.deleteDevice(id: id)
            if selectedDevice?.id == id {
                selectedDevice = nil
            }
            refreshManagedDevices()
            self.toastMessage = "Device removed from inventory"
        } catch {
            self.toastMessage = "Failed to delete device: \(error.localizedDescription)"
        }
    }
}
