import Foundation
import CryptoKit
import NetworkCore
import PersistenceKit

// MARK: - Evidence Models

public enum EvidenceType: String, Sendable, CaseIterable, Identifiable, Codable {
    case pcap = "pcap"
    case cliOutput = "cliOutput"
    case configDiff = "configDiff"
    case diagnosticProbe = "diagnosticProbe"
    case syslog = "syslog"
    case screenshot = "screenshot"
    case genericFile = "genericFile"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .pcap: return "PCAP Capture"
        case .cliOutput: return "CLI Output"
        case .configDiff: return "Config Diff"
        case .diagnosticProbe: return "Diagnostic Probe"
        case .syslog: return "Syslog Excerpt"
        case .screenshot: return "Screenshot / Media"
        case .genericFile: return "Log / Data File"
        }
    }

    public var iconName: String {
        switch self {
        case .pcap: return "waveform.path.ecg"
        case .cliOutput: return "terminal.fill"
        case .configDiff: return "arrow.left.arrow.right"
        case .diagnosticProbe: return "stethoscope"
        case .syslog: return "doc.text.magnifyingglass"
        case .screenshot: return "photo.fill"
        case .genericFile: return "doc.fill"
        }
    }
}

public struct EvidenceItem: Sendable, Identifiable, Hashable {
    public let id: String
    public let investigationId: String
    public var title: String
    public var evidenceType: EvidenceType
    public var filename: String
    public var sha256: String
    public var byteSize: Int
    public var content: String
    public var sourceWorkbench: String
    public var createdAt: Date
    public var notes: String

    public init(
        id: String = UUID().uuidString,
        investigationId: String,
        title: String,
        evidenceType: EvidenceType,
        filename: String,
        sha256: String,
        byteSize: Int,
        content: String,
        sourceWorkbench: String = "Investigations",
        createdAt: Date = Date(),
        notes: String = ""
    ) {
        self.id = id
        self.investigationId = investigationId
        self.title = title
        self.evidenceType = evidenceType
        self.filename = filename
        self.sha256 = sha256
        self.byteSize = byteSize
        self.content = content
        self.sourceWorkbench = sourceWorkbench
        self.createdAt = createdAt
        self.notes = notes
    }

    /// Convenience initializer from raw Data, automatically computing SHA-256
    public static func fromData(
        data: Data,
        investigationId: String,
        title: String,
        filename: String,
        type: EvidenceType,
        sourceWorkbench: String = "Investigations",
        notes: String = ""
    ) -> EvidenceItem {
        let hash = SHA256.hash(data: data)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
        let contentString: String
        if type == .pcap || type == .screenshot {
            contentString = data.base64EncodedString()
        } else {
            contentString = String(decoding: data, as: UTF8.self)
        }

        return EvidenceItem(
            investigationId: investigationId,
            title: title,
            evidenceType: type,
            filename: filename,
            sha256: hashString,
            byteSize: data.count,
            content: contentString,
            sourceWorkbench: sourceWorkbench,
            createdAt: Date(),
            notes: notes
        )
    }

    public static func fromString(
        text: String,
        investigationId: String,
        title: String,
        filename: String,
        type: EvidenceType,
        sourceWorkbench: String = "Investigations",
        notes: String = ""
    ) -> EvidenceItem {
        let data = Data(text.utf8)
        return fromData(
            data: data,
            investigationId: investigationId,
            title: title,
            filename: filename,
            type: type,
            sourceWorkbench: sourceWorkbench,
            notes: notes
        )
    }

    public init(record: EvidenceItemRecord) {
        self.id = record.id
        self.investigationId = record.investigationId
        self.title = record.title
        self.evidenceType = EvidenceType(rawValue: record.evidenceType) ?? .genericFile
        self.filename = record.filename
        self.sha256 = record.sha256
        self.byteSize = record.byteSize
        self.content = record.content
        self.sourceWorkbench = record.sourceWorkbench
        self.createdAt = Date(timeIntervalSince1970: record.createdAt)
        self.notes = record.notes
    }

    public func toRecord() -> EvidenceItemRecord {
        EvidenceItemRecord(
            id: id,
            investigationId: investigationId,
            title: title,
            evidenceType: evidenceType.rawValue,
            filename: filename,
            sha256: sha256,
            byteSize: byteSize,
            content: content,
            sourceWorkbench: sourceWorkbench,
            createdAt: createdAt.timeIntervalSince1970,
            notes: notes
        )
    }
}

// MARK: - Hypothesis Models

public enum HypothesisStatus: String, Sendable, CaseIterable, Identifiable, Codable {
    case untested = "Untested"
    case testing = "Testing"
    case confirmed = "Confirmed"
    case refuted = "Refuted"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .untested: return "questionmark.circle"
        case .testing: return "hourglass.circle"
        case .confirmed: return "checkmark.circle.fill"
        case .refuted: return "xmark.circle.fill"
        }
    }
}

public struct InvestigationHypothesis: Sendable, Identifiable, Hashable {
    public let id: String
    public let investigationId: String
    public var statement: String
    public var status: HypothesisStatus
    public var proposedTest: String
    public var findings: String
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        investigationId: String,
        statement: String,
        status: HypothesisStatus = .untested,
        proposedTest: String = "",
        findings: String = "",
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.investigationId = investigationId
        self.statement = statement
        self.status = status
        self.proposedTest = proposedTest
        self.findings = findings
        self.updatedAt = updatedAt
    }

    public init(record: HypothesisRecord) {
        self.id = record.id
        self.investigationId = record.investigationId
        self.statement = record.statement
        self.status = HypothesisStatus(rawValue: record.status) ?? .untested
        self.proposedTest = record.proposedTest
        self.findings = record.findings
        self.updatedAt = Date(timeIntervalSince1970: record.updatedAt)
    }

    public func toRecord() -> HypothesisRecord {
        HypothesisRecord(
            id: id,
            investigationId: investigationId,
            statement: statement,
            status: status.rawValue,
            proposedTest: proposedTest,
            findings: findings,
            updatedAt: updatedAt.timeIntervalSince1970
        )
    }
}

// MARK: - Action Items

public enum ActionPhase: String, Sendable, CaseIterable, Identifiable, Codable {
    case mitigation = "Mitigation"
    case verification = "Verification"
    case postMortem = "PostMortem"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .mitigation: return "Immediate Mitigation"
        case .verification: return "Service Verification"
        case .postMortem: return "Post-Incident Hardening"
        }
    }
}

public struct InvestigationActionItem: Sendable, Identifiable, Hashable {
    public let id: String
    public let investigationId: String
    public var title: String
    public var phase: ActionPhase
    public var isCompleted: Bool
    public var assignee: String?
    public var completedAt: Date?
    public var notes: String

    public init(
        id: String = UUID().uuidString,
        investigationId: String,
        title: String,
        phase: ActionPhase = .mitigation,
        isCompleted: Bool = false,
        assignee: String? = nil,
        completedAt: Date? = nil,
        notes: String = ""
    ) {
        self.id = id
        self.investigationId = investigationId
        self.title = title
        self.phase = phase
        self.isCompleted = isCompleted
        self.assignee = assignee
        self.completedAt = completedAt
        self.notes = notes
    }

    public init(record: ActionItemRecord) {
        self.id = record.id
        self.investigationId = record.investigationId
        self.title = record.title
        self.phase = ActionPhase(rawValue: record.phase) ?? .mitigation
        self.isCompleted = record.isCompleted
        self.assignee = record.assignee
        self.completedAt = record.completedAt != nil ? Date(timeIntervalSince1970: record.completedAt!) : nil
        self.notes = record.notes
    }

    public func toRecord() -> ActionItemRecord {
        ActionItemRecord(
            id: id,
            investigationId: investigationId,
            title: title,
            phase: phase.rawValue,
            isCompleted: isCompleted,
            assignee: assignee,
            completedAt: completedAt?.timeIntervalSince1970,
            notes: notes
        )
    }
}

// MARK: - Root Cause Analysis (5-Whys)

public enum RootCauseCategory: String, Sendable, CaseIterable, Identifiable, Codable {
    case hardware = "Hardware / Physical"
    case softwareBug = "Firmware / Software Bug"
    case configDrift = "Configuration Drift"
    case capacity = "Capacity / Congestion"
    case carrierISP = "Carrier / Upstream ISP"
    case cyberSecurity = "Security / Threat"
    case humanError = "Operational Error"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .hardware: return "cable.connector"
        case .softwareBug: return "ladybug.fill"
        case .configDrift: return "arrow.triangle.swap"
        case .capacity: return "gauge.with.needle.fill"
        case .carrierISP: return "globe.americas.fill"
        case .cyberSecurity: return "shield.lefthalf.filled.trianglebadge.exclamationmark"
        case .humanError: return "person.crop.circle.badge.exclamationmark"
        }
    }
}

public struct InvestigationRCA: Sendable, Identifiable, Hashable {
    public let id: String
    public let investigationId: String
    public var problemStatement: String
    public var why1: String
    public var why2: String
    public var why3: String
    public var why4: String
    public var why5: String
    public var rootCause: String
    public var preventativeStrategy: String

    public init(
        id: String = UUID().uuidString,
        investigationId: String,
        problemStatement: String = "",
        why1: String = "",
        why2: String = "",
        why3: String = "",
        why4: String = "",
        why5: String = "",
        rootCause: String = "",
        preventativeStrategy: String = ""
    ) {
        self.id = id
        self.investigationId = investigationId
        self.problemStatement = problemStatement
        self.why1 = why1
        self.why2 = why2
        self.why3 = why3
        self.why4 = why4
        self.why5 = why5
        self.rootCause = rootCause
        self.preventativeStrategy = preventativeStrategy
    }

    public init(record: InvestigationRCARecord) {
        self.id = record.id
        self.investigationId = record.investigationId
        self.problemStatement = record.problemStatement
        self.why1 = record.why1
        self.why2 = record.why2
        self.why3 = record.why3
        self.why4 = record.why4
        self.why5 = record.why5
        self.rootCause = record.rootCause
        self.preventativeStrategy = record.preventativeStrategy
    }

    public func toRecord() -> InvestigationRCARecord {
        InvestigationRCARecord(
            id: id,
            investigationId: investigationId,
            problemStatement: problemStatement,
            why1: why1,
            why2: why2,
            why3: why3,
            why4: why4,
            why5: why5,
            rootCause: rootCause,
            preventativeStrategy: preventativeStrategy
        )
    }
}
