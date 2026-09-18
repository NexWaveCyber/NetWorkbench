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

public enum FleetViewMode: String, CaseIterable, Identifiable, Sendable {
    case grid = "Grid Cards"
    case table = "Dense Table"

    public var id: String { rawValue }
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
    public let deviceAuditor: DeviceAuditor = DeviceAuditor()
    public var managedDevices: [NetworkDevice] = []
    public var selectedDevice: NetworkDevice? = nil
    public var fleetViewMode: FleetViewMode = .grid
    public var selectedDeviceIds: Set<UUID> = []
    public var isSelectionMode: Bool = false
    public var isFleetBaselineAuditing: Bool = false
    public var fleetBaselineAuditProgress: Double = 0.0
    public var fleetDriftCompliancePct: Double = 100.0
    public var driftDegradedDevices: [UUID: BaselineComparisonResult] = [:]
    public var selectedToolboxTool: ToolboxTool = .ports
    public var portDiagnosticsTarget: String = ""
    public var discoveredNeighbors: [DiscoveredNeighbor] = []
    public var isDiscoveringNeighbors: Bool = false
    public var lastNeighborDiscoveryTime: Date? = nil

    public struct DiscoveryProgressInfo: Sendable {
        public var phase: String
        public var current: Int
        public var total: Int
        public var percent: Double
        public var activeHost: String

        public init(phase: String = "Idle", current: Int = 0, total: Int = 0, percent: Double = 0.0, activeHost: String = "") {
            self.phase = phase
            self.current = current
            self.total = total
            self.percent = percent
            self.activeHost = activeHost
        }
    }

    public var discoveryProgress: DiscoveryProgressInfo = DiscoveryProgressInfo()
    public var activeSubnetDetected: String = ""
    public var activeInterfaceDetected: String = ""
    public var activeGatewayDetected: String = ""
    public var customScanCIDR: String = ""
    public var availableInterfaces: [ActiveNetworkInterface] = []
    public var selectedInterfaceName: String = ""
    public var activeDiscoveryTask: Task<Void, Never>? = nil

    // SNMP Studio target handoff
    public var activeSNMPTarget: String = "192.168.1.1"
    public var activeSNMPPort: String = "161"
    public var activeSNMPCommunity: String = "public"
    public var activeSNMPVersion: String = "v2c"

    // Phase 6: Terminal & Console Sessions
    public var terminalManager: TerminalManager = TerminalManager()

    // Config Workbench Cross-Handoff Bridge
    public var configWorkbenchText: String? = nil
    public var cliParserInputText: String? = nil
    public var configWorkbenchTargetTab: Int? = nil // 0: Studio, 1: Diff, 2: ACL, 3: CLI Parser, 4: Compliance

    // Phase 7: Time-Series & Continuous Monitoring
    public let timeSeriesRepository: TimeSeriesRepository
    public let monitorService: BackgroundMonitorService

    // Operations & Evidence: Environments & Custom Commands
    public let environmentRepository: EnvironmentRepository
    public let customCommandRepository: CustomCommandRepository
    public var siteEnvironments: [EnvironmentRecord] = []
    public var activeSiteEnvironment: EnvironmentRecord? = nil
    public var customCommandsList: [CustomCommandRecord] = []

    // Alerts and feedback
    public var toastMessage: String? = nil

    public init() {
        let db: SQLiteDatabase
        do {
            db = try SQLiteDatabase()
        } catch {
            print("[AppState] Warning: Could not open persistent SQLite database: \(error). Falling back to in-memory SQLite database.")
            do {
                db = try SQLiteDatabase(path: ":memory:")
            } catch {
                let tempPath = FileManager.default.temporaryDirectory.appendingPathComponent("nexwave_temp_\(UUID().uuidString).sqlite").path
                db = (try? SQLiteDatabase(path: tempPath)) ?? (try? SQLiteDatabase(path: ":memory:")) ?? {
                    // Fallback to empty SQLiteDatabase in temp directory
                    try! SQLiteDatabase(path: tempPath)
                }()
            }
        }

        self.database = db
        self.investigationManager = InvestigationManager(database: db)
        self.deviceManager = DeviceManager(database: db)
        let tsRepo = TimeSeriesRepository(database: db)
        self.timeSeriesRepository = tsRepo
        let monService = BackgroundMonitorService(repository: tsRepo)
        self.monitorService = monService

        let envRepo = EnvironmentRepository(database: db)
        self.environmentRepository = envRepo
        try? envRepo.seedDefaultsIfEmpty()
        self.siteEnvironments = (try? envRepo.fetchAll()) ?? []
        self.activeSiteEnvironment = (try? envRepo.fetchActive())

        let cmdRepo = CustomCommandRepository(database: db)
        self.customCommandRepository = cmdRepo
        self.customCommandsList = (try? cmdRepo.fetchAll()) ?? []

        Task {
            await monService.setOnAlertTriggered { alert in
                NotificationManager.shared.postSLAAlert(alert)
            }
        }

        self.investigations = (try? investigationManager.listInvestigations()) ?? []
        try? investigationManager.seedDemoHistoryIfEmpty()
        self.recentHistory = (try? investigationManager.fetchRecentHistory(limit: 100)) ?? []
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

        // Auto-enrich any existing devices with missing MAC or generic vendor using live ARP
        for i in 0..<self.managedDevices.count {
            var dev = self.managedDevices[i]
            if (dev.macAddress == nil || dev.macAddress?.isEmpty == true || dev.vendor == .generic) && !dev.managementIP.isEmpty {
                if let resolved = LocalDiscoveryEngine.resolveLocalHost(ip: dev.managementIP) {
                    dev.macAddress = resolved.mac
                    if dev.vendor == .generic {
                        dev.vendor = resolved.vendor
                    }
                    try? self.deviceManager.updateDevice(dev)
                    self.managedDevices[i] = dev
                }
            }
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
            // Do not auto-start background monitoring on launch; monitoring runs when TimeSeriesStudio is opened
            try? tsRepo.pruneOldSamples(olderThanDays: 2)
        }

        self.updateTargetClassification(self.targetInput)
        self.refreshNetworkInterfaces()
    }

    public func refreshNetworkInterfaces() {
        self.availableInterfaces = LocalDiscoveryEngine.enumerateActiveInterfaces()
        if self.selectedInterfaceName.isEmpty || !self.availableInterfaces.contains(where: { $0.name == self.selectedInterfaceName }) {
            if let active = LocalDiscoveryEngine.resolveActiveInterface() {
                self.selectedInterfaceName = active.name
                self.activeSubnetDetected = active.cidr
                self.activeInterfaceDetected = "\(active.name) (\(active.ipv4))"
                self.activeGatewayDetected = active.gateway.isEmpty ? "Unknown" : active.gateway
            }
        } else if let matched = self.availableInterfaces.first(where: { $0.name == self.selectedInterfaceName }) {
            self.activeSubnetDetected = matched.cidr
            self.activeInterfaceDetected = "\(matched.name) (\(matched.ipv4))"
            self.activeGatewayDetected = matched.gateway.isEmpty ? "Unknown" : matched.gateway
        }
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

    public func refreshHistory(limit: Int = 100) {
        if let list = try? investigationManager.fetchRecentHistory(limit: limit) {
            self.recentHistory = list
        }
    }

    public func deleteHistoryRecord(id: String) {
        try? investigationManager.deleteHistory(id: id)
        refreshHistory()
    }

    public func purgeHistory(olderThanDays days: Int) {
        try? investigationManager.purgeHistory(olderThanDays: days)
        refreshHistory()
        self.toastMessage = "Purged diagnostic records older than \(days) days."
    }

    public func clearAllHistory() {
        try? investigationManager.clearAllHistory()
        self.recentHistory.removeAll()
        self.toastMessage = "Cleared all diagnostic history records."
    }

    public func createInvestigationFromHistoryRecord(_ record: DiagnosticHistoryRecord) {
        let title = "Incident: \(record.target) Diagnostic Failure"
        let desc = "Investigation opened from historic diagnostic run recorded on \(Date(timeIntervalSince1970: record.timestamp).formatted()). Summary: \(record.summary)"
        let severity: InvestigationSeverity = (!record.tcpHealthy || (record.packetLoss ?? 0) > 20) ? .high : .medium

        if let inv = try? investigationManager.createInvestigation(title: title, description: desc, severity: severity) {
            if let data = record.rawJson.data(using: .utf8) {
                _ = try? investigationManager.attachEvidenceData(
                    investigationId: inv.id,
                    title: "Diagnostic Run (\(record.target))",
                    filename: "diagnostic_\(record.target).json",
                    type: .diagnosticProbe,
                    data: data,
                    sourceWorkbench: "Diagnostic History",
                    notes: "Target: \(record.target), Type: \(record.targetType), Ping: \(record.pingLatency ?? 0)ms, Loss: \(record.packetLoss ?? 0)%"
                )
            }
            self.refreshInvestigations()
            self.selectedInvestigation = inv
            self.selectedWorkspace = .investigations
            self.toastMessage = "Promoted \(record.target) test to Investigation incident."
        }
    }

    public func retestHistoryTarget(_ record: DiagnosticHistoryRecord) {
        self.targetInput = record.target
        self.selectedWorkspace = .diagnose
        self.toastMessage = "Loaded \(record.target) for diagnosis."
    }

    public func vacuumDatabase() {
        try? database.execute(sql: "VACUUM;")
        try? database.execute(sql: "ANALYZE;")
        self.toastMessage = "SQLite database vacuumed and optimized."
    }

    public func backupDatabase(to destinationURL: URL) throws {
        try database.backupDatabase(to: destinationURL)
        self.toastMessage = "Database backup saved to \(destinationURL.lastPathComponent)."
    }

    public func getDatabaseStats() -> (fileSizeBytes: Int64, rowCounts: [String: Int]) {
        return (database.databaseFileSize(), database.tableRowCounts())
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
            var updatedList = list
            for i in 0..<updatedList.count {
                var dev = updatedList[i]
                if (dev.macAddress == nil || dev.macAddress?.isEmpty == true || dev.vendor == .generic) && !dev.managementIP.isEmpty {
                    if let resolved = LocalDiscoveryEngine.resolveLocalHost(ip: dev.managementIP) {
                        dev.macAddress = resolved.mac
                        if dev.vendor == .generic {
                            dev.vendor = resolved.vendor
                        }
                        try? self.deviceManager.updateDevice(dev)
                        updatedList[i] = dev
                    }
                }
            }
            self.managedDevices = updatedList
        }
    }

    @MainActor
    public func runLocalDiscovery(customCIDR: String? = nil, targetInterface: String? = nil, performSweep: Bool = true) async {
        if self.isDiscoveringNeighbors { return }

        let ifaceName = targetInterface ?? (self.selectedInterfaceName.isEmpty ? nil : self.selectedInterfaceName)

        let cidrToScan = (customCIDR?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? customCIDR
            : (self.customScanCIDR.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self.customScanCIDR)

        self.isDiscoveringNeighbors = true
        self.discoveryProgress = DiscoveryProgressInfo(phase: "Initializing multi-vector discovery...", current: 0, total: 100, percent: 0.0)

        // Query active interfaces for freshest telemetry
        self.refreshNetworkInterfaces()

        let task = Task { [weak self] () -> [DiscoveredNeighbor] in
            guard let self = self else { return [] }
            let engine = LocalDiscoveryEngine()
            let neighbors = await engine.discoverNeighbors(
                customSubnet: cidrToScan,
                targetInterface: ifaceName,
                performSweep: performSweep
            ) { [weak self] phase, current, total in
                Task { @MainActor [weak self] in
                    let pct = total > 0 ? Double(current) / Double(total) : 0.0
                    self?.discoveryProgress = DiscoveryProgressInfo(
                        phase: phase,
                        current: current,
                        total: total,
                        percent: pct,
                        activeHost: ""
                    )
                }
            }
            return neighbors
        }

        self.activeDiscoveryTask = Task {
            _ = await task.value
        }

        let neighbors = await task.value

        if Task.isCancelled {
            self.isDiscoveringNeighbors = false
            self.activeDiscoveryTask = nil
            self.discoveryProgress = DiscoveryProgressInfo(phase: "Scan aborted", current: 0, total: 0, percent: 0.0)
            self.toastMessage = "Scan LAN operation cancelled"
            return
        }

        self.discoveredNeighbors = neighbors
        self.lastNeighborDiscoveryTime = Date()
        self.isDiscoveringNeighbors = false
        self.activeDiscoveryTask = nil
        self.discoveryProgress = DiscoveryProgressInfo(phase: "Scan Complete", current: neighbors.count, total: neighbors.count, percent: 1.0)
        self.toastMessage = "Discovered \(neighbors.count) active hosts on LAN"
    }

    @MainActor
    public func cancelLocalDiscovery() {
        if let task = self.activeDiscoveryTask {
            task.cancel()
            self.activeDiscoveryTask = nil
        }
        self.isDiscoveringNeighbors = false
        self.discoveryProgress = DiscoveryProgressInfo(phase: "Scan aborted", current: 0, total: 0, percent: 0.0)
        self.toastMessage = "Scan LAN operation cancelled"
    }

    @MainActor
    public func enrolAllDiscoveredNeighbors() {
        let existingIPs = Set(managedDevices.map { $0.managementIP })
        let unenrolled = discoveredNeighbors.filter { !existingIPs.contains($0.ip) }
        guard !unenrolled.isEmpty else {
            self.toastMessage = "All discovered devices are already enrolled in inventory"
            return
        }

        var count = 0
        for neighbor in unenrolled {
            let finalVendor = neighbor.vendor != .generic ? neighbor.vendor : OUIResolver.inferVendor(mac: neighbor.mac)
            let device = NetworkDevice(
                name: (neighbor.hostname?.isEmpty == false ? neighbor.hostname : nil) ?? neighbor.ip,
                hostname: neighbor.hostname,
                ipAddress: neighbor.ip,
                macAddress: neighbor.mac,
                vendor: finalVendor,
                role: .workstation,
                status: .online,
                tags: ["discovered", neighbor.source.rawValue]
            )
            do {
                try deviceManager.saveDevice(device)
                count += 1
            } catch {}
        }
        refreshManagedDevices()
        self.toastMessage = "Enrolled \(count) devices into inventory"
    }

    public func addDiscoveredNeighborToInventory(_ neighbor: DiscoveredNeighbor, role: DeviceRole, name: String) {
        let finalVendor = neighbor.vendor != .generic ? neighbor.vendor : OUIResolver.inferVendor(mac: neighbor.mac)
        let device = NetworkDevice(
            name: name.isEmpty ? (neighbor.hostname ?? neighbor.ip) : name,
            hostname: neighbor.hostname,
            ipAddress: neighbor.ip,
            macAddress: neighbor.mac,
            vendor: finalVendor,
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
        var devToSave = device
        if (devToSave.macAddress == nil || devToSave.macAddress?.isEmpty == true || devToSave.vendor == .generic) && !devToSave.managementIP.isEmpty {
            if let resolved = LocalDiscoveryEngine.resolveLocalHost(ip: devToSave.managementIP) {
                if devToSave.macAddress == nil || devToSave.macAddress?.isEmpty == true {
                    devToSave.macAddress = resolved.mac
                }
                if devToSave.vendor == .generic {
                    devToSave.vendor = resolved.vendor
                }
            }
        }
        do {
            try deviceManager.saveDevice(devToSave)
            refreshManagedDevices()
            self.toastMessage = "Saved device \(devToSave.name)"
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

    public func updateManagedDevice(_ device: NetworkDevice) {
        do {
            try deviceManager.updateDevice(device)
            refreshManagedDevices()
            self.toastMessage = "Updated device: \(device.name)"
        } catch {
            self.toastMessage = "Failed to update device: \(error.localizedDescription)"
        }
    }

    public func addDeviceToTimeline(device: NetworkDevice) {
        let config = MonitorTargetConfig(
            target: device.managementIP,
            name: "\(device.displayName) (\(device.role.rawValue))",
            intervalSeconds: 2.5,
            latencyThresholdMs: 60.0,
            packetLossThresholdPct: 5.0,
            isEnabled: true,
            probeProtocol: .icmp
        )
        do {
            try timeSeriesRepository.insertOrUpdateTarget(config: config)
            Task {
                await monitorService.addConfig(config)
            }
            self.toastMessage = "Added \(device.displayName) to Timeline & SLA Monitor"
        } catch {
            self.toastMessage = "Failed to add to monitor: \(error.localizedDescription)"
        }
    }

    public func jumpToSNMPStudio(device: NetworkDevice) {
        self.activeSNMPTarget = device.managementIP
        if let snmp = device.snmpConfig {
            self.activeSNMPCommunity = snmp.community
            self.activeSNMPPort = "\(snmp.port)"
            self.activeSNMPVersion = snmp.version
        }
        self.selectedWorkspace = .snmp
        self.toastMessage = "Opened SNMP Studio for \(device.displayName)"
    }

    public func exportFleetToCSV() -> String {
        var csv = "ID,Name,Hostname,Management IP,MAC Address,Vendor,Role,Status,Site,Tags,SNMP,Last Seen\n"
        for d in managedDevices {
            let idStr = d.id.uuidString
            let name = "\"\(d.displayName.replacingOccurrences(of: "\"", with: "\"\""))\""
            let host = "\"\(d.hostname.replacingOccurrences(of: "\"", with: "\"\""))\""
            let ip = d.managementIP
            let mac = d.macAddress ?? "N/A"
            let vendor = d.vendor.rawValue
            let role = d.role.rawValue
            let status = d.status.rawValue
            let site = "\"\(d.site?.replacingOccurrences(of: "\"", with: "\"\"") ?? "")\""
            let tags = "\"\(d.tags.joined(separator: "; "))\""
            let snmp = d.snmpConfig != nil ? "\(d.snmpConfig!.version):\(d.snmpConfig!.port)" : "None"
            let lastSeen = d.lastSeen?.ISO8601Format() ?? "Never"
            csv += "\(idStr),\(name),\(host),\(ip),\(mac),\(vendor),\(role),\(status),\(site),\(tags),\(snmp),\(lastSeen)\n"
        }
        return csv
    }

    public func exportFleetToJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(managedDevices),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }

    public func exportDiscoveredToCSV() -> String {
        var csv = "IP Address,MAC Address,Resolved Vendor,Interface,Source,Hostname,Latency (ms),Discovered Services,Last Seen\n"
        for n in discoveredNeighbors {
            let ip = n.ipAddress
            let mac = n.macAddress
            let vendor = "\"\(n.ouiVendor ?? "Generic")\""
            let iface = n.interface
            let source = n.discoverySource.rawValue
            let host = "\"\(n.hostname ?? "")\""
            let latency = n.latencyMs != nil ? String(format: "%.2f", n.latencyMs!) : "N/A"
            let services = "\"\(n.discoveredServices.joined(separator: "; "))\""
            let lastSeen = n.lastSeen.ISO8601Format()
            csv += "\(ip),\(mac),\(vendor),\(iface),\(source),\(host),\(latency),\(services),\(lastSeen)\n"
        }
        return csv
    }

    public func exportDiscoveredToJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(discoveredNeighbors),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }

    // MARK: - Multi-Selection & Bulk Actions

    public func toggleDeviceSelection(id: UUID) {
        if selectedDeviceIds.contains(id) {
            selectedDeviceIds.remove(id)
        } else {
            selectedDeviceIds.insert(id)
        }
    }

    public func selectAllDevices() {
        selectedDeviceIds = Set(managedDevices.map(\.id))
    }

    public func clearDeviceSelection() {
        selectedDeviceIds.removeAll()
    }

    public func bulkDeleteSelectedDevices() {
        guard !selectedDeviceIds.isEmpty else { return }
        let count = selectedDeviceIds.count
        do {
            try deviceManager.bulkDeleteDevices(ids: Array(selectedDeviceIds))
            selectedDeviceIds.removeAll()
            refreshManagedDevices()
            self.toastMessage = "Deleted \(count) devices from fleet"
        } catch {
            self.toastMessage = "Failed to bulk delete devices: \(error.localizedDescription)"
        }
    }

    public func bulkAddTagToSelected(tag: String) {
        guard !selectedDeviceIds.isEmpty else { return }
        do {
            try deviceManager.bulkAddTags(ids: Array(selectedDeviceIds), tags: [tag])
            refreshManagedDevices()
            self.toastMessage = "Added tag #\(tag) to \(selectedDeviceIds.count) devices"
        } catch {
            self.toastMessage = "Failed to add tag: \(error.localizedDescription)"
        }
    }

    public func bulkSetSiteForSelected(site: String) {
        guard !selectedDeviceIds.isEmpty else { return }
        do {
            try deviceManager.bulkAssignSite(ids: Array(selectedDeviceIds), site: site)
            refreshManagedDevices()
            self.toastMessage = "Assigned site '\(site)' to \(selectedDeviceIds.count) devices"
        } catch {
            self.toastMessage = "Failed to assign site: \(error.localizedDescription)"
        }
    }

    // MARK: - Device File Import

    public func importDevices(from url: URL) async -> DeviceImportResult {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isScoped { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let data = try Data(contentsOf: url)
            let isCSV = url.pathExtension.lowercased() == "csv"
            let result: DeviceImportResult
            if isCSV {
                guard let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
                    return DeviceImportResult(totalProcessed: 0, addedCount: 0, updatedCount: 0, errors: ["Cannot decode CSV text as UTF-8/ASCII."])
                }
                result = try deviceManager.importDevicesFromCSV(content: content)
            } else {
                result = try deviceManager.importDevicesFromJSON(data: data)
            }
            refreshManagedDevices()
            self.toastMessage = "Import complete: \(result.addedCount) added, \(result.updatedCount) updated"
            return result
        } catch {
            return DeviceImportResult(totalProcessed: 0, addedCount: 0, updatedCount: 0, errors: [error.localizedDescription])
        }
    }

    // MARK: - Port Diagnostics Deep-Linking

    public func jumpToPortDiagnostics(host: String) {
        self.portDiagnosticsTarget = host
        self.selectedToolboxTool = .ports
        self.selectedWorkspace = .toolbox
        self.toastMessage = "Opened Port Reachability Prober for \(host)"
    }

    // MARK: - Canvas Coordinate Persistence

    public func saveCanvasNodePosition(preset: String, nodeId: String, position: CGPoint) {
        try? deviceManager.saveNodePosition(preset: preset, nodeId: nodeId, position: position)
    }

    public func loadCanvasNodePositions(preset: String) -> [String: CGPoint] {
        (try? deviceManager.loadNodePositions(preset: preset)) ?? [:]
    }

    public func resetCanvasLayout(preset: String) {
        try? deviceManager.clearNodePositions(preset: preset)
    }

    // MARK: - Fleet Baseline Drift Daemon

    public func runFleetBaselineAuditNow() async {
        guard !isFleetBaselineAuditing else { return }
        isFleetBaselineAuditing = true
        fleetBaselineAuditProgress = 0.0
        defer { isFleetBaselineAuditing = false }

        var baselinedDevices: [(NetworkDevice, DeviceBaseline)] = []
        for dev in managedDevices {
            if let base = try? deviceManager.getLatestBaseline(forDeviceId: dev.id) {
                baselinedDevices.append((dev, base))
            }
        }

        guard !baselinedDevices.isEmpty else {
            self.fleetDriftCompliancePct = 100.0
            self.driftDegradedDevices = [:]
            self.toastMessage = "No devices have recorded SLA baselines yet."
            return
        }

        var degraded: [UUID: BaselineComparisonResult] = [:]
        var scores: [Double] = []

        for (idx, (dev, base)) in baselinedDevices.enumerated() {
            let sample = await deviceAuditor.probeLiveBaseline(
                ipAddress: dev.managementIP,
                customPorts: base.openPorts.isEmpty ? DeviceAuditor.standardAuditPorts : base.openPorts,
                pingCount: 3,
                snmpConfig: dev.snmpConfig
            )
            let comp = deviceManager.compareWithBaseline(
                currentLatency: sample.avgLatencyMs,
                currentLoss: sample.packetLossPct,
                currentOpenPorts: sample.openPorts,
                baseline: base
            )
            scores.append(Double(comp.overallHealthScore))
            if comp.overallHealthScore < 75 {
                degraded[dev.id] = comp
            }
            fleetBaselineAuditProgress = Double(idx + 1) / Double(baselinedDevices.count)
        }

        let avgScore = scores.isEmpty ? 100.0 : (scores.reduce(0, +) / Double(scores.count))
        self.fleetDriftCompliancePct = avgScore
        self.driftDegradedDevices = degraded

        if !degraded.isEmpty {
            self.toastMessage = "⚠️ Baseline Drift Alert: \(degraded.count) devices degraded!"
        } else {
            self.toastMessage = "Fleet Baseline Audit Complete: 100% compliant"
        }
    }

    // MARK: - Environments & Command Library Management

    public func refreshEnvironments() {
        self.siteEnvironments = (try? environmentRepository.fetchAll()) ?? []
        self.activeSiteEnvironment = (try? environmentRepository.fetchActive())
    }

    public func activateEnvironment(id: String) {
        try? environmentRepository.setActive(id: id)
        refreshEnvironments()
        if let active = activeSiteEnvironment {
            self.targetInput = active.gatewayIP
            self.toastMessage = "Switched active scope to \(active.name)"
        }
    }

    public func saveEnvironment(_ record: EnvironmentRecord) {
        try? environmentRepository.insert(record)
        refreshEnvironments()
    }

    public func deleteEnvironment(id: String) {
        try? environmentRepository.delete(id: id)
        refreshEnvironments()
    }

    public func refreshCustomCommands() {
        self.customCommandsList = (try? customCommandRepository.fetchAll()) ?? []
    }

    public func saveCustomCommand(_ record: CustomCommandRecord) {
        try? customCommandRepository.insert(record)
        refreshCustomCommands()
    }

    public func deleteCustomCommand(id: String) {
        try? customCommandRepository.delete(id: id)
        refreshCustomCommands()
    }

    public func toggleCommandFavorite(id: String) {
        try? customCommandRepository.toggleFavorite(id: id)
        refreshCustomCommands()
    }
}

