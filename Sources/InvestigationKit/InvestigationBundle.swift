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

/// Complete exportable investigation bundle (.nwi archive) for cross-team sharing and audit archiving
public struct InvestigationBundle: Codable, Sendable, Identifiable {
    public var id: String { investigation.id }
    public let version: String
    public let exportedAt: Date
    public let exportedBy: String
    public let investigation: InvestigationRecord
    public let timelineEvents: [TimelineEventRecord]
    public let diagnosticSnapshots: [DiagnosticHistoryRecord]
    public let attachedConfigFiles: [AttachedConfigFile]
    public let packetCaptureBase64: String?
    public let notes: String

    public init(
        version: String = "1.0",
        exportedAt: Date = Date(),
        exportedBy: String = NSUserName(),
        investigation: InvestigationRecord,
        timelineEvents: [TimelineEventRecord] = [],
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
        self.diagnosticSnapshots = diagnosticSnapshots
        self.attachedConfigFiles = attachedConfigFiles
        self.packetCaptureBase64 = packetCaptureBase64
        self.notes = notes
    }
}
