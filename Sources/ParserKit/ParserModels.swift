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
    case showVersion = "show version"
    case showVLAN = "show vlan brief"
    case showOSPFNeighbors = "show ip ospf neighbor"

    public var iconName: String {
        switch self {
        case .showIPInterfaceBrief: return "network"
        case .showInterfaces: return "cable.connector"
        case .showIPRoute: return "arrow.triangle.branch"
        case .showMacAddressTable: return "tablecells"
        case .showARP: return "point.filled.topleft.down.curvedto.point.bottomright.up"
        case .showNeighbors: return "point.3.connected.trianglepath.dotted"
        case .showBGPSummary: return "globe.americas.fill"
        case .showVersion: return "info.circle"
        case .showVLAN: return "square.grid.2x2"
        case .showOSPFNeighbors: return "point.3.filled.connected.trianglepath.dotted"
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
    case version(VersionEntry)
    case vlans([VlanEntry])
    case ospfNeighbors([OSPFNeighborEntry])

    public var recordCount: Int {
        switch self {
        case .ipInterfaceBrief(let a): return a.count
        case .interfaceDetails(let a): return a.count
        case .routes(let a): return a.count
        case .macTable(let a): return a.count
        case .arp(let a): return a.count
        case .neighbors(let a): return a.count
        case .bgpSummary(let a): return a.count
        case .version: return 1
        case .vlans(let a): return a.count
        case .ospfNeighbors(let a): return a.count
        }
    }

    /// Converts structured result to RFC 4180 compliant CSV string.
    public func toCSV() -> String {
        switch self {
        case .ipInterfaceBrief(let entries):
            var lines = ["Interface,IP Address,OK,Method,Status,Protocol"]
            for e in entries {
                lines.append("\"\(e.interface)\",\"\(e.ipAddress)\",\"\(e.isOK ? "YES" : "NO")\",\"\(e.method)\",\"\(e.status)\",\"\(e.lineProtocol)\"")
            }
            return lines.joined(separator: "\n")

        case .interfaceDetails(let entries):
            var lines = ["Name,Admin State,Line State,MAC Address,IP Address,MTU,Duplex,Speed,CRC Errors"]
            for e in entries {
                lines.append("\"\(e.name)\",\"\(e.adminState)\",\"\(e.lineState)\",\"\(e.macAddress ?? "")\",\"\(e.ipAddress ?? "")\",\"\(e.mtu.map(String.init) ?? "")\",\"\(e.duplex ?? "")\",\"\(e.speed ?? "")\",\"\(e.crcErrors)\"")
            }
            return lines.joined(separator: "\n")

        case .routes(let entries):
            var lines = ["Protocol,Prefix,Admin Distance,Metric,Next Hop,Interface,Age"]
            for e in entries {
                lines.append("\"\(e.protocolCode)\",\"\(e.prefix)\",\"\(e.adminDistance.map(String.init) ?? "")\",\"\(e.metric.map(String.init) ?? "")\",\"\(e.nextHop ?? "")\",\"\(e.outgoingInterface ?? "")\",\"\(e.age ?? "")\"")
            }
            return lines.joined(separator: "\n")

        case .macTable(let entries):
            var lines = ["VLAN,MAC Address,Type,Port"]
            for e in entries {
                lines.append("\"\(e.vlan)\",\"\(e.macAddress)\",\"\(e.type)\",\"\(e.port)\"")
            }
            return lines.joined(separator: "\n")

        case .arp(let entries):
            var lines = ["Protocol,IP Address,Age (min),MAC Address,Type,Interface,Vendor"]
            for e in entries {
                lines.append("\"\(e.protocolType)\",\"\(e.ipAddress)\",\"\(e.ageMinutes)\",\"\(e.macAddress)\",\"\(e.type)\",\"\(e.interface)\",\"\(e.vendor ?? "")\"")
            }
            return lines.joined(separator: "\n")

        case .neighbors(let entries):
            var lines = ["Device ID,Local Interface,Holdtime,Capability,Platform,Port ID"]
            for e in entries {
                lines.append("\"\(e.deviceId)\",\"\(e.localInterface)\",\"\(e.holdtime.map(String.init) ?? "")\",\"\(e.capability)\",\"\(e.platform)\",\"\(e.portId)\"")
            }
            return lines.joined(separator: "\n")

        case .bgpSummary(let entries):
            var lines = ["Neighbor,Version,Remote AS,Msg Rcvd,Msg Sent,Table Ver,InQ,OutQ,Up/Down,State/Pfx"]
            for e in entries {
                lines.append("\"\(e.neighborIP)\",\"\(e.version)\",\"\(e.remoteAS)\",\"\(e.msgRcvd)\",\"\(e.msgSent)\",\"\(e.tableVersion)\",\"\(e.inQ)\",\"\(e.outQ)\",\"\(e.upDown)\",\"\(e.stateOrPfxRcd)\"")
            }
            return lines.joined(separator: "\n")

        case .version(let v):
            var lines = ["Property,Value"]
            lines.append("\"Hardware\",\"\(v.hardware)\"")
            lines.append("\"OS Version\",\"\(v.osVersion)\"")
            lines.append("\"Uptime\",\"\(v.uptime)\"")
            lines.append("\"Serial Number\",\"\(v.serialNumber ?? "")\"")
            lines.append("\"System Image\",\"\(v.systemImage ?? "")\"")
            return lines.joined(separator: "\n")

        case .vlans(let entries):
            var lines = ["VLAN ID,Name,Status,Ports"]
            for e in entries {
                let portsStr = e.ports.joined(separator: "; ")
                lines.append("\"\(e.vlanId)\",\"\(e.name)\",\"\(e.status)\",\"\(portsStr)\"")
            }
            return lines.joined(separator: "\n")

        case .ospfNeighbors(let entries):
            var lines = ["Neighbor ID,Priority,State,Dead Time,Address,Interface"]
            for e in entries {
                lines.append("\"\(e.neighborId)\",\"\(e.priority)\",\"\(e.state)\",\"\(e.deadTime)\",\"\(e.address)\",\"\(e.interface)\"")
            }
            return lines.joined(separator: "\n")
        }
    }

    /// Converts structured result to formatted JSON string.
    public func toJSON() -> String {
        var rawObj: Any = []

        switch self {
        case .ipInterfaceBrief(let a):
            rawObj = a.map { ["interface": $0.interface, "ipAddress": $0.ipAddress, "isOK": $0.isOK, "method": $0.method, "status": $0.status, "lineProtocol": $0.lineProtocol] }
        case .interfaceDetails(let a):
            rawObj = a.map { ["name": $0.name, "adminState": $0.adminState, "lineState": $0.lineState, "macAddress": $0.macAddress ?? "", "ipAddress": $0.ipAddress ?? "", "mtu": $0.mtu ?? 0, "crcErrors": $0.crcErrors] }
        case .routes(let a):
            rawObj = a.map { ["protocol": $0.protocolCode, "prefix": $0.prefix, "adminDistance": $0.adminDistance ?? 0, "metric": $0.metric ?? 0, "nextHop": $0.nextHop ?? "", "interface": $0.outgoingInterface ?? ""] }
        case .macTable(let a):
            rawObj = a.map { ["vlan": $0.vlan, "macAddress": $0.macAddress, "type": $0.type, "port": $0.port] }
        case .arp(let a):
            rawObj = a.map { ["protocol": $0.protocolType, "ipAddress": $0.ipAddress, "age": $0.ageMinutes, "macAddress": $0.macAddress, "interface": $0.interface] }
        case .neighbors(let a):
            rawObj = a.map { ["deviceId": $0.deviceId, "localInterface": $0.localInterface, "platform": $0.platform, "portId": $0.portId] }
        case .bgpSummary(let a):
            rawObj = a.map { ["neighbor": $0.neighborIP, "remoteAS": $0.remoteAS, "upDown": $0.upDown, "stateOrPfx": $0.stateOrPfxRcd] }
        case .version(let v):
            rawObj = ["hardware": v.hardware, "osVersion": v.osVersion, "uptime": v.uptime, "serialNumber": v.serialNumber ?? "", "systemImage": v.systemImage ?? ""]
        case .vlans(let a):
            rawObj = a.map { ["vlanId": $0.vlanId, "name": $0.name, "status": $0.status, "ports": $0.ports] }
        case .ospfNeighbors(let a):
            rawObj = a.map { ["neighborId": $0.neighborId, "priority": $0.priority, "state": $0.state, "deadTime": $0.deadTime, "address": $0.address, "interface": $0.interface] }
        }

        if let data = try? JSONSerialization.data(withJSONObject: rawObj, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "[]"
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

public struct VersionEntry: Sendable {
    public let hardware: String
    public let osVersion: String
    public let uptime: String
    public let serialNumber: String?
    public let systemImage: String?

    public init(hardware: String, osVersion: String, uptime: String, serialNumber: String? = nil, systemImage: String? = nil) {
        self.hardware = hardware
        self.osVersion = osVersion
        self.uptime = uptime
        self.serialNumber = serialNumber
        self.systemImage = systemImage
    }
}

public struct VlanEntry: Identifiable, Sendable {
    public var id: Int { vlanId }
    public let vlanId: Int
    public let name: String
    public let status: String
    public let ports: [String]

    public init(vlanId: Int, name: String, status: String, ports: [String]) {
        self.vlanId = vlanId
        self.name = name
        self.status = status
        self.ports = ports
    }
}

public struct OSPFNeighborEntry: Identifiable, Sendable {
    public var id: String { "\(neighborId)-\(interface)" }
    public let neighborId: String
    public let priority: Int
    public let state: String
    public let deadTime: String
    public let address: String
    public let interface: String

    public init(neighborId: String, priority: Int, state: String, deadTime: String, address: String, interface: String) {
        self.neighborId = neighborId
        self.priority = priority
        self.state = state
        self.deadTime = deadTime
        self.address = address
        self.interface = interface
    }
}
