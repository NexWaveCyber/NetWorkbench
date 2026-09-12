import Foundation
import NetworkCore

public enum Vendor: String, Sendable, CaseIterable, Codable {
    case cisco = "Cisco"
    case arista = "Arista"
    case juniper = "Juniper"
    case generic = "Generic"
}

public enum OperatingSystem: String, Sendable, CaseIterable, Codable {
    case iosXE = "Cisco IOS-XE"
    case nxos = "Cisco NX-OS"
    case eos = "Arista EOS"
    case junos = "Juniper Junos"
    case any = "Multi-Platform"
}

public enum CommandFamily: String, Sendable, CaseIterable, Codable {
    case showIPInterfaceBrief = "show ip interface brief"
    case showInterfaces = "show interfaces"
    case showIPRoute = "show ip route"
    case showMacAddressTable = "show mac address-table"
    case showARP = "show arp"
    case showNeighbors = "show cdp / lldp neighbors"
    case showBGPSummary = "show ip bgp summary"

    public var iconName: String {
        switch self {
        case .showIPInterfaceBrief: return "network"
        case .showInterfaces: return "cable.connector"
        case .showIPRoute: return "arrow.triangle.branch"
        case .showMacAddressTable: return "tablecells"
        case .showARP: return "point.filled.topleft.down.curvedto.point.bottomright.up"
        case .showNeighbors: return "point.3.connected.trianglepath.dotted"
        case .showBGPSummary: return "globe.americas.fill"
        }
    }
}

public protocol VendorOutputParser: Sendable {
    var vendor: Vendor { get }
    var operatingSystem: OperatingSystem { get }
    var commandFamily: CommandFamily { get }
    var parserVersion: String { get }

    func canParse(rawOutput: String) -> Double
    func parse(rawOutput: String) throws -> StructuredResult
}

public enum StructuredResult: Sendable {
    case ipInterfaceBrief([IPInterfaceEntry])
    case interfaceDetails([InterfaceDetailEntry])
    case routes([RouteEntry])
    case macTable([MacTableEntry])
    case arp([ARPEntry])
    case neighbors([NeighborEntry])
    case bgpSummary([BGPSummaryEntry])

    public var recordCount: Int {
        switch self {
        case .ipInterfaceBrief(let a): return a.count
        case .interfaceDetails(let a): return a.count
        case .routes(let a): return a.count
        case .macTable(let a): return a.count
        case .arp(let a): return a.count
        case .neighbors(let a): return a.count
        case .bgpSummary(let a): return a.count
        }
    }
}

// MARK: - Parsed Entries

public struct IPInterfaceEntry: Identifiable, Sendable {
    public var id: String { interface }
    public let interface: String
    public let ipAddress: String
    public let isOK: Bool
    public let method: String
    public let status: String
    public let lineProtocol: String

    public var isUp: Bool {
        status.lowercased().contains("up") && lineProtocol.lowercased().contains("up")
    }

    public init(interface: String, ipAddress: String, isOK: Bool, method: String, status: String, lineProtocol: String) {
        self.interface = interface
        self.ipAddress = ipAddress
        self.isOK = isOK
        self.method = method
        self.status = status
        self.lineProtocol = lineProtocol
    }
}

public struct InterfaceDetailEntry: Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let adminState: String
    public let lineState: String
    public let hardwareType: String?
    public let macAddress: String?
    public let ipAddress: String?
    public let mtu: Int?
    public let bandwidth: String?
    public let duplex: String?
    public let speed: String?
    public let inputPackets: UInt64
    public let outputPackets: UInt64
    public let crcErrors: UInt64
    public let inputDiscards: UInt64
    public let anomalies: [String]

    public init(
        name: String,
        adminState: String,
        lineState: String,
        hardwareType: String? = nil,
        macAddress: String? = nil,
        ipAddress: String? = nil,
        mtu: Int? = nil,
        bandwidth: String? = nil,
        duplex: String? = nil,
        speed: String? = nil,
        inputPackets: UInt64 = 0,
        outputPackets: UInt64 = 0,
        crcErrors: UInt64 = 0,
        inputDiscards: UInt64 = 0,
        anomalies: [String] = []
    ) {
        self.name = name
        self.adminState = adminState
        self.lineState = lineState
        self.hardwareType = hardwareType
        self.macAddress = macAddress
        self.ipAddress = ipAddress
        self.mtu = mtu
        self.bandwidth = bandwidth
        self.duplex = duplex
        self.speed = speed
        self.inputPackets = inputPackets
        self.outputPackets = outputPackets
        self.crcErrors = crcErrors
        self.inputDiscards = inputDiscards
        self.anomalies = anomalies
    }
}

public struct RouteEntry: Identifiable, Sendable {
    public var id: String { "\(protocolCode)-\(prefix)-\(nextHop ?? outgoingInterface ?? "")" }
    public let protocolCode: String
    public let prefix: String
    public let adminDistance: Int?
    public let metric: Int?
    public let nextHop: String?
    public let outgoingInterface: String?
    public let age: String?

    public init(
        protocolCode: String,
        prefix: String,
        adminDistance: Int? = nil,
        metric: Int? = nil,
        nextHop: String? = nil,
        outgoingInterface: String? = nil,
        age: String? = nil
    ) {
        self.protocolCode = protocolCode
        self.prefix = prefix
        self.adminDistance = adminDistance
        self.metric = metric
        self.nextHop = nextHop
        self.outgoingInterface = outgoingInterface
        self.age = age
    }
}

public struct MacTableEntry: Identifiable, Sendable {
    public var id: String { "\(vlan)-\(macAddress)" }
    public let vlan: Int
    public let macAddress: String
    public let type: String
    public let port: String

    public init(vlan: Int, macAddress: String, type: String, port: String) {
        self.vlan = vlan
        self.macAddress = macAddress
        self.type = type
        self.port = port
    }
}

public struct ARPEntry: Identifiable, Sendable {
    public var id: String { "\(ipAddress)-\(macAddress)" }
    public let protocolType: String
    public let ipAddress: String
    public let ageMinutes: String
    public let macAddress: String
    public let type: String
    public let interface: String
    public let vendor: String?

    public init(protocolType: String, ipAddress: String, ageMinutes: String, macAddress: String, type: String, interface: String, vendor: String? = nil) {
        self.protocolType = protocolType
        self.ipAddress = ipAddress
        self.ageMinutes = ageMinutes
        self.macAddress = macAddress
        self.type = type
        self.interface = interface
        self.vendor = vendor
    }
}

public struct NeighborEntry: Identifiable, Sendable {
    public var id: String { "\(deviceId)-\(localInterface)" }
    public let deviceId: String
    public let localInterface: String
    public let holdtime: Int?
    public let capability: String
    public let platform: String
    public let portId: String

    public init(deviceId: String, localInterface: String, holdtime: Int? = nil, capability: String, platform: String, portId: String) {
        self.deviceId = deviceId
        self.localInterface = localInterface
        self.holdtime = holdtime
        self.capability = capability
        self.platform = platform
        self.portId = portId
    }
}

public struct BGPSummaryEntry: Identifiable, Sendable {
    public var id: String { neighborIP }
    public let neighborIP: String
    public let version: Int
    public let remoteAS: Int
    public let msgRcvd: UInt64
    public let msgSent: UInt64
    public let tableVersion: UInt64
    public let inQ: Int
    public let outQ: Int
    public let upDown: String
    public let stateOrPfxRcd: String

    public var isEstablished: Bool {
        // If stateOrPfxRcd is a number, BGP session is established and number represents prefixes received
        Int(stateOrPfxRcd) != nil
    }

    public init(
        neighborIP: String,
        version: Int,
        remoteAS: Int,
        msgRcvd: UInt64,
        msgSent: UInt64,
        tableVersion: UInt64,
        inQ: Int,
        outQ: Int,
        upDown: String,
        stateOrPfxRcd: String
    ) {
        self.neighborIP = neighborIP
        self.version = version
        self.remoteAS = remoteAS
        self.msgRcvd = msgRcvd
        self.msgSent = msgSent
        self.tableVersion = tableVersion
        self.inQ = inQ
        self.outQ = outQ
        self.upDown = upDown
        self.stateOrPfxRcd = stateOrPfxRcd
    }
}
