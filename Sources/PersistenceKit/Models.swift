import Foundation

public struct InvestigationRecord: Sendable, Identifiable, Hashable, Codable {
    public let id: String
    public var title: String
    public var description: String
    public var environmentId: String?
    public var status: String // "Open", "Investigating", "Mitigating", "Monitoring", "Resolved", "Archived"
    public var severity: String // "Low", "Medium", "High", "Critical"
    public var createdAt: Double
    public var updatedAt: Double
    public var resolvedAt: Double?
    public var resolution: String?
    
    // Enterprise Incident Extensions
    public var commander: String?
    public var affectedServices: String // comma-separated or JSON
    public var affectedDevices: String // comma-separated or JSON
    public var blastRadius: String?
    public var detectedAt: Double?
    public var mitigatedAt: Double?
    public var rootCauseCategory: String?
    public var rootCauseSummary: String?

    public init(
        id: String = UUID().uuidString,
        title: String,
        description: String = "",
        environmentId: String? = nil,
        status: String = "Open",
        severity: String = "Medium",
        createdAt: Double = Date().timeIntervalSince1970,
        updatedAt: Double = Date().timeIntervalSince1970,
        resolvedAt: Double? = nil,
        resolution: String? = nil,
        commander: String? = nil,
        affectedServices: String = "",
        affectedDevices: String = "",
        blastRadius: String? = nil,
        detectedAt: Double? = nil,
        mitigatedAt: Double? = nil,
        rootCauseCategory: String? = nil,
        rootCauseSummary: String? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.environmentId = environmentId
        self.status = status
        self.severity = severity
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.resolvedAt = resolvedAt
        self.resolution = resolution
        self.commander = commander
        self.affectedServices = affectedServices
        self.affectedDevices = affectedDevices
        self.blastRadius = blastRadius
        self.detectedAt = detectedAt ?? createdAt
        self.mitigatedAt = mitigatedAt
        self.rootCauseCategory = rootCauseCategory
        self.rootCauseSummary = rootCauseSummary
    }
}

public struct TimelineEventRecord: Sendable, Identifiable, Hashable, Codable {
    public let id: String
    public let investigationId: String
    public let timestamp: Double
    public let title: String
    public let detail: String
    public let category: String // "Diagnostic", "Manual", "Config", "StatusChange", "Syslog", "Action"

    public init(
        id: String = UUID().uuidString,
        investigationId: String,
        timestamp: Double = Date().timeIntervalSince1970,
        title: String,
        detail: String = "",
        category: String = "Diagnostic"
    ) {
        self.id = id
        self.investigationId = investigationId
        self.timestamp = timestamp
        self.title = title
        self.detail = detail
        self.category = category
    }
}

/// A forensic evidence artifact attached to an investigation (PCAP, CLI output, diff, log, etc.)
public struct EvidenceItemRecord: Sendable, Identifiable, Hashable, Codable {
    public let id: String
    public let investigationId: String
    public var title: String
    public var evidenceType: String // "pcap", "cliOutput", "configDiff", "diagnosticProbe", "syslog", "screenshot", "genericFile"
    public var filename: String
    public var sha256: String // Cryptographic chain-of-custody checksum
    public var byteSize: Int
    public var content: String // Raw text, hex dump, or Base64 payload
    public var sourceWorkbench: String
    public var createdAt: Double
    public var notes: String

    public init(
        id: String = UUID().uuidString,
        investigationId: String,
        title: String,
        evidenceType: String,
        filename: String,
        sha256: String,
        byteSize: Int,
        content: String,
        sourceWorkbench: String = "Investigations",
        createdAt: Double = Date().timeIntervalSince1970,
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
}

/// A hypothesis evaluated during root cause analysis
public struct HypothesisRecord: Sendable, Identifiable, Hashable, Codable {
    public let id: String
    public let investigationId: String
    public var statement: String
    public var status: String // "Untested", "Testing", "Confirmed", "Refuted"
    public var proposedTest: String
    public var findings: String
    public var updatedAt: Double

    public init(
        id: String = UUID().uuidString,
        investigationId: String,
        statement: String,
        status: String = "Untested",
        proposedTest: String = "",
        findings: String = "",
        updatedAt: Double = Date().timeIntervalSince1970
    ) {
        self.id = id
        self.investigationId = investigationId
        self.statement = statement
        self.status = status
        self.proposedTest = proposedTest
        self.findings = findings
        self.updatedAt = updatedAt
    }
}

/// An actionable checklist item for mitigation, verification, or post-mortem follow-up
public struct ActionItemRecord: Sendable, Identifiable, Hashable, Codable {
    public let id: String
    public let investigationId: String
    public var title: String
    public var phase: String // "Mitigation", "Verification", "PostMortem"
    public var isCompleted: Bool
    public var assignee: String?
    public var completedAt: Double?
    public var notes: String

    public init(
        id: String = UUID().uuidString,
        investigationId: String,
        title: String,
        phase: String = "Mitigation",
        isCompleted: Bool = false,
        assignee: String? = nil,
        completedAt: Double? = nil,
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
}

/// The 5-Whys structured root cause analysis breakdown
public struct InvestigationRCARecord: Sendable, Identifiable, Hashable, Codable {
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
}

public struct DiagnosticHistoryRecord: Sendable, Identifiable, Hashable, Codable {
    public let id: String
    public let target: String
    public let targetType: String
    public let timestamp: Double
    public let dnsHealthy: Bool
    public let pingLatency: Double?
    public let packetLoss: Double?
    public let tcpHealthy: Bool
    public let tlsHealthy: Bool
    public let httpStatus: Int?
    public let summary: String
    public let rawJson: String

    public init(
        id: String = UUID().uuidString,
        target: String,
        targetType: String,
        timestamp: Double = Date().timeIntervalSince1970,
        dnsHealthy: Bool,
        pingLatency: Double?,
        packetLoss: Double?,
        tcpHealthy: Bool,
        tlsHealthy: Bool,
        httpStatus: Int?,
        summary: String,
        rawJson: String
    ) {
        self.id = id
        self.target = target
        self.targetType = targetType
        self.timestamp = timestamp
        self.dnsHealthy = dnsHealthy
        self.pingLatency = pingLatency
        self.packetLoss = packetLoss
        self.tcpHealthy = tcpHealthy
        self.tlsHealthy = tlsHealthy
        self.httpStatus = httpStatus
        self.summary = summary
        self.rawJson = rawJson
    }
}

public struct EnvironmentRecord: Sendable, Identifiable, Hashable, Codable {
    public let id: String
    public var name: String
    public var environmentType: String
    public var gatewayIP: String
    public var subnetCIDR: String
    public var primaryDNS: String
    public var secondaryDNS: String?
    public var vlanRange: String
    public var runbookNotes: String
    public var isActive: Bool
    public var createdAt: Double
    public var updatedAt: Double

    public init(
        id: String = UUID().uuidString,
        name: String,
        environmentType: String = "campus",
        gatewayIP: String,
        subnetCIDR: String,
        primaryDNS: String = "1.1.1.1",
        secondaryDNS: String? = nil,
        vlanRange: String = "1 - 100",
        runbookNotes: String = "",
        isActive: Bool = false,
        createdAt: Double = Date().timeIntervalSince1970,
        updatedAt: Double = Date().timeIntervalSince1970
    ) {
        self.id = id
        self.name = name
        self.environmentType = environmentType
        self.gatewayIP = gatewayIP
        self.subnetCIDR = subnetCIDR
        self.primaryDNS = primaryDNS
        self.secondaryDNS = secondaryDNS
        self.vlanRange = vlanRange
        self.runbookNotes = runbookNotes
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct CustomCommandRecord: Sendable, Identifiable, Hashable, Codable {
    public let id: String
    public var intent: String
    public var category: String
    public var vendor: String
    public var syntax: String
    public var description: String
    public var isFavorite: Bool
    public var isCustom: Bool
    public var parametersJSON: String?
    public var createdAt: Double

    public init(
        id: String = UUID().uuidString,
        intent: String,
        category: String,
        vendor: String,
        syntax: String,
        description: String = "",
        isFavorite: Bool = false,
        isCustom: Bool = true,
        parametersJSON: String? = nil,
        createdAt: Double = Date().timeIntervalSince1970
    ) {
        self.id = id
        self.intent = intent
        self.category = category
        self.vendor = vendor
        self.syntax = syntax
        self.description = description
        self.isFavorite = isFavorite
        self.isCustom = isCustom
        self.parametersJSON = parametersJSON
        self.createdAt = createdAt
    }
}
