import SwiftUI
import NetworkCore
import DiagnosticsEngine
import InvestigationKit
import PersistenceKit
import CommandLibrary

public enum WorkspaceItem: String, CaseIterable, Identifiable, Sendable {
    case home = "Home / Dashboard"
    case diagnose = "Diagnose"
    case toolbox = "Toolbox"
    case devices = "Devices"
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
        case .devices: return "server.rack"
        case .snmp: return "chart.bar.xaxis"
        case .config: return "doc.text.magnifyingglass"
        case .packet: return "waveform.path.ecg"
        case .investigations: return "briefcase.fill"
        case .environments: return "network"
        case .commandLibrary: return "terminal.fill"
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

    // Alerts and feedback
    public var toastMessage: String? = nil

    public init() {
        do {
            let db = try SQLiteDatabase()
            self.database = db
            self.investigationManager = InvestigationManager(database: db)
            self.investigations = (try? investigationManager.listInvestigations()) ?? []
            self.recentHistory = (try? investigationManager.fetchRecentHistory(limit: 20)) ?? []
        } catch {
            fatalError("Failed to initialize SQLite persistence: \(error)")
        }

        self.updateTargetClassification(self.targetInput)
    }

    public func updateTargetClassification(_ text: String) {
        self.targetInput = text
        self.classifiedTarget = TargetClassifier.classify(text)
    }

    @MainActor
    public func runDiagnosis(target: NetworkTarget) async {
        self.isDiagnosing = true
        self.currentProgress = PipelineProgress(stage: .resolvingDNS, percentage: 0.05, message: "Initializing diagnostic pipeline...")

        let pipeline = DiagnosticPipeline()
        let result = await pipeline.execute(target: target) { progress in
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
}
