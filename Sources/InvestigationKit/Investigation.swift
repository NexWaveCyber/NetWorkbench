import Foundation
import NetworkCore
import DiagnosticsEngine
import PersistenceKit

public enum InvestigationStatus: String, Sendable, CaseIterable, Identifiable {
    case open = "Open"
    case monitoring = "Monitoring"
    case resolved = "Resolved"
    case archived = "Archived"

    public var id: String { rawValue }
}

public enum InvestigationSeverity: String, Sendable, CaseIterable, Identifiable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case critical = "Critical"

    public var id: String { rawValue }
}

/// A first-class network problem investigation.
public struct Investigation: Sendable, Identifiable, Hashable {
    public let id: String
    public var title: String
    public var description: String
    public var environmentId: String?
    public var status: InvestigationStatus
    public var severity: InvestigationSeverity
    public var createdAt: Date
    public var updatedAt: Date
    public var resolvedAt: Date?
    public var resolution: String?

    public init(
        id: String = UUID().uuidString,
        title: String,
        description: String = "",
        environmentId: String? = nil,
        status: InvestigationStatus = .open,
        severity: InvestigationSeverity = .medium,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        resolvedAt: Date? = nil,
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

    public init(record: InvestigationRecord) {
        self.id = record.id
        self.title = record.title
        self.description = record.description
        self.environmentId = record.environmentId
        self.status = InvestigationStatus(rawValue: record.status) ?? .open
        self.severity = InvestigationSeverity(rawValue: record.severity) ?? .medium
        self.createdAt = Date(timeIntervalSince1970: record.createdAt)
        self.updatedAt = Date(timeIntervalSince1970: record.updatedAt)
        self.resolvedAt = record.resolvedAt != nil ? Date(timeIntervalSince1970: record.resolvedAt!) : nil
        self.resolution = record.resolution
    }

    public func toRecord() -> InvestigationRecord {
        InvestigationRecord(
            id: id,
            title: title,
            description: description,
            environmentId: environmentId,
            status: status.rawValue,
            severity: severity.rawValue,
            createdAt: createdAt.timeIntervalSince1970,
            updatedAt: updatedAt.timeIntervalSince1970,
            resolvedAt: resolvedAt?.timeIntervalSince1970,
            resolution: resolution
        )
    }
}
