import Foundation
import NetworkCore
import DiagnosticsEngine
import PersistenceKit

public enum InvestigationStatus: String, Sendable, CaseIterable, Identifiable, Codable {
    case open = "Open"
    case investigating = "Investigating"
    case mitigating = "Mitigating"
    case monitoring = "Monitoring"
    case resolved = "Resolved"
    case archived = "Archived"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .open: return "exclamationmark.circle"
        case .investigating: return "magnifyingglass.circle.fill"
        case .mitigating: return "shield.lefthalf.filled"
        case .monitoring: return "chart.line.uptrend.xyaxis.circle.fill"
        case .resolved: return "checkmark.circle.fill"
        case .archived: return "archivebox.circle.fill"
        }
    }

    public var isActive: Bool {
        self != .resolved && self != .archived
    }
}

public enum InvestigationSeverity: String, Sendable, CaseIterable, Identifiable, Codable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case critical = "Critical"

    public var id: String { rawValue }

    public var priorityPill: String {
        switch self {
        case .critical: return "P1 Critical"
        case .high: return "P2 High"
        case .medium: return "P3 Medium"
        case .low: return "P4 Low"
        }
    }

    /// SLA target time to resolve in minutes
    public var slaTargetMinutes: Double {
        switch self {
        case .critical: return 60.0    // 1 Hour SLA
        case .high: return 240.0       // 4 Hours SLA
        case .medium: return 720.0     // 12 Hours SLA
        case .low: return 1440.0       // 24 Hours SLA
        }
    }
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

    // Enterprise Incident Lifecycle & Scope
    public var commander: String?
    public var affectedServices: [String]
    public var affectedDevices: [String]
    public var blastRadius: String?
    public var detectedAt: Date
    public var mitigatedAt: Date?
    public var rootCauseCategory: RootCauseCategory?
    public var rootCauseSummary: String?

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
        resolution: String? = nil,
        commander: String? = nil,
        affectedServices: [String] = [],
        affectedDevices: [String] = [],
        blastRadius: String? = nil,
        detectedAt: Date? = nil,
        mitigatedAt: Date? = nil,
        rootCauseCategory: RootCauseCategory? = nil,
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
        self.commander = record.commander
        self.affectedServices = record.affectedServices.isEmpty ? [] : record.affectedServices.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        self.affectedDevices = record.affectedDevices.isEmpty ? [] : record.affectedDevices.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        self.blastRadius = record.blastRadius
        self.detectedAt = record.detectedAt != nil ? Date(timeIntervalSince1970: record.detectedAt!) : Date(timeIntervalSince1970: record.createdAt)
        self.mitigatedAt = record.mitigatedAt != nil ? Date(timeIntervalSince1970: record.mitigatedAt!) : nil
        self.rootCauseCategory = record.rootCauseCategory != nil ? RootCauseCategory(rawValue: record.rootCauseCategory!) : nil
        self.rootCauseSummary = record.rootCauseSummary
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
            resolution: resolution,
            commander: commander,
            affectedServices: affectedServices.joined(separator: ", "),
            affectedDevices: affectedDevices.joined(separator: ", "),
            blastRadius: blastRadius,
            detectedAt: detectedAt.timeIntervalSince1970,
            mitigatedAt: mitigatedAt?.timeIntervalSince1970,
            rootCauseCategory: rootCauseCategory?.rawValue,
            rootCauseSummary: rootCauseSummary
        )
    }

    // MARK: - SLA & MTTR Metrics

    /// Total outage or active investigation duration in minutes
    public var durationMinutes: Double {
        let end = resolvedAt ?? Date()
        return max(1.0, end.timeIntervalSince(detectedAt) / 60.0)
    }

    /// Time to Detect (minutes between incident detection and initial investigation triage)
    public var mttdMinutes: Double {
        max(0.0, createdAt.timeIntervalSince(detectedAt) / 60.0)
    }

    /// Time to Mitigate (minutes between incident detection and initial workaround/mitigation)
    public var mttmMinutes: Double? {
        guard let mit = mitigatedAt else { return nil }
        return max(0.0, mit.timeIntervalSince(detectedAt) / 60.0)
    }

    /// Time to Resolve (minutes between detection and final resolution)
    public var mttrMinutes: Double? {
        guard let res = resolvedAt else { return nil }
        return max(0.0, res.timeIntervalSince(detectedAt) / 60.0)
    }

    /// Checks if current duration has exceeded severity SLA threshold
    public var isSLAOverdue: Bool {
        status.isActive && durationMinutes > severity.slaTargetMinutes
    }
}
