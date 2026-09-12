import Foundation

public enum SLAAlertType: String, Sendable, Codable {
    case latencySpike = "Latency Spike"
    case packetLoss = "Packet Loss Breach"
    case targetDown = "Target Unreachable"

    public var badgeColor: String {
        switch self {
        case .latencySpike: return "#F59E0B" // Amber
        case .packetLoss:   return "#F97316" // Orange
        case .targetDown:   return "#EF4444" // Crimson
        }
    }
}

public struct LatencySample: Identifiable, Sendable, Codable, Equatable {
    public let id: UUID
    public let target: String
    public let timestamp: Date
    public let latencyMs: Double?
    public let isTimeout: Bool
    public let jitterMs: Double?

    public init(
        id: UUID = UUID(),
        target: String,
        timestamp: Date = Date(),
        latencyMs: Double?,
        isTimeout: Bool = false,
        jitterMs: Double? = nil
    ) {
        self.id = id
        self.target = target
        self.timestamp = timestamp
        self.latencyMs = latencyMs
        self.isTimeout = isTimeout
        self.jitterMs = jitterMs
    }
}

public enum TimeRange: String, Sendable, Codable, CaseIterable, Identifiable {
    case last10Minutes = "10m"
    case lastHour = "1h"
    case last6Hours = "6h"
    case last24Hours = "24h"
    case last7Days = "7d"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .last10Minutes: return "Last 10 Minutes"
        case .lastHour:      return "Last 1 Hour"
        case .last6Hours:    return "Last 6 Hours"
        case .last24Hours:   return "Last 24 Hours"
        case .last7Days:     return "Last 7 Days"
        }
    }

    public func startDate(from now: Date = Date()) -> Date {
        switch self {
        case .last10Minutes: return now.addingTimeInterval(-600)
        case .lastHour:      return now.addingTimeInterval(-3600)
        case .last6Hours:    return now.addingTimeInterval(-21600)
        case .last24Hours:   return now.addingTimeInterval(-86400)
        case .last7Days:     return now.addingTimeInterval(-604800)
        }
    }

    public var targetBucketCount: Int {
        switch self {
        case .last10Minutes: return 60   // ~10s buckets
        case .lastHour:      return 60   // ~1m buckets
        case .last6Hours:    return 72   // ~5m buckets
        case .last24Hours:   return 96   // ~15m buckets
        case .last7Days:     return 112  // ~1.5h buckets
        }
    }
}

public struct AggregatedBucket: Identifiable, Sendable, Codable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let minMs: Double
    public let avgMs: Double
    public let maxMs: Double
    public let jitterMs: Double
    public let packetLossPct: Double
    public let sampleCount: Int

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        minMs: Double,
        avgMs: Double,
        maxMs: Double,
        jitterMs: Double,
        packetLossPct: Double,
        sampleCount: Int
    ) {
        self.id = id
        self.timestamp = timestamp
        self.minMs = minMs
        self.avgMs = avgMs
        self.maxMs = maxMs
        self.jitterMs = jitterMs
        self.packetLossPct = packetLossPct
        self.sampleCount = sampleCount
    }
}

public struct MonitorTargetConfig: Identifiable, Sendable, Codable, Equatable {
    public let id: UUID
    public var target: String
    public var name: String
    public var intervalSeconds: Double
    public var latencyThresholdMs: Double
    public var packetLossThresholdPct: Double
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        target: String,
        name: String,
        intervalSeconds: Double = 2.5,
        latencyThresholdMs: Double = 60.0,
        packetLossThresholdPct: Double = 5.0,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.target = target
        self.name = name
        self.intervalSeconds = intervalSeconds
        self.latencyThresholdMs = latencyThresholdMs
        self.packetLossThresholdPct = packetLossThresholdPct
        self.isEnabled = isEnabled
    }
}

public struct SLAMonitorAlert: Identifiable, Sendable, Codable, Equatable {
    public let id: UUID
    public let target: String
    public let targetName: String
    public let timestamp: Date
    public let alertType: SLAAlertType
    public let measuredValue: Double
    public let thresholdValue: Double
    public let message: String
    public var isAcknowledged: Bool

    public init(
        id: UUID = UUID(),
        target: String,
        targetName: String,
        timestamp: Date = Date(),
        alertType: SLAAlertType,
        measuredValue: Double,
        thresholdValue: Double,
        message: String,
        isAcknowledged: Bool = false
    ) {
        self.id = id
        self.target = target
        self.targetName = targetName
        self.timestamp = timestamp
        self.alertType = alertType
        self.measuredValue = measuredValue
        self.thresholdValue = thresholdValue
        self.message = message
        self.isAcknowledged = isAcknowledged
    }
}
