import Foundation

public struct InvestigationRecord: Sendable, Identifiable, Hashable {
    public let id: String
    public var title: String
    public var description: String
    public var environmentId: String?
    public var status: String // "Open", "Monitoring", "Resolved", "Archived"
    public var severity: String // "Low", "Medium", "High", "Critical"
    public var createdAt: Double
    public var updatedAt: Double
    public var resolvedAt: Double?
    public var resolution: String?

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
        resolution: String? = nil
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
    }
}

public struct TimelineEventRecord: Sendable, Identifiable, Hashable {
    public let id: String
    public let investigationId: String
    public let timestamp: Double
    public let title: String
    public let detail: String
    public let category: String // "Diagnostic", "Manual", "Config", "StatusChange"

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

public struct DiagnosticHistoryRecord: Sendable, Identifiable, Hashable {
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
