import Foundation
import NetworkCore
import DiagnosticsEngine
import PersistenceKit

/// Coordinates investigations and persists chronological timeline events.
public final class InvestigationManager: Sendable {
    private let repo: InvestigationRepository
    private let historyRepo: DiagnosticHistoryRepository

    public init(database: SQLiteDatabase) {
        self.repo = InvestigationRepository(database: database)
        self.historyRepo = DiagnosticHistoryRepository(database: database)
    }

    public func createInvestigation(
        title: String,
        description: String = "",
        severity: InvestigationSeverity = .medium
    ) throws -> Investigation {
        let inv = Investigation(
            title: title,
            description: description,
            severity: severity
        )
        try repo.insert(inv.toRecord())

        let initialEvent = TimelineEventRecord(
            investigationId: inv.id,
            timestamp: Date().timeIntervalSince1970,
            title: "Investigation Created",
            detail: "Investigation opened with \(severity.rawValue) severity.",
            category: "StatusChange"
        )
        try repo.addTimelineEvent(initialEvent)
        return inv
    }

    public func listInvestigations() throws -> [Investigation] {
        let records = try repo.fetchAll()
        return records.map { Investigation(record: $0) }
    }

    public func fetchTimeline(forInvestigationId id: String) throws -> [TimelineEventRecord] {
        try repo.fetchEvents(forInvestigationId: id)
    }

    public func attachDiagnosticResult(
        _ result: DiagnosticResult,
        toInvestigationId investigationId: String
    ) throws {
        let event = TimelineEventRecord(
            investigationId: investigationId,
            timestamp: Date().timeIntervalSince1970,
            title: "Diagnosed \(result.target.displayString)",
            detail: "Status: \(result.overallStatus.rawValue) | \(result.overallSummary)",
            category: "Diagnostic"
        )
        try repo.addTimelineEvent(event)

        // Also add detailed finding events if critical/warning
        for finding in result.findings where finding.severity == .critical || finding.severity == .warning {
            let findingEvent = TimelineEventRecord(
                investigationId: investigationId,
                timestamp: Date().timeIntervalSince1970,
                title: "Anomaly: \(finding.title)",
                detail: "\(finding.classification.rawValue): \(finding.statement) (Fault Domain: \(finding.faultDomain))",
                category: "Diagnostic"
            )
            try repo.addTimelineEvent(findingEvent)
        }
    }

    public func recordHistory(result: DiagnosticResult) throws {
        let rec = DiagnosticHistoryRecord(
            target: result.target.displayString,
            targetType: result.target.targetType.rawValue,
            timestamp: result.timestamp.timeIntervalSince1970,
            dnsHealthy: result.dns?.isHealthy ?? true,
            pingLatency: result.latency?.medianMs,
            packetLoss: result.latency?.lossPercentage,
            tcpHealthy: result.tcp?.isSuccess ?? false,
            tlsHealthy: !(result.http?.certificateInfo?.isExpired ?? false),
            httpStatus: result.http?.statusCode,
            summary: result.overallSummary,
            rawJson: "{}"
        )
        try historyRepo.record(rec)
    }

    public func fetchRecentHistory(limit: Int = 20) throws -> [DiagnosticHistoryRecord] {
        try historyRepo.fetchRecent(limit: limit)
    }
}
