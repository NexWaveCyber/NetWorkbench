import Foundation
import NetworkCore
import PersistenceKit

/// Attached device configuration snapshot stored inside an investigation bundle
public struct AttachedConfigFile: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let filename: String
    public let deviceHostname: String
    public let content: String

    public init(
        id: String = UUID().uuidString,
        filename: String,
        deviceHostname: String,
        content: String
    ) {
        self.id = id
        self.filename = filename
        self.deviceHostname = deviceHostname
        self.content = content
    }
}

/// Complete exportable investigation bundle (.nwi archive) for cross-team sharing, incident handoff, and audit archiving
public struct InvestigationBundle: Codable, Sendable, Identifiable {
    public var id: String { investigation.id }
    public let version: String
    public let exportedAt: Date
    public let exportedBy: String
    public let investigation: InvestigationRecord
    public let timelineEvents: [TimelineEventRecord]
    
    // Enterprise Incident Extensions (v2.0)
    public let evidenceItems: [EvidenceItemRecord]
    public let hypotheses: [HypothesisRecord]
    public let actionItems: [ActionItemRecord]
    public let rca: InvestigationRCARecord?

    // Legacy v1.x compatibility fields
    public let diagnosticSnapshots: [DiagnosticHistoryRecord]
    public let attachedConfigFiles: [AttachedConfigFile]
    public let packetCaptureBase64: String?
    public let notes: String

    public init(
        version: String = "2.0",
        exportedAt: Date = Date(),
        exportedBy: String = NSUserName(),
        investigation: InvestigationRecord,
        timelineEvents: [TimelineEventRecord] = [],
        evidenceItems: [EvidenceItemRecord] = [],
        hypotheses: [HypothesisRecord] = [],
        actionItems: [ActionItemRecord] = [],
        rca: InvestigationRCARecord? = nil,
        diagnosticSnapshots: [DiagnosticHistoryRecord] = [],
        attachedConfigFiles: [AttachedConfigFile] = [],
        packetCaptureBase64: String? = nil,
        notes: String = ""
    ) {
        self.version = version
        self.exportedAt = exportedAt
        self.exportedBy = exportedBy
        self.investigation = investigation
        self.timelineEvents = timelineEvents
        self.evidenceItems = evidenceItems
        self.hypotheses = hypotheses
        self.actionItems = actionItems
        self.rca = rca
        self.diagnosticSnapshots = diagnosticSnapshots
        self.attachedConfigFiles = attachedConfigFiles
        self.packetCaptureBase64 = packetCaptureBase64
        self.notes = notes
    }

    // Custom Decodable to maintain backward-compatibility with v1.0/1.1 bundles
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = (try? container.decode(String.self, forKey: .version)) ?? "1.0"
        self.exportedAt = (try? container.decode(Date.self, forKey: .exportedAt)) ?? Date()
        self.exportedBy = (try? container.decode(String.self, forKey: .exportedBy)) ?? "Unknown"
        self.investigation = try container.decode(InvestigationRecord.self, forKey: .investigation)
        self.timelineEvents = (try? container.decode([TimelineEventRecord].self, forKey: .timelineEvents)) ?? []
        self.evidenceItems = (try? container.decode([EvidenceItemRecord].self, forKey: .evidenceItems)) ?? []
        self.hypotheses = (try? container.decode([HypothesisRecord].self, forKey: .hypotheses)) ?? []
        self.actionItems = (try? container.decode([ActionItemRecord].self, forKey: .actionItems)) ?? []
        self.rca = try? container.decodeIfPresent(InvestigationRCARecord.self, forKey: .rca)
        self.diagnosticSnapshots = (try? container.decode([DiagnosticHistoryRecord].self, forKey: .diagnosticSnapshots)) ?? []
        self.attachedConfigFiles = (try? container.decode([AttachedConfigFile].self, forKey: .attachedConfigFiles)) ?? []
        self.packetCaptureBase64 = try? container.decodeIfPresent(String.self, forKey: .packetCaptureBase64)
        self.notes = (try? container.decode(String.self, forKey: .notes)) ?? ""
    }
}
