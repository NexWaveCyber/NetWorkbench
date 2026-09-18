import Foundation
import NetworkCore
import DiagnosticsEngine
import PersistenceKit

/// Coordinates enterprise investigations, forensic evidence, hypothesis testing, 5-Whys RCA, and timeline events.
public final class InvestigationManager: Sendable {
    private let repo: InvestigationRepository
    private let evidenceRepo: EvidenceRepository
    private let hypothesisRepo: HypothesisRepository
    private let actionItemRepo: ActionItemRepository
    private let rcaRepo: RCARepository
    private let historyRepo: DiagnosticHistoryRepository

    public init(database: SQLiteDatabase) {
        self.repo = InvestigationRepository(database: database)
        self.evidenceRepo = EvidenceRepository(database: database)
        self.hypothesisRepo = HypothesisRepository(database: database)
        self.actionItemRepo = ActionItemRepository(database: database)
        self.rcaRepo = RCARepository(database: database)
        self.historyRepo = DiagnosticHistoryRepository(database: database)
    }

    // MARK: - Investigation Lifecycle

    public func createInvestigation(
        title: String,
        description: String = "",
        severity: InvestigationSeverity = .medium,
        commander: String? = nil,
        affectedServices: [String] = [],
        affectedDevices: [String] = [],
        blastRadius: String? = nil
    ) throws -> Investigation {
        let inv = Investigation(
            title: title,
            description: description,
            severity: severity,
            commander: commander,
            affectedServices: affectedServices,
            affectedDevices: affectedDevices,
            blastRadius: blastRadius,
            detectedAt: Date()
        )
        try repo.insert(inv.toRecord())

        let initialEvent = TimelineEventRecord(
            investigationId: inv.id,
            timestamp: Date().timeIntervalSince1970,
            title: "Investigation Opened",
            detail: "Incident declared with \(severity.priorityPill) severity. Lead: \(commander ?? "Unassigned").",
            category: "StatusChange"
        )
        try repo.addTimelineEvent(initialEvent)
        return inv
    }

    public func listInvestigations() throws -> [Investigation] {
        let records = try repo.fetchAll()
        return records.map { Investigation(record: $0) }
    }

    public func updateInvestigation(_ inv: Investigation) throws {
        try repo.insert(inv.toRecord())
    }

    public func updateInvestigationStatus(
        id: String,
        status: InvestigationStatus,
        resolution: String? = nil,
        rootCauseSummary: String? = nil
    ) throws {
        let now = Date().timeIntervalSince1970
        let resolvedAt = (status == .resolved) ? now : nil
        let mitigatedAt = (status == .mitigating || status == .monitoring || status == .resolved) ? now : nil

        try repo.updateStatus(
            id: id,
            status: status.rawValue,
            resolution: resolution,
            resolvedAt: resolvedAt,
            mitigatedAt: mitigatedAt,
            rootCauseSummary: rootCauseSummary
        )

        let statusEvent = TimelineEventRecord(
            investigationId: id,
            timestamp: now,
            title: "Status Changed: \(status.rawValue)",
            detail: resolution ?? "Investigation transitioned to \(status.rawValue).",
            category: "StatusChange"
        )
        try repo.addTimelineEvent(statusEvent)
    }

    public func deleteInvestigation(id: String) throws {
        try repo.delete(id: id)
    }

    // MARK: - Chronological Timeline

    public func fetchTimeline(forInvestigationId id: String) throws -> [TimelineEventRecord] {
        try repo.fetchEvents(forInvestigationId: id)
    }

    public func addTimelineEvent(
        investigationId: String,
        title: String,
        detail: String = "",
        category: String = "Manual",
        timestamp: Date = Date()
    ) throws {
        let event = TimelineEventRecord(
            investigationId: investigationId,
            timestamp: timestamp.timeIntervalSince1970,
            title: title,
            detail: detail,
            category: category
        )
        try repo.addTimelineEvent(event)
    }

    public func deleteTimelineEvent(id: String) throws {
        try repo.deleteTimelineEvent(id: id)
    }

    // MARK: - Forensic Evidence Vault

    public func attachEvidence(
        investigationId: String,
        title: String,
        filename: String,
        type: EvidenceType,
        content: String,
        sourceWorkbench: String = "Investigations",
        notes: String = ""
    ) throws -> EvidenceItem {
        let item = EvidenceItem.fromString(
            text: content,
            investigationId: investigationId,
            title: title,
            filename: filename,
            type: type,
            sourceWorkbench: sourceWorkbench,
            notes: notes
        )
        try evidenceRepo.insert(item.toRecord())

        let timelineEvent = TimelineEventRecord(
            investigationId: investigationId,
            timestamp: Date().timeIntervalSince1970,
            title: "Forensic Evidence Attached: \(filename)",
            detail: "Type: \(type.displayName) | SHA-256: \(item.sha256.prefix(12))...",
            category: "Diagnostic"
        )
        try repo.addTimelineEvent(timelineEvent)
        return item
    }

    public func attachEvidenceData(
        investigationId: String,
        title: String,
        filename: String,
        type: EvidenceType,
        data: Data,
        sourceWorkbench: String = "Investigations",
        notes: String = ""
    ) throws -> EvidenceItem {
        let item = EvidenceItem.fromData(
            data: data,
            investigationId: investigationId,
            title: title,
            filename: filename,
            type: type,
            sourceWorkbench: sourceWorkbench,
            notes: notes
        )
        try evidenceRepo.insert(item.toRecord())

        let timelineEvent = TimelineEventRecord(
            investigationId: investigationId,
            timestamp: Date().timeIntervalSince1970,
            title: "Artifact Logged: \(filename)",
            detail: "Size: \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)) | SHA-256: \(item.sha256.prefix(12))...",
            category: "Diagnostic"
        )
        try repo.addTimelineEvent(timelineEvent)
        return item
    }

    public func listEvidence(forInvestigationId investigationId: String) throws -> [EvidenceItem] {
        let records = try evidenceRepo.fetch(forInvestigationId: investigationId)
        return records.map { EvidenceItem(record: $0) }
    }

    public func deleteEvidence(id: String) throws {
        try evidenceRepo.delete(id: id)
    }

    // MARK: - Hypotheses Matrix

    public func addHypothesis(
        investigationId: String,
        statement: String,
        proposedTest: String = ""
    ) throws -> InvestigationHypothesis {
        let hyp = InvestigationHypothesis(
            investigationId: investigationId,
            statement: statement,
            proposedTest: proposedTest
        )
        try hypothesisRepo.insert(hyp.toRecord())

        let timelineEvent = TimelineEventRecord(
            investigationId: investigationId,
            timestamp: Date().timeIntervalSince1970,
            title: "Hypothesis Proposed",
            detail: statement,
            category: "Manual"
        )
        try repo.addTimelineEvent(timelineEvent)
        return hyp
    }

    public func updateHypothesisStatus(
        id: String,
        investigationId: String,
        status: HypothesisStatus,
        findings: String
    ) throws {
        let existing = (try hypothesisRepo.fetch(forInvestigationId: investigationId)).first { $0.id == id }
        if var rec = existing {
            rec.status = status.rawValue
            rec.findings = findings
            rec.updatedAt = Date().timeIntervalSince1970
            try hypothesisRepo.insert(rec)

            let event = TimelineEventRecord(
                investigationId: investigationId,
                timestamp: Date().timeIntervalSince1970,
                title: "Hypothesis \(status.rawValue)",
                detail: "\(rec.statement) — Findings: \(findings)",
                category: status == .confirmed ? "Diagnostic" : "Manual"
            )
            try repo.addTimelineEvent(event)
        }
    }

    public func listHypotheses(forInvestigationId investigationId: String) throws -> [InvestigationHypothesis] {
        let records = try hypothesisRepo.fetch(forInvestigationId: investigationId)
        return records.map { InvestigationHypothesis(record: $0) }
    }

    public func deleteHypothesis(id: String) throws {
        try hypothesisRepo.delete(id: id)
    }

    // MARK: - Action Items & Mitigation Runbook

    public func addActionItem(
        investigationId: String,
        title: String,
        phase: ActionPhase = .mitigation,
        assignee: String? = nil,
        notes: String = ""
    ) throws -> InvestigationActionItem {
        let act = InvestigationActionItem(
            investigationId: investigationId,
            title: title,
            phase: phase,
            assignee: assignee,
            notes: notes
        )
        try actionItemRepo.insert(act.toRecord())
        return act
    }

    public func toggleActionItem(id: String, investigationId: String, isCompleted: Bool) throws {
        try actionItemRepo.toggleCompleted(id: id, isCompleted: isCompleted)
        let items = try actionItemRepo.fetch(forInvestigationId: investigationId)
        if let item = items.first(where: { $0.id == id }) {
            let statusText = isCompleted ? "Completed" : "Re-opened"
            let event = TimelineEventRecord(
                investigationId: investigationId,
                timestamp: Date().timeIntervalSince1970,
                title: "Action Item \(statusText): \(item.title)",
                detail: "Phase: \(item.phase) | Assignee: \(item.assignee ?? "None")",
                category: "Action"
            )
            try repo.addTimelineEvent(event)
        }
    }

    public func listActionItems(forInvestigationId investigationId: String) throws -> [InvestigationActionItem] {
        let records = try actionItemRepo.fetch(forInvestigationId: investigationId)
        return records.map { InvestigationActionItem(record: $0) }
    }

    public func deleteActionItem(id: String) throws {
        try actionItemRepo.delete(id: id)
    }

    // MARK: - 5-Whys Root Cause Analysis

    public func saveRCA(_ rca: InvestigationRCA) throws {
        try rcaRepo.insertOrUpdate(rca.toRecord())
    }

    public func fetchRCA(forInvestigationId investigationId: String) throws -> InvestigationRCA? {
        if let record = try rcaRepo.fetch(forInvestigationId: investigationId) {
            return InvestigationRCA(record: record)
        }
        return nil
    }

    // MARK: - Diagnostic Result Cross-Workbench Bridge

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

        // Also create evidence probe record
        let probeSummary = "Target: \(result.target.displayString)\nStatus: \(result.overallStatus.rawValue)\nDNS: \(result.dns?.isHealthy == true ? "OK" : "Failed")\nLatency: \(result.latency?.medianMs != nil ? "\(result.latency!.medianMs)ms" : "N/A")\nLoss: \(result.latency?.lossPercentage != nil ? "\(result.latency!.lossPercentage)%" : "N/A")\nTCP: \(result.tcp?.isSuccess == true ? "OK" : "Failed")\nSummary: \(result.overallSummary)"
        _ = try attachEvidence(
            investigationId: investigationId,
            title: "Diagnostic Probe (\(result.target.displayString))",
            filename: "probe_\(result.target.displayString.replacingOccurrences(of: "[:/.]", with: "_", options: .regularExpression)).txt",
            type: .diagnosticProbe,
            content: probeSummary,
            sourceWorkbench: "Diagnostics Workspace",
            notes: "Recorded from active diagnostic runner"
        )
    }

    public func recordHistory(result: DiagnosticResult) throws {
        var jsonDict: [String: Any] = [
            "target": result.target.displayString,
            "targetType": result.target.targetType.rawValue,
            "timestamp": result.timestamp.timeIntervalSince1970,
            "executionDurationMs": result.executionDurationMs,
            "overallStatus": result.overallStatus.rawValue,
            "overallSummary": result.overallSummary
        ]
        if let dns = result.dns {
            jsonDict["dns"] = [
                "isHealthy": dns.isHealthy,
                "latencyMs": dns.queryTimeMs,
                "addresses": dns.ipv4Addresses.map { $0.description } + dns.ipv6Addresses.map { $0.description }
            ]
        }
        if let lat = result.latency {
            jsonDict["latency"] = [
                "medianMs": lat.medianMs,
                "minMs": lat.minMs,
                "maxMs": lat.maxMs,
                "lossPercentage": lat.lossPercentage,
                "jitterMs": lat.jitterMs
            ]
        }
        if let tcp = result.tcp {
            var tcpDict: [String: Any] = [
                "isSuccess": tcp.isSuccess
            ]
            if let ms = tcp.latencyMs { tcpDict["latencyMs"] = ms }
            jsonDict["tcp"] = tcpDict
        }
        if let http = result.http {
            var httpDict: [String: Any] = [
                "statusCode": http.statusCode
            ]
            if let ttfb = http.ttfbMs { httpDict["ttfbMs"] = ttfb }
            if let v = http.certificateInfo?.protocolVersion { httpDict["tlsVersion"] = v }
            if let c = http.certificateInfo?.cipherSuite { httpDict["cipherSuite"] = c }
            jsonDict["http"] = httpDict
        }
        let rawJson = (try? String(data: JSONSerialization.data(withJSONObject: jsonDict, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)) ?? "{}"

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
            rawJson: rawJson
        )
        try historyRepo.record(rec)
    }

    public func fetchRecentHistory(limit: Int = 100) throws -> [DiagnosticHistoryRecord] {
        try historyRepo.fetchRecent(limit: limit)
    }

    public func deleteHistory(id: String) throws {
        try historyRepo.delete(id: id)
    }

    public func purgeHistory(olderThanDays days: Int) throws {
        try historyRepo.deleteOlderThan(days: days)
    }

    public func clearAllHistory() throws {
        try historyRepo.clearAll()
    }

    public func seedDemoHistoryIfEmpty() throws {
        try historyRepo.seedDemoHistoryIfEmpty()
    }


    // MARK: - .nwi Collaboration Bundle Export & Import (v2.0)

    public func exportInvestigationBundle(
        id: String,
        to url: URL,
        notes: String = "",
        configFiles: [AttachedConfigFile] = [],
        pcapData: Data? = nil
    ) throws {
        guard let invRecord = try repo.fetchAll().first(where: { $0.id == id }) else {
            throw NSError(domain: "InvestigationManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "Investigation not found"])
        }
        let timeline = try repo.fetchEvents(forInvestigationId: id)
        let evidence = try evidenceRepo.fetch(forInvestigationId: id)
        let hypotheses = try hypothesisRepo.fetch(forInvestigationId: id)
        let actions = try actionItemRepo.fetch(forInvestigationId: id)
        let rca = try rcaRepo.fetch(forInvestigationId: id)
        let history = (try? historyRepo.fetchRecent(limit: 50)) ?? []

        try InvestigationBundleManager.exportBundleToFile(
            investigation: invRecord,
            timelineEvents: timeline,
            evidenceItems: evidence,
            hypotheses: hypotheses,
            actionItems: actions,
            rca: rca,
            diagnostics: history,
            configFiles: configFiles,
            pcapData: pcapData,
            notes: notes,
            to: url
        )
    }

    public func importInvestigationBundle(from url: URL) throws -> Investigation {
        let bundle = try InvestigationBundleManager.loadBundle(from: url)
        try InvestigationBundleManager.importIntoDatabase(
            bundle: bundle,
            investigationRepo: repo,
            evidenceRepo: evidenceRepo,
            hypothesisRepo: hypothesisRepo,
            actionItemRepo: actionItemRepo,
            rcaRepo: rcaRepo,
            historyRepo: historyRepo
        )
        return Investigation(record: bundle.investigation)
    }

    // MARK: - Post-Mortem Report Generation

    public func generatePostMortemMarkdown(id: String) throws -> String {
        guard let invRecord = try repo.fetchAll().first(where: { $0.id == id }) else {
            throw NSError(domain: "InvestigationManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "Investigation not found"])
        }
        let inv = Investigation(record: invRecord)
        let timeline = try repo.fetchEvents(forInvestigationId: id)
        let evidence = try listEvidence(forInvestigationId: id)
        let hypotheses = try listHypotheses(forInvestigationId: id)
        let actionItems = try listActionItems(forInvestigationId: id)
        let rca = try fetchRCA(forInvestigationId: id)

        return IncidentPostMortemGenerator.generateMarkdown(
            investigation: inv,
            timeline: timeline,
            evidence: evidence,
            hypotheses: hypotheses,
            actionItems: actionItems,
            rca: rca
        )
    }

    public func generatePostMortemHTML(id: String) throws -> String {
        guard let invRecord = try repo.fetchAll().first(where: { $0.id == id }) else {
            throw NSError(domain: "InvestigationManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "Investigation not found"])
        }
        let inv = Investigation(record: invRecord)
        let timeline = try repo.fetchEvents(forInvestigationId: id)
        let evidence = try listEvidence(forInvestigationId: id)
        let hypotheses = try listHypotheses(forInvestigationId: id)
        let actionItems = try listActionItems(forInvestigationId: id)
        let rca = try fetchRCA(forInvestigationId: id)

        return IncidentPostMortemGenerator.generateHTML(
            investigation: inv,
            timeline: timeline,
            evidence: evidence,
            hypotheses: hypotheses,
            actionItems: actionItems,
            rca: rca
        )
    }
}
