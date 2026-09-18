import Foundation

public enum EnvironmentType: String, Sendable, CaseIterable, Identifiable, Codable {
    case dataCenter = "datacenter"
    case campus = "campus"
    case branch = "branch"
    case lab = "lab"
    case cloud = "cloud"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .dataCenter: return "Data Center"
        case .campus: return "Campus HQ"
        case .branch: return "Branch Office"
        case .lab: return "Engineering Lab"
        case .cloud: return "Cloud Transit (VPC)"
        }
    }

    public var iconName: String {
        switch self {
        case .dataCenter: return "server.rack"
        case .campus: return "building.2.fill"
        case .branch: return "building.fill"
        case .lab: return "flask.fill"
        case .cloud: return "cloud.fill"
        }
    }

    public var accentColorHex: String {
        switch self {
        case .dataCenter: return "#00E5FF" // cyanPulse
        case .campus: return "#00E676"     // signalEmerald
        case .branch: return "#FFAB00"     // solarAmber
        case .lab: return "#7C4DFF"        // quantumViolet
        case .cloud: return "#2979FF"      // azurePro
        }
    }
}

/// A structured maintenance runbook step for standard operating procedures (SOPs)
public struct SiteRunbookStep: Hashable, Sendable, Identifiable, Codable {
    public let id: String
    public var title: String
    public var commandSyntax: String?
    public var isCompleted: Bool
    public var phase: String // "Pre-Maintenance", "Execution", "Verification"

    public init(
        id: String = UUID().uuidString,
        title: String,
        commandSyntax: String? = nil,
        isCompleted: Bool = false,
        phase: String = "Pre-Maintenance"
    ) {
        self.id = id
        self.title = title
        self.commandSyntax = commandSyntax
        self.isCompleted = isCompleted
        self.phase = phase
    }
}

/// Comprehensive IPAM IP address plan telemetry for a subnet scope
public struct SubnetIPAMInfo: Hashable, Sendable {
    public let cidr: String
    public let networkAddress: String
    public let broadcastAddress: String
    public let netmask: String
    public let wildcardMask: String
    public let firstUsableHost: String
    public let lastUsableHost: String
    public let totalCapacity: UInt64
    public let allocatedCount: Int
    public let utilizationPercentage: Double

    public init(
        cidr: String,
        networkAddress: String,
        broadcastAddress: String,
        netmask: String,
        wildcardMask: String,
        firstUsableHost: String,
        lastUsableHost: String,
        totalCapacity: UInt64,
        allocatedCount: Int,
        utilizationPercentage: Double
    ) {
        self.cidr = cidr
        self.networkAddress = networkAddress
        self.broadcastAddress = broadcastAddress
        self.netmask = netmask
        self.wildcardMask = wildcardMask
        self.firstUsableHost = firstUsableHost
        self.lastUsableHost = lastUsableHost
        self.totalCapacity = totalCapacity
        self.allocatedCount = allocatedCount
        self.utilizationPercentage = utilizationPercentage
    }

    public var isCritical: Bool {
        utilizationPercentage >= 90.0
    }

    public var isWarning: Bool {
        utilizationPercentage >= 75.0 && utilizationPercentage < 90.0
    }
}

/// IPAM calculation engine integrating with IPNetwork
public struct IPAMCalculator: Sendable {
    public static func calculate(cidr: String, allocatedDeviceCount: Int) -> SubnetIPAMInfo? {
        guard let network = IPNetwork(cidr) else { return nil }

        let netAddrStr = network.networkAddress.description
        let bcastStr = network.broadcastAddress?.description ?? "N/A"
        let netmaskStr = network.ipv4Netmask?.description ?? "255.255.255.0"
        let wildcardStr = network.ipv4WildcardMask?.description ?? "0.0.0.255"
        let firstHostStr = network.firstUsableAddress?.description ?? netAddrStr
        let lastHostStr = network.lastUsableAddress?.description ?? bcastStr
        let totalHosts = network.usableHostCount

        let pct: Double
        if totalHosts > 0 {
            pct = min(100.0, (Double(allocatedDeviceCount) / Double(totalHosts)) * 100.0)
        } else {
            pct = 0.0
        }

        return SubnetIPAMInfo(
            cidr: cidr,
            networkAddress: netAddrStr,
            broadcastAddress: bcastStr,
            netmask: netmaskStr,
            wildcardMask: wildcardStr,
            firstUsableHost: firstHostStr,
            lastUsableHost: lastHostStr,
            totalCapacity: totalHosts,
            allocatedCount: allocatedDeviceCount,
            utilizationPercentage: pct
        )
    }
}
