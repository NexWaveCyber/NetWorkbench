import Foundation
import SwiftUI
import NetworkCore

public enum DeviceRole: String, Codable, Sendable, CaseIterable, Identifiable {
    case router = "Router"
    case switchRole = "Switch"
    case firewall = "Firewall"
    case accessPoint = "Access Point"
    case server = "Server"
    case workstation = "Workstation"
    case other = "Other"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .router: return "point.3.filled.connected.trianglepath.dotted"
        case .switchRole: return "server.rack"
        case .firewall: return "shield.fill"
        case .accessPoint: return "wifi.router"
        case .server: return "cpu"
        case .workstation: return "laptopcomputer"
        case .other: return "network"
        }
    }
}

public enum DeviceVendor: String, Codable, Sendable, CaseIterable, Identifiable {
    case cisco = "Cisco"
    case arista = "Arista"
    case juniper = "Juniper"
    case linux = "Linux"
    case apple = "Apple"
    case ubiquiti = "Ubiquiti"
    case mikrotik = "MikroTik"
    case fortinet = "Fortinet"
    case vmware = "VMware"
    case raspberryPi = "Raspberry Pi"
    case intel = "Intel"
    case linksys = "Linksys"
    case netgear = "Netgear"
    case tpLink = "TP-Link"
    case asus = "ASUS"
    case synology = "Synology"
    case dlink = "D-Link"
    case paloAlto = "Palo Alto Networks"
    case huawei = "Huawei"
    case dell = "Dell"
    case hpe = "HPE / Aruba"
    case amazon = "Amazon / eero"
    case google = "Google / Nest"
    case arris = "Arris / Motorola"
    case avm = "AVM Fritz!Box"
    case belkin = "Belkin"
    case zyxel = "Zyxel"
    case generic = "Generic"

    public var id: String { rawValue }
}

public enum DeviceStatus: String, Codable, Sendable, CaseIterable {
    case online = "Online"
    case offline = "Offline"
    case unresponsive = "Unresponsive"
    case unknown = "Unknown"
}

public struct SNMPDeviceConfig: Codable, Sendable, Hashable {
    public var community: String
    public var port: Int
    public var version: String // "v1", "v2c", "v3"

    public init(community: String = "public", port: Int = 161, version: String = "v2c") {
        self.community = community
        self.port = port
        self.version = version
    }
}

public struct NetworkDevice: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public var displayName: String
    public var hostname: String
    public var managementIP: String
    public var macAddress: String?
    public var vendor: DeviceVendor
    public var role: DeviceRole
    public var platform: String?
    public var model: String?
    public var site: String?
    public var environmentId: String?
    public var tags: [String]
    public var status: DeviceStatus
    public var credentialRef: UUID?
    public var snmpConfig: SNMPDeviceConfig?
    public var lastSeen: Date?

    public init(
        id: UUID = UUID(),
        displayName: String,
        hostname: String,
        managementIP: String,
        macAddress: String? = nil,
        vendor: DeviceVendor = .generic,
        role: DeviceRole = .switchRole,
        platform: String? = nil,
        model: String? = nil,
        site: String? = nil,
        environmentId: String? = nil,
        tags: [String] = [],
        status: DeviceStatus = .unknown,
        credentialRef: UUID? = nil,
        snmpConfig: SNMPDeviceConfig? = nil,
        lastSeen: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.hostname = hostname
        self.managementIP = managementIP
        self.macAddress = macAddress
        self.vendor = vendor
        self.role = role
        self.platform = platform
        self.model = model
        self.site = site
        self.environmentId = environmentId
        self.tags = tags
        self.status = status
        self.credentialRef = credentialRef
        self.snmpConfig = snmpConfig
        self.lastSeen = lastSeen
    }
}

public struct DeviceBaseline: Identifiable, Codable, Sendable {
    public let id: UUID
    public let deviceId: UUID
    public let createdAt: Date
    public let avgLatencyMs: Double
    public let packetLossPct: Double
    public let openPorts: [Int]
    public let snmpSysDescr: String?
    public let notes: String

    public init(
        id: UUID = UUID(),
        deviceId: UUID,
        createdAt: Date = Date(),
        avgLatencyMs: Double,
        packetLossPct: Double,
        openPorts: [Int] = [],
        snmpSysDescr: String? = nil,
        notes: String = ""
    ) {
        self.id = id
        self.deviceId = deviceId
        self.createdAt = createdAt
        self.avgLatencyMs = avgLatencyMs
        self.packetLossPct = packetLossPct
        self.openPorts = openPorts
        self.snmpSysDescr = snmpSysDescr
        self.notes = notes
    }
}

public enum NeighborSource: String, Codable, Sendable {
    case arp = "ARP Table"
    case ndp = "NDP IPv6"
    case bonjour = "Bonjour mDNS"
    case combined = "Multi-Source"
}

public struct DiscoveredNeighbor: Identifiable, Codable, Sendable, Hashable {
    public var id: String { "\(ipAddress)-\(macAddress)" }
    public let ipAddress: String
    public var ipv6Address: String?
    public let macAddress: String
    public var hostname: String?
    public let interface: String
    public let discoverySource: NeighborSource
    public var ouiVendor: String?
    public var discoveredServices: [String]
    public var lastSeen: Date

    public init(
        ipAddress: String,
        ipv6Address: String? = nil,
        macAddress: String,
        hostname: String? = nil,
        interface: String = "en0",
        discoverySource: NeighborSource = .arp,
        ouiVendor: String? = nil,
        discoveredServices: [String] = [],
        lastSeen: Date = Date()
    ) {
        self.ipAddress = ipAddress
        self.ipv6Address = ipv6Address
        self.macAddress = macAddress
        self.hostname = hostname
        self.interface = interface
        self.discoverySource = discoverySource
        self.ouiVendor = ouiVendor
        self.discoveredServices = discoveredServices
        self.lastSeen = lastSeen
    }
}

public struct BaselineComparisonResult: Sendable {
    public let latencyDeltaMs: Double
    public let isLatencyDegraded: Bool
    public let lossDeltaPct: Double
    public let isLossDegraded: Bool
    public let missingPorts: [Int]
    public let unexpectedPorts: [Int]
    public let overallHealthScore: Int // 0 to 100

    public init(
        latencyDeltaMs: Double,
        isLatencyDegraded: Bool,
        lossDeltaPct: Double,
        isLossDegraded: Bool,
        missingPorts: [Int],
        unexpectedPorts: [Int],
        overallHealthScore: Int
    ) {
        self.latencyDeltaMs = latencyDeltaMs
        self.isLatencyDegraded = isLatencyDegraded
        self.lossDeltaPct = lossDeltaPct
        self.isLossDegraded = isLossDegraded
        self.missingPorts = missingPorts
        self.unexpectedPorts = unexpectedPorts
        self.overallHealthScore = overallHealthScore
    }
}

// MARK: - Ergonomic Helpers & Aliases

extension DeviceRole {
    public static let switchDevice: DeviceRole = .switchRole
    public static let gateway: DeviceRole = .router
    public static let host: DeviceRole = .workstation
}

extension DeviceStatus {
    public static let warning: DeviceStatus = .unresponsive

    public var color: SwiftUI.Color {
        switch self {
        case .online: return SwiftUI.Color(red: 0.20, green: 0.88, blue: 0.42)
        case .offline: return SwiftUI.Color(red: 1.0, green: 0.24, blue: 0.24)
        case .unresponsive: return SwiftUI.Color(red: 1.0, green: 0.62, blue: 0.05)
        case .unknown: return SwiftUI.Color.secondary
        }
    }
}

extension NetworkDevice {
    public var name: String {
        get { displayName }
        set { displayName = newValue }
    }

    public var ipAddress: String {
        get { managementIP }
        set { managementIP = newValue }
    }

    public var location: String? {
        get { site }
        set { site = newValue }
    }

    public init(
        id: UUID = UUID(),
        name: String,
        hostname: String? = nil,
        ipAddress: String,
        macAddress: String? = nil,
        vendor: DeviceVendor = .generic,
        role: DeviceRole = .switchRole,
        status: DeviceStatus = .online,
        location: String? = nil,
        tags: [String] = [],
        snmpConfig: SNMPDeviceConfig? = nil
    ) {
        self.id = id
        self.displayName = name
        self.hostname = hostname ?? name
        self.managementIP = ipAddress
        self.macAddress = macAddress
        self.vendor = vendor
        self.role = role
        self.platform = nil
        self.model = nil
        self.site = location
        self.environmentId = nil
        self.tags = tags
        self.status = status
        self.credentialRef = nil
        self.snmpConfig = snmpConfig
        self.lastSeen = Date()
    }
}

extension DiscoveredNeighbor {
    public var ip: String { ipAddress }
    public var ipv6: String? { ipv6Address }
    public var mac: String { macAddress }
    public var source: NeighborSource { discoverySource }
    public var vendor: DeviceVendor {
        if !macAddress.isEmpty {
            let inferred = OUIResolver.inferVendor(mac: macAddress)
            if inferred != .generic {
                return inferred
            }
        }
        if let oui = ouiVendor {
            let inferred = OUIResolver.inferVendor(fromName: oui)
            if inferred != .generic {
                return inferred
            }
            return DeviceVendor(rawValue: oui) ?? .generic
        }
        return .generic
    }
}

extension DeviceBaseline {
    public var pingLatencyMs: Double { avgLatencyMs }
    public var packetLossPercent: Double { packetLossPct }

    public init(
        id: UUID = UUID(),
        deviceId: UUID,
        createdAt: Date = Date(),
        pingLatencyMs: Double,
        jitterMs: Double = 0.0,
        packetLossPercent: Double = 0.0,
        openPorts: [Int] = []
    ) {
        self.id = id
        self.deviceId = deviceId
        self.createdAt = createdAt
        self.avgLatencyMs = pingLatencyMs
        self.packetLossPct = packetLossPercent
        self.openPorts = openPorts
        self.snmpSysDescr = nil
        self.notes = ""
    }
}

