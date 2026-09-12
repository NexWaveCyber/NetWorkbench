import Foundation

public enum PacketProtocol: Sendable, Codable, Hashable, CustomStringConvertible {
    case tcp
    case udp
    case icmp
    case icmpv6
    case dns
    case tls
    case http
    case arp
    case other(String)

    public var description: String {
        switch self {
        case .tcp: return "TCP"
        case .udp: return "UDP"
        case .icmp: return "ICMP"
        case .icmpv6: return "ICMPv6"
        case .dns: return "DNS"
        case .tls: return "TLS"
        case .http: return "HTTP"
        case .arp: return "ARP"
        case .other(let name): return name
        }
    }

    public var badgeColorHex: String {
        switch self {
        case .tcp: return "#00F0FF"      // Cyan
        case .udp: return "#3B82F6"      // Blue
        case .dns: return "#A855F7"      // Violet
        case .tls: return "#10B981"      // Green
        case .http: return "#F59E0B"     // Amber
        case .icmp, .icmpv6: return "#EC4899" // Pink
        case .arp: return "#8B5CF6"      // Purple
        case .other: return "#64748B"    // Slate
        }
    }
}

public struct TCPFlags: OptionSet, Sendable, Codable, Hashable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let fin = TCPFlags(rawValue: 1 << 0)
    public static let syn = TCPFlags(rawValue: 1 << 1)
    public static let rst = TCPFlags(rawValue: 1 << 2)
    public static let psh = TCPFlags(rawValue: 1 << 3)
    public static let ack = TCPFlags(rawValue: 1 << 4)
    public static let urg = TCPFlags(rawValue: 1 << 5)
    public static let ece = TCPFlags(rawValue: 1 << 6)
    public static let cwr = TCPFlags(rawValue: 1 << 7)

    public var flagSummary: String {
        var names: [String] = []
        if contains(.syn) { names.append("SYN") }
        if contains(.ack) { names.append("ACK") }
        if contains(.fin) { names.append("FIN") }
        if contains(.rst) { names.append("RST") }
        if contains(.psh) { names.append("PSH") }
        if contains(.urg) { names.append("URG") }
        return names.isEmpty ? "[None]" : "[\(names.joined(separator: ", "))]"
    }
}

public enum AnomalySeverity: String, Sendable, Codable, Hashable {
    case info = "INFO"
    case warning = "WARNING"
    case critical = "CRITICAL"
}

public enum TCPAnomaly: Sendable, Codable, Hashable, Identifiable {
    case retransmission(originalPacket: Int)
    case duplicateAck(count: Int, ackNum: UInt32)
    case zeroWindow
    case windowUpdate
    case connectionReset
    case unansweredSyn

    public var id: String {
        switch self {
        case .retransmission(let original): return "retrans-\(original)"
        case .duplicateAck(let count, let ack): return "dupack-\(count)-\(ack)"
        case .zeroWindow: return "zero-window"
        case .windowUpdate: return "window-update"
        case .connectionReset: return "rst"
        case .unansweredSyn: return "unanswered-syn"
        }
    }

    public var title: String {
        switch self {
        case .retransmission(let original): return "TCP Retransmission (Original: #\(original))"
        case .duplicateAck(let count, let ack): return "TCP Dup ACK #\(count) (Ack: \(ack))"
        case .zeroWindow: return "TCP Zero Window (Buffer Stall)"
        case .windowUpdate: return "TCP Window Update"
        case .connectionReset: return "TCP Connection Reset (RST)"
        case .unansweredSyn: return "Unanswered SYN / Handshake Timeout"
        }
    }

    public var severity: AnomalySeverity {
        switch self {
        case .retransmission, .duplicateAck: return .warning
        case .zeroWindow, .connectionReset: return .critical
        case .windowUpdate: return .info
        case .unansweredSyn: return .warning
        }
    }
}

public struct LayerField: Sendable, Codable, Hashable, Identifiable {
    public var id: String { "\(name):\(value)" }
    public let name: String
    public let value: String
    public let hexOffset: Int?
    public let hexLength: Int?

    public init(name: String, value: String, hexOffset: Int? = nil, hexLength: Int? = nil) {
        self.name = name
        self.value = value
        self.hexOffset = hexOffset
        self.hexLength = hexLength
    }
}

public struct DissectedLayer: Sendable, Codable, Hashable, Identifiable {
    public var id: String { name }
    public let name: String
    public let summary: String
    public let fields: [LayerField]

    public init(name: String, summary: String, fields: [LayerField]) {
        self.name = name
        self.summary = summary
        self.fields = fields
    }
}

public struct PacketRecord: Sendable, Codable, Hashable, Identifiable {
    public let id: UUID
    public let number: Int
    public let timestamp: Date
    public let relativeTime: TimeInterval
    public let sourceAddress: String
    public let destinationAddress: String
    public let sourcePort: Int?
    public let destinationPort: Int?
    public let protocolType: PacketProtocol
    public let wireLength: Int
    public let capturedLength: Int
    public let summary: String
    public let tcpFlags: TCPFlags?
    public let tcpSeq: UInt32?
    public let tcpAck: UInt32?
    public let tcpWindow: UInt16?
    public let anomalies: [TCPAnomaly]
    public let layers: [DissectedLayer]
    public let rawBytes: Data

    public init(
        id: UUID = UUID(),
        number: Int,
        timestamp: Date,
        relativeTime: TimeInterval,
        sourceAddress: String,
        destinationAddress: String,
        sourcePort: Int? = nil,
        destinationPort: Int? = nil,
        protocolType: PacketProtocol,
        wireLength: Int,
        capturedLength: Int,
        summary: String,
        tcpFlags: TCPFlags? = nil,
        tcpSeq: UInt32? = nil,
        tcpAck: UInt32? = nil,
        tcpWindow: UInt16? = nil,
        anomalies: [TCPAnomaly] = [],
        layers: [DissectedLayer] = [],
        rawBytes: Data = Data()
    ) {
        self.id = id
        self.number = number
        self.timestamp = timestamp
        self.relativeTime = relativeTime
        self.sourceAddress = sourceAddress
        self.destinationAddress = destinationAddress
        self.sourcePort = sourcePort
        self.destinationPort = destinationPort
        self.protocolType = protocolType
        self.wireLength = wireLength
        self.capturedLength = capturedLength
        self.summary = summary
        self.tcpFlags = tcpFlags
        self.tcpSeq = tcpSeq
        self.tcpAck = tcpAck
        self.tcpWindow = tcpWindow
        self.anomalies = anomalies
        self.layers = layers
        self.rawBytes = rawBytes
    }
}

public struct ConversationFlow: Sendable, Codable, Hashable, Identifiable {
    public let id: String
    public let source: String
    public let destination: String
    public let protocolType: PacketProtocol
    public let startTime: Date
    public let endTime: Date
    public let duration: TimeInterval
    public let packetsAtoB: Int
    public let packetsBtoA: Int
    public let totalPackets: Int
    public let bytesAtoB: Int
    public let bytesBtoA: Int
    public let totalBytes: Int
    public let anomalies: [TCPAnomaly]

    public init(
        id: String,
        source: String,
        destination: String,
        protocolType: PacketProtocol,
        startTime: Date,
        endTime: Date,
        duration: TimeInterval,
        packetsAtoB: Int,
        packetsBtoA: Int,
        totalPackets: Int,
        bytesAtoB: Int,
        bytesBtoA: Int,
        totalBytes: Int,
        anomalies: [TCPAnomaly] = []
    ) {
        self.id = id
        self.source = source
        self.destination = destination
        self.protocolType = protocolType
        self.startTime = startTime
        self.endTime = endTime
        self.duration = duration
        self.packetsAtoB = packetsAtoB
        self.packetsBtoA = packetsBtoA
        self.totalPackets = totalPackets
        self.bytesAtoB = bytesAtoB
        self.bytesBtoA = bytesBtoA
        self.totalBytes = totalBytes
        self.anomalies = anomalies
    }
}

public struct TalkerSummary: Sendable, Codable, Hashable, Identifiable {
    public var id: String { ipAddress }
    public let ipAddress: String
    public let sentBytes: Int
    public let receivedBytes: Int
    public let totalBytes: Int
    public let packetCount: Int

    public init(ipAddress: String, sentBytes: Int, receivedBytes: Int, totalBytes: Int, packetCount: Int) {
        self.ipAddress = ipAddress
        self.sentBytes = sentBytes
        self.receivedBytes = receivedBytes
        self.totalBytes = totalBytes
        self.packetCount = packetCount
    }
}

public struct ProtocolShare: Sendable, Codable, Hashable, Identifiable {
    public var id: String { protocolType.description }
    public let protocolType: PacketProtocol
    public let packetCount: Int
    public let byteCount: Int
    public let percentage: Double

    public init(protocolType: PacketProtocol, packetCount: Int, byteCount: Int, percentage: Double) {
        self.protocolType = protocolType
        self.packetCount = packetCount
        self.byteCount = byteCount
        self.percentage = percentage
    }
}

public struct AnomalyEvent: Sendable, Codable, Hashable, Identifiable {
    public let id: UUID
    public let packetNumber: Int
    public let relativeTime: TimeInterval
    public let source: String
    public let destination: String
    public let anomaly: TCPAnomaly
    public let severity: AnomalySeverity
    public let description: String

    public init(
        id: UUID = UUID(),
        packetNumber: Int,
        relativeTime: TimeInterval,
        source: String,
        destination: String,
        anomaly: TCPAnomaly,
        severity: AnomalySeverity,
        description: String
    ) {
        self.id = id
        self.packetNumber = packetNumber
        self.relativeTime = relativeTime
        self.source = source
        self.destination = destination
        self.anomaly = anomaly
        self.severity = severity
        self.description = description
    }
}

public struct PacketCaptureSummary: Sendable, Codable {
    public let fileName: String
    public let formatName: String
    public let totalPackets: Int
    public let totalBytes: Int
    public let duration: TimeInterval
    public let startTime: Date?
    public let endTime: Date?
    public let averageBitrateMbps: Double
    public let protocolDistribution: [ProtocolShare]
    public let topTalkers: [TalkerSummary]
    public let flows: [ConversationFlow]
    public let anomalies: [AnomalyEvent]
    public let packets: [PacketRecord]

    public init(
        fileName: String,
        formatName: String,
        totalPackets: Int,
        totalBytes: Int,
        duration: TimeInterval,
        startTime: Date? = nil,
        endTime: Date? = nil,
        averageBitrateMbps: Double = 0.0,
        protocolDistribution: [ProtocolShare] = [],
        topTalkers: [TalkerSummary] = [],
        flows: [ConversationFlow] = [],
        anomalies: [AnomalyEvent] = [],
        packets: [PacketRecord] = []
    ) {
        self.fileName = fileName
        self.formatName = formatName
        self.totalPackets = totalPackets
        self.totalBytes = totalBytes
        self.duration = duration
        self.startTime = startTime
        self.endTime = endTime
        self.averageBitrateMbps = averageBitrateMbps
        self.protocolDistribution = protocolDistribution
        self.topTalkers = topTalkers
        self.flows = flows
        self.anomalies = anomalies
        self.packets = packets
    }
}
