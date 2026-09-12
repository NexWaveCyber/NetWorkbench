import Foundation
import NetworkCore

public enum VendorOS: String, Sendable, CaseIterable, Codable {
    case ciscoIOS = "Cisco IOS / IOS-XE"
    case ciscoNXOS = "Cisco NX-OS"
    case aristaEOS = "Arista EOS"
    case juniperJunos = "Juniper Junos"

    public var defaultPrompt: String {
        switch self {
        case .ciscoIOS: return "Router#"
        case .ciscoNXOS: return "switch#"
        case .aristaEOS: return "switch#"
        case .juniperJunos: return "user@host> "
        }
    }
}

public enum ConfigSectionType: String, Sendable, CaseIterable, Codable {
    case interface = "Interfaces"
    case vlan = "VLAN Database"
    case router = "Routing Protocols"
    case acl = "Access Control Lists"
    case management = "Security & Management"
    case line = "Console & VTY Lines"
    case global = "Global Settings"
    case other = "Other Directives"

    public var iconName: String {
        switch self {
        case .interface: return "cable.connector"
        case .vlan: return "square.stack.3d.up"
        case .router: return "point.3.connected.trianglepath.dotted"
        case .acl: return "shield.lefthalf.filled"
        case .management: return "key.fill"
        case .line: return "terminal"
        case .global: return "gearshape.2"
        case .other: return "doc.text"
        }
    }
}

public struct ConfigLine: Identifiable, Sendable, Hashable {
    public let id: Int
    public let lineNumber: Int
    public let indentation: Int
    public let rawText: String
    public let isComment: Bool

    public init(id: Int, lineNumber: Int, indentation: Int, rawText: String, isComment: Bool) {
        self.id = id
        self.lineNumber = lineNumber
        self.indentation = indentation
        self.rawText = rawText
        self.isComment = isComment
    }
}

public struct ConfigBlock: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let sectionType: ConfigSectionType
    public let startLine: Int
    public let endLine: Int
    public let lines: [ConfigLine]
    public let children: [ConfigBlock]

    public init(
        id: String = UUID().uuidString,
        title: String,
        sectionType: ConfigSectionType,
        startLine: Int,
        endLine: Int,
        lines: [ConfigLine],
        children: [ConfigBlock] = []
    ) {
        self.id = id
        self.title = title
        self.sectionType = sectionType
        self.startLine = startLine
        self.endLine = endLine
        self.lines = lines
        self.children = children
    }
}

public struct ConfigAST: Sendable {
    public let vendor: VendorOS
    public let hostname: String?
    public let domainName: String?
    public let rawContent: String
    public let blocks: [ConfigBlock]
    public let allLines: [ConfigLine]

    public init(
        vendor: VendorOS,
        hostname: String? = nil,
        domainName: String? = nil,
        rawContent: String,
        blocks: [ConfigBlock],
        allLines: [ConfigLine]
    ) {
        self.vendor = vendor
        self.hostname = hostname
        self.domainName = domainName
        self.rawContent = rawContent
        self.blocks = blocks
        self.allLines = allLines
    }
}

// MARK: - Semantic Configuration Models

public struct InterfaceConfig: Identifiable, Sendable, Hashable {
    public var id: String { name }
    public let name: String
    public let description: String?
    public let ipAddress: String?
    public let subnetMask: String?
    public let accessVlan: Int?
    public let trunkAllowedVlans: [Int]
    public let isShutdown: Bool
    public let mtu: Int?
    public let speed: String?
    public let duplex: String?

    public init(
        name: String,
        description: String? = nil,
        ipAddress: String? = nil,
        subnetMask: String? = nil,
        accessVlan: Int? = nil,
        trunkAllowedVlans: [Int] = [],
        isShutdown: Bool = false,
        mtu: Int? = nil,
        speed: String? = nil,
        duplex: String? = nil
    ) {
        self.name = name
        self.description = description
        self.ipAddress = ipAddress
        self.subnetMask = subnetMask
        self.accessVlan = accessVlan
        self.trunkAllowedVlans = trunkAllowedVlans
        self.isShutdown = isShutdown
        self.mtu = mtu
        self.speed = speed
        self.duplex = duplex
    }
}

public enum RoutingProtocol: String, Sendable, Codable {
    case bgp = "BGP"
    case ospf = "OSPF"
    case staticRoute = "Static"
    case isis = "IS-IS"
    case eigrp = "EIGRP"
}

public struct RoutingConfig: Identifiable, Sendable {
    public var id: String { "\(routingProtocol.rawValue)-\(autonomousSystem ?? 0)-\(routerId ?? "")" }
    public let routingProtocol: RoutingProtocol
    public let autonomousSystem: Int?
    public let routerId: String?
    public let networks: [String]
    public let neighbors: [String]
    public let areas: [String]

    public init(
        routingProtocol: RoutingProtocol,
        autonomousSystem: Int? = nil,
        routerId: String? = nil,
        networks: [String] = [],
        neighbors: [String] = [],
        areas: [String] = []
    ) {
        self.routingProtocol = routingProtocol
        self.autonomousSystem = autonomousSystem
        self.routerId = routerId
        self.networks = networks
        self.neighbors = neighbors
        self.areas = areas
    }
}

public enum ACLAction: String, Sendable, Codable {
    case permit = "PERMIT"
    case deny = "DENY"
}

public enum ACLProtocol: String, Sendable, Codable {
    case ip = "ip"
    case tcp = "tcp"
    case udp = "udp"
    case icmp = "icmp"
    case any = "any"
}

public enum NetworkMatch: Sendable, Hashable {
    case any
    case host(String)
    case subnet(network: String, wildcard: String)

    public var displayString: String {
        switch self {
        case .any:
            return "any"
        case .host(let ip):
            return "host \(ip)"
        case .subnet(let net, let mask):
            return "\(net) \(mask)"
        }
    }
}

public enum PortOperator: Sendable, Hashable {
    case eq(UInt16)
    case range(UInt16, UInt16)
    case gt(UInt16)
    case lt(UInt16)

    public func matches(port: UInt16) -> Bool {
        switch self {
        case .eq(let p):
            return port == p
        case .range(let start, let end):
            return port >= start && port <= end
        case .gt(let p):
            return port > p
        case .lt(let p):
            return port < p
        }
    }

    public var displayString: String {
        switch self {
        case .eq(let p): return "eq \(p)"
        case .range(let s, let e): return "range \(s) \(e)"
        case .gt(let p): return "gt \(p)"
        case .lt(let p): return "lt \(p)"
        }
    }
}

public struct ACLRule: Identifiable, Sendable {
    public let id: Int
    public let sequence: Int
    public let action: ACLAction
    public let protocolType: ACLProtocol
    public let source: NetworkMatch
    public let destination: NetworkMatch
    public let portOperator: PortOperator?
    public let isEstablished: Bool
    public let remark: String?
    public let rawText: String

    public init(
        id: Int,
        sequence: Int,
        action: ACLAction,
        protocolType: ACLProtocol,
        source: NetworkMatch,
        destination: NetworkMatch,
        portOperator: PortOperator? = nil,
        isEstablished: Bool = false,
        remark: String? = nil,
        rawText: String
    ) {
        self.id = id
        self.sequence = sequence
        self.action = action
        self.protocolType = protocolType
        self.source = source
        self.destination = destination
        self.portOperator = portOperator
        self.isEstablished = isEstablished
        self.remark = remark
        self.rawText = rawText
    }
}

public struct ACLConfig: Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let isExtended: Bool
    public let rules: [ACLRule]

    public init(name: String, isExtended: Bool = true, rules: [ACLRule] = []) {
        self.name = name
        self.isExtended = isExtended
        self.rules = rules
    }
}
