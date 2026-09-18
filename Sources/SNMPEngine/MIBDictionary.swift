import Foundation

/// Standard RFC MIB definitions dictionary and hierarchy tree.
public final class MIBDictionary: @unchecked Sendable {
    public static let shared = MIBDictionary()
    public let trie = OIDTrie()

    public init() {
        populateStandardMIBs()
    }

    private func populateStandardMIBs() {
        // Base Tree
        trie.insert(oid: "1.3.6.1", name: "internet")
        trie.insert(oid: "1.3.6.1.2.1", name: "mgmt.mib-2")

        // RFC 1213 MIB-II: system (1.3.6.1.2.1.1)
        trie.insert(oid: "1.3.6.1.2.1.1", name: "system", description: "System Information Group")
        trie.insert(oid: "1.3.6.1.2.1.1.1", name: "sysDescr", syntax: "DisplayString", description: "System hardware/software description")
        trie.insert(oid: "1.3.6.1.2.1.1.2", name: "sysObjectID", syntax: "OBJECT IDENTIFIER", description: "Authoritative vendor identification OID")
        trie.insert(oid: "1.3.6.1.2.1.1.3", name: "sysUpTime", syntax: "TimeTicks", description: "Time since network management portion was re-initialized")
        trie.insert(oid: "1.3.6.1.2.1.1.4", name: "sysContact", syntax: "DisplayString", description: "Contact person for this managed node")
        trie.insert(oid: "1.3.6.1.2.1.1.5", name: "sysName", syntax: "DisplayString", description: "Administratively-assigned node hostname")
        trie.insert(oid: "1.3.6.1.2.1.1.6", name: "sysLocation", syntax: "DisplayString", description: "Physical location of this node")
        trie.insert(oid: "1.3.6.1.2.1.1.7", name: "sysServices", syntax: "INTEGER", description: "Indicates set of services this entity provides")

        // RFC 1213 / RFC 2863: interfaces (1.3.6.1.2.1.2)
        trie.insert(oid: "1.3.6.1.2.1.2", name: "interfaces", description: "Network Interfaces Group")
        trie.insert(oid: "1.3.6.1.2.1.2.1", name: "ifNumber", syntax: "INTEGER", description: "Total count of network interfaces present")
        trie.insert(oid: "1.3.6.1.2.1.2.2", name: "ifTable", description: "List of interface entries")
        trie.insert(oid: "1.3.6.1.2.1.2.2.1.1", name: "ifIndex", syntax: "INTEGER", description: "Unique interface index number")
        trie.insert(oid: "1.3.6.1.2.1.2.2.1.2", name: "ifDescr", syntax: "DisplayString", description: "Interface name / description string")
        trie.insert(oid: "1.3.6.1.2.1.2.2.1.3", name: "ifType", syntax: "INTEGER", description: "Type of interface based on physical link protocol")
        trie.insert(oid: "1.3.6.1.2.1.2.2.1.4", name: "ifMtu", syntax: "INTEGER", description: "Maximum transmission unit (MTU) in octets")
        trie.insert(oid: "1.3.6.1.2.1.2.2.1.5", name: "ifSpeed", syntax: "Gauge32", description: "Estimated bandwidth in bits per second")
        trie.insert(oid: "1.3.6.1.2.1.2.2.1.6", name: "ifPhysAddress", syntax: "PhysAddress", description: "Interface physical hardware address (MAC)")
        trie.insert(oid: "1.3.6.1.2.1.2.2.1.7", name: "ifAdminStatus", syntax: "INTEGER", description: "Desired state (1=up, 2=down, 3=testing)")
        trie.insert(oid: "1.3.6.1.2.1.2.2.1.8", name: "ifOperStatus", syntax: "INTEGER", description: "Current operational state (1=up, 2=down)")
        trie.insert(oid: "1.3.6.1.2.1.2.2.1.9", name: "ifLastChange", syntax: "TimeTicks", description: "SysUpTime at which interface entered its current state")
        trie.insert(oid: "1.3.6.1.2.1.2.2.1.10", name: "ifInOctets", syntax: "Counter32", description: "Total input octets received")
        trie.insert(oid: "1.3.6.1.2.1.2.2.1.11", name: "ifInUcastPkts", syntax: "Counter32", description: "Inbound unicast packets delivered to higher sub-layer")
        trie.insert(oid: "1.3.6.1.2.1.2.2.1.13", name: "ifInDiscards", syntax: "Counter32", description: "Inbound packets discarded without errors")
        trie.insert(oid: "1.3.6.1.2.1.2.2.1.14", name: "ifInErrors", syntax: "Counter32", description: "Inbound packets containing errors")
        trie.insert(oid: "1.3.6.1.2.1.2.2.1.16", name: "ifOutOctets", syntax: "Counter32", description: "Total output octets transmitted")
        trie.insert(oid: "1.3.6.1.2.1.2.2.1.17", name: "ifOutUcastPkts", syntax: "Counter32", description: "Outbound unicast packets transmitted")
        trie.insert(oid: "1.3.6.1.2.1.2.2.1.19", name: "ifOutDiscards", syntax: "Counter32", description: "Outbound packets discarded without errors")
        trie.insert(oid: "1.3.6.1.2.1.2.2.1.20", name: "ifOutErrors", syntax: "Counter32", description: "Outbound packets that could not be transmitted due to errors")

        // IF-MIB (RFC 2863): ifXTable (1.3.6.1.2.1.31.1.1.1)
        trie.insert(oid: "1.3.6.1.2.1.31.1.1.1.1", name: "ifName", syntax: "DisplayString", description: "Textual name of the interface")
        trie.insert(oid: "1.3.6.1.2.1.31.1.1.1.6", name: "ifHCInOctets", syntax: "Counter64", description: "64-bit high-capacity input octets")
        trie.insert(oid: "1.3.6.1.2.1.31.1.1.1.10", name: "ifHCOutOctets", syntax: "Counter64", description: "64-bit high-capacity output octets")
        trie.insert(oid: "1.3.6.1.2.1.31.1.1.1.15", name: "ifHighSpeed", syntax: "Gauge32", description: "Bandwidth estimate in 1,000,000 bits/sec (Mbps)")
        trie.insert(oid: "1.3.6.1.2.1.31.1.1.1.18", name: "ifAlias", syntax: "DisplayString", description: "Administratively-configured interface description")

        // IP-MIB (1.3.6.1.2.1.4)
        trie.insert(oid: "1.3.6.1.2.1.4", name: "ip", description: "IP Group")
        trie.insert(oid: "1.3.6.1.2.1.4.1", name: "ipForwarding", syntax: "INTEGER", description: "IP gateway forwarding enabled (1=yes, 2=no)")
        trie.insert(oid: "1.3.6.1.2.1.4.2", name: "ipDefaultTTL", syntax: "INTEGER", description: "Default time-to-live value for IP datagrams")
        trie.insert(oid: "1.3.6.1.2.1.4.3", name: "ipInReceives", syntax: "Counter32", description: "Total input datagrams received from interfaces")
        trie.insert(oid: "1.3.6.1.2.1.4.4", name: "ipInHdrErrors", syntax: "Counter32", description: "Input datagrams discarded due to errors in IP headers")
        trie.insert(oid: "1.3.6.1.2.1.4.8", name: "ipInDiscards", syntax: "Counter32", description: "Valid input IP datagrams discarded due to lack of buffers")
        trie.insert(oid: "1.3.6.1.2.1.4.9", name: "ipInDelivers", syntax: "Counter32", description: "Input datagrams successfully delivered to higher protocols")
        trie.insert(oid: "1.3.6.1.2.1.4.10", name: "ipOutRequests", syntax: "Counter32", description: "IP datagrams locally supplied to IP layer for transmission")
        trie.insert(oid: "1.3.6.1.2.1.4.20.1.1", name: "ipAdEntAddr", syntax: "IpAddress", description: "IPv4 address corresponding to interface")
        trie.insert(oid: "1.3.6.1.2.1.4.20.1.3", name: "ipAdEntNetMask", syntax: "IpAddress", description: "Subnet mask associated with IPv4 address")

        // TCP-MIB (RFC 4022): 1.3.6.1.2.1.6
        trie.insert(oid: "1.3.6.1.2.1.6", name: "tcp", description: "TCP Protocol Group")
        trie.insert(oid: "1.3.6.1.2.1.6.1", name: "tcpRtoAlgorithm", syntax: "INTEGER", description: "Algorithm used to determine timeout retransmission value")
        trie.insert(oid: "1.3.6.1.2.1.6.2", name: "tcpRtoMin", syntax: "INTEGER", description: "Minimum retransmission timeout in milliseconds")
        trie.insert(oid: "1.3.6.1.2.1.6.3", name: "tcpRtoMax", syntax: "INTEGER", description: "Maximum retransmission timeout in milliseconds")
        trie.insert(oid: "1.3.6.1.2.1.6.4", name: "tcpMaxConn", syntax: "INTEGER", description: "Limit on total number of concurrent TCP connections")
        trie.insert(oid: "1.3.6.1.2.1.6.5", name: "tcpActiveOpens", syntax: "Counter32", description: "Number of direct active transitions from CLOSED to SYN-SENT")
        trie.insert(oid: "1.3.6.1.2.1.6.6", name: "tcpPassiveOpens", syntax: "Counter32", description: "Number of direct passive transitions from LISTEN to SYN-RCVD")
        trie.insert(oid: "1.3.6.1.2.1.6.7", name: "tcpAttemptFails", syntax: "Counter32", description: "Times TCP connections made direct failure transitions")
        trie.insert(oid: "1.3.6.1.2.1.6.8", name: "tcpEstabResets", syntax: "Counter32", description: "Times TCP connections transitioned from ESTABLISHED or CLOSE-WAIT to CLOSED")
        trie.insert(oid: "1.3.6.1.2.1.6.9", name: "tcpCurrEstab", syntax: "Gauge32", description: "Current number of TCP connections in ESTABLISHED or CLOSE-WAIT")
        trie.insert(oid: "1.3.6.1.2.1.6.10", name: "tcpInSegs", syntax: "Counter32", description: "Total segments received, including those received in error")
        trie.insert(oid: "1.3.6.1.2.1.6.11", name: "tcpOutSegs", syntax: "Counter32", description: "Total segments sent, including those on current connections")
        trie.insert(oid: "1.3.6.1.2.1.6.12", name: "tcpRetransSegs", syntax: "Counter32", description: "Number of segments retransmitted")

        // UDP-MIB (RFC 4113): 1.3.6.1.2.1.7
        trie.insert(oid: "1.3.6.1.2.1.7", name: "udp", description: "UDP Protocol Group")
        trie.insert(oid: "1.3.6.1.2.1.7.1", name: "udpInDatagrams", syntax: "Counter32", description: "Total UDP datagrams delivered to application users")
        trie.insert(oid: "1.3.6.1.2.1.7.2", name: "udpNoPorts", syntax: "Counter32", description: "Received UDP datagrams with no application listener on port")
        trie.insert(oid: "1.3.6.1.2.1.7.3", name: "udpInErrors", syntax: "Counter32", description: "Received UDP datagrams discarded for reasons other than no application")
        trie.insert(oid: "1.3.6.1.2.1.7.4", name: "udpOutDatagrams", syntax: "Counter32", description: "Total UDP datagrams sent from this entity")

        // HOST-RESOURCES-MIB (RFC 2790): 1.3.6.1.2.1.25
        trie.insert(oid: "1.3.6.1.2.1.25", name: "host", description: "Host Resources MIB Group")
        trie.insert(oid: "1.3.6.1.2.1.25.1.1", name: "hrSystemUptime", syntax: "TimeTicks", description: "Amount of time since this host was last booted")
        trie.insert(oid: "1.3.6.1.2.1.25.1.5", name: "hrSystemNumUsers", syntax: "Gauge32", description: "Number of user sessions currently active on this host")
        trie.insert(oid: "1.3.6.1.2.1.25.1.6", name: "hrSystemProcesses", syntax: "Gauge32", description: "Number of operating system processes currently running")
        trie.insert(oid: "1.3.6.1.2.1.25.2.2", name: "hrMemorySize", syntax: "INTEGER", description: "Amount of physical RAM in kilobytes (KB)")
        trie.insert(oid: "1.3.6.1.2.1.25.3.3.1.2", name: "hrProcessorLoad", syntax: "INTEGER", description: "Average percentage CPU utilization (0..100%)")

        // Cisco Private Enterprise MIB: 1.3.6.1.4.1.9
        trie.insert(oid: "1.3.6.1.4.1.9", name: "cisco", description: "Cisco Systems Private Enterprise")
        trie.insert(oid: "1.3.6.1.4.1.9.9.48.1.1.1.5", name: "ciscoMemoryPoolUsed", syntax: "Gauge32", description: "Used bytes from memory pool")
        trie.insert(oid: "1.3.6.1.4.1.9.9.48.1.1.1.6", name: "ciscoMemoryPoolFree", syntax: "Gauge32", description: "Free bytes in memory pool")
        trie.insert(oid: "1.3.6.1.4.1.9.9.109.1.1.1.1.3", name: "ciscoCPU5sec", syntax: "Gauge32", description: "CPU busy percentage over 5 seconds")
        trie.insert(oid: "1.3.6.1.4.1.9.9.109.1.1.1.1.4", name: "ciscoCPU1min", syntax: "Gauge32", description: "CPU busy percentage over 1 minute")
        trie.insert(oid: "1.3.6.1.4.1.9.9.109.1.1.1.1.5", name: "ciscoCPU5min", syntax: "Gauge32", description: "CPU busy percentage over 5 minutes")
    }

    public static let standardNodes: [MIBNodeInfo] = [
        // System Group (RFC 1213)
        MIBNodeInfo(oid: "1.3.6.1.2.1.1.1", name: "sysDescr", syntax: "DisplayString", access: "read-only", description: "A textual description of the entity. Includes full hardware and OS software version."),
        MIBNodeInfo(oid: "1.3.6.1.2.1.1.2", name: "sysObjectID", syntax: "OBJECT IDENTIFIER", access: "read-only", description: "The vendor's authoritative identification of the network management subsystem."),
        MIBNodeInfo(oid: "1.3.6.1.2.1.1.3", name: "sysUpTime", syntax: "TimeTicks", access: "read-only", description: "The time (in hundredths of a second) since network management was last re-initialized."),
        MIBNodeInfo(oid: "1.3.6.1.2.1.1.4", name: "sysContact", syntax: "DisplayString", access: "read-write", description: "Textual contact person for this managed node and contact instructions."),
        MIBNodeInfo(oid: "1.3.6.1.2.1.1.5", name: "sysName", syntax: "DisplayString", access: "read-write", description: "An administratively-assigned name for this node (typically FQDN)."),
        MIBNodeInfo(oid: "1.3.6.1.2.1.1.6", name: "sysLocation", syntax: "DisplayString", access: "read-write", description: "Physical location of this node (e.g. Data Center, Rack 14B)."),
        MIBNodeInfo(oid: "1.3.6.1.2.1.1.7", name: "sysServices", syntax: "INTEGER", access: "read-only", description: "Indicates the set of services that this entity primarily offers."),

        // Interfaces Group (RFC 1213 / RFC 2863)
        MIBNodeInfo(oid: "1.3.6.1.2.1.2.1", name: "ifNumber", syntax: "INTEGER", access: "read-only", description: "Total number of network interfaces present on this system."),
        MIBNodeInfo(oid: "1.3.6.1.2.1.2.2.1.1", name: "ifIndex", syntax: "INTEGER", access: "read-only", description: "Unique interface index number."),
        MIBNodeInfo(oid: "1.3.6.1.2.1.2.2.1.2", name: "ifDescr", syntax: "DisplayString", access: "read-only", description: "Textual string containing name or manufacturer description of interface."),
        MIBNodeInfo(oid: "1.3.6.1.2.1.2.2.1.3", name: "ifType", syntax: "INTEGER", access: "read-only", description: "Type of interface based on physical/link protocol."),
        MIBNodeInfo(oid: "1.3.6.1.2.1.2.2.1.5", name: "ifSpeed", syntax: "Gauge32", access: "read-only", description: "Estimated bandwidth in bits per second."),
        MIBNodeInfo(oid: "1.3.6.1.2.1.2.2.1.6", name: "ifPhysAddress", syntax: "PhysAddress", access: "read-only", description: "Interface hardware MAC address."),
        MIBNodeInfo(oid: "1.3.6.1.2.1.2.2.1.7", name: "ifAdminStatus", syntax: "INTEGER", access: "read-write", description: "Desired state of interface (1=up, 2=down, 3=testing)."),
        MIBNodeInfo(oid: "1.3.6.1.2.1.2.2.1.8", name: "ifOperStatus", syntax: "INTEGER", access: "read-only", description: "Operational state of interface (1=up, 2=down)."),
        MIBNodeInfo(oid: "1.3.6.1.2.1.2.2.1.10", name: "ifInOctets", syntax: "Counter32", access: "read-only", description: "Total octets received on interface."),
        MIBNodeInfo(oid: "1.3.6.1.2.1.2.2.1.14", name: "ifInErrors", syntax: "Counter32", access: "read-only", description: "Inbound packets discarded due to errors."),
        MIBNodeInfo(oid: "1.3.6.1.2.1.2.2.1.16", name: "ifOutOctets", syntax: "Counter32", access: "read-only", description: "Total octets transmitted on interface."),
        MIBNodeInfo(oid: "1.3.6.1.2.1.2.2.1.20", name: "ifOutErrors", syntax: "Counter32", access: "read-only", description: "Outbound packets that failed transmission due to errors."),

        // IF-MIB (RFC 2863)
        MIBNodeInfo(oid: "1.3.6.1.2.1.31.1.1.1.1", name: "ifName", syntax: "DisplayString", access: "read-only", description: "Textual name of interface (e.g. GigabitEthernet0/1)."),
        MIBNodeInfo(oid: "1.3.6.1.2.1.31.1.1.1.6", name: "ifHCInOctets", syntax: "Counter64", access: "read-only", description: "64-bit high-capacity total octets received."),
        MIBNodeInfo(oid: "1.3.6.1.2.1.31.1.1.1.10", name: "ifHCOutOctets", syntax: "Counter64", access: "read-only", description: "64-bit high-capacity total octets transmitted."),
        MIBNodeInfo(oid: "1.3.6.1.2.1.31.1.1.1.18", name: "ifAlias", syntax: "DisplayString", access: "read-write", description: "Administratively-configured interface description."),

        // IP-MIB (RFC 4293)
        MIBNodeInfo(oid: "1.3.6.1.2.1.4.1", name: "ipForwarding", syntax: "INTEGER", access: "read-write", description: "IP gateway packet forwarding enabled flag (1=yes, 2=no)."),
        MIBNodeInfo(oid: "1.3.6.1.2.1.4.3", name: "ipInReceives", syntax: "Counter32", access: "read-only", description: "Total input datagrams received from interfaces."),
        MIBNodeInfo(oid: "1.3.6.1.2.1.4.8", name: "ipInDiscards", syntax: "Counter32", access: "read-only", description: "Valid input IP datagrams discarded due to lack of buffers."),
        MIBNodeInfo(oid: "1.3.6.1.2.1.4.10", name: "ipOutRequests", syntax: "Counter32", access: "read-only", description: "Total IP datagrams supplied for transmission."),

        // TCP-MIB (RFC 4022)
        MIBNodeInfo(oid: "1.3.6.1.2.1.6.5", name: "tcpActiveOpens", syntax: "Counter32", access: "read-only", description: "Number of active transitions from CLOSED to SYN-SENT."),
        MIBNodeInfo(oid: "1.3.6.1.2.1.6.6", name: "tcpPassiveOpens", syntax: "Counter32", access: "read-only", description: "Number of passive transitions from LISTEN to SYN-RCVD."),
        MIBNodeInfo(oid: "1.3.6.1.2.1.6.9", name: "tcpCurrEstab", syntax: "Gauge32", access: "read-only", description: "Current count of active TCP connections in ESTABLISHED state."),
        MIBNodeInfo(oid: "1.3.6.1.2.1.6.12", name: "tcpRetransSegs", syntax: "Counter32", access: "read-only", description: "Total segments retransmitted due to timeout or loss."),

        // UDP-MIB (RFC 4113)
        MIBNodeInfo(oid: "1.3.6.1.2.1.7.1", name: "udpInDatagrams", syntax: "Counter32", access: "read-only", description: "Total UDP datagrams delivered to application users."),
        MIBNodeInfo(oid: "1.3.6.1.2.1.7.2", name: "udpNoPorts", syntax: "Counter32", access: "read-only", description: "Received UDP packets with no destination port listening."),

        // HOST-RESOURCES-MIB (RFC 2790)
        MIBNodeInfo(oid: "1.3.6.1.2.1.25.1.1", name: "hrSystemUptime", syntax: "TimeTicks", access: "read-only", description: "Host operational system uptime."),
        MIBNodeInfo(oid: "1.3.6.1.2.1.25.1.6", name: "hrSystemProcesses", syntax: "Gauge32", access: "read-only", description: "Total running operating system processes."),
        MIBNodeInfo(oid: "1.3.6.1.2.1.25.2.2", name: "hrMemorySize", syntax: "INTEGER", access: "read-only", description: "Installed physical RAM capacity in kilobytes (KB)."),
        MIBNodeInfo(oid: "1.3.6.1.2.1.25.3.3.1.2", name: "hrProcessorLoad", syntax: "INTEGER", access: "read-only", description: "Processor average CPU utilization (0..100%)."),

        // Cisco Private Enterprise MIB
        MIBNodeInfo(oid: "1.3.6.1.4.1.9.9.48.1.1.1.5", name: "ciscoMemoryPoolUsed", syntax: "Gauge32", access: "read-only", description: "Memory pool used bytes on Cisco device."),
        MIBNodeInfo(oid: "1.3.6.1.4.1.9.9.48.1.1.1.6", name: "ciscoMemoryPoolFree", syntax: "Gauge32", access: "read-only", description: "Memory pool free bytes on Cisco device."),
        MIBNodeInfo(oid: "1.3.6.1.4.1.9.9.109.1.1.1.1.5", name: "ciscoCPU5min", syntax: "Gauge32", access: "read-only", description: "Cisco device 5-minute average CPU busy percentage.")
    ]

    private var customNodesList: [MIBNodeInfo] = []

    public var allNodes: [MIBNodeInfo] {
        MIBDictionary.standardNodes + customNodesList
    }

    public func resolve(oid: String) -> String {
        trie.resolveName(oid: oid)
    }

    /// Builds hierarchical outline tree starting at prefix (default: 1.3.6.1)
    public func buildHierarchyTree(fromPrefix prefix: String = "1.3.6.1") -> MIBTreeNode? {
        trie.buildTree(fromPrefix: prefix)
    }

    /// Registers a custom MIB node at runtime
    public func registerCustomNode(
        oid: String,
        name: String,
        syntax: String = "DisplayString",
        access: String = "read-only",
        description: String = ""
    ) {
        trie.insert(oid: oid, name: name, syntax: syntax, description: description)
        let info = MIBNodeInfo(oid: oid, name: name, syntax: syntax, access: access, description: description)
        if !customNodesList.contains(where: { $0.oid == oid }) {
            customNodesList.append(info)
        }
    }
}

public struct MIBNodeInfo: Identifiable, Sendable, Hashable {
    public var id: String { oid }
    public let oid: String
    public let name: String
    public let syntax: String
    public let access: String
    public let description: String

    public init(oid: String, name: String, syntax: String = "DisplayString", access: String = "read-only", description: String = "") {
        self.oid = oid
        self.name = name
        self.syntax = syntax
        self.access = access
        self.description = description
    }
}

/// Lightweight parser for importing standard SMIv2 MIB text files or definitions
public struct MIBFileParser: Sendable {
    public init() {}

    public static func parse(content: String) -> [MIBNodeInfo] {
        var results: [MIBNodeInfo] = []
        let lines = content.components(separatedBy: .newlines)

        var currentName: String? = nil
        var currentSyntax: String = "DisplayString"
        var currentAccess: String = "read-only"
        var currentDesc: String = ""
        var isInDesc = false

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("--") { continue }

            // Check for OBJECT-TYPE definition
            if line.contains("OBJECT-TYPE") {
                let parts = line.components(separatedBy: "OBJECT-TYPE")
                currentName = parts.first?.trimmingCharacters(in: .whitespaces)
                currentSyntax = "DisplayString"
                currentAccess = "read-only"
                currentDesc = ""
                isInDesc = false
                continue
            }

            // Check for SYNTAX
            if line.hasPrefix("SYNTAX") {
                let syntaxPart = line.replacingOccurrences(of: "SYNTAX", with: "").trimmingCharacters(in: .whitespaces)
                currentSyntax = syntaxPart.components(separatedBy: " ").first ?? "DisplayString"
                continue
            }

            // Check for MAX-ACCESS / ACCESS
            if line.hasPrefix("MAX-ACCESS") || line.hasPrefix("ACCESS") {
                let accessPart = line.replacingOccurrences(of: "MAX-ACCESS", with: "").replacingOccurrences(of: "ACCESS", with: "").trimmingCharacters(in: .whitespaces)
                currentAccess = accessPart
                continue
            }

            // Check for DESCRIPTION
            if line.hasPrefix("DESCRIPTION") {
                let quoteCount = line.filter { $0 == "\"" }.count
                let descText = line.replacingOccurrences(of: "DESCRIPTION", with: "")
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                currentDesc = descText
                isInDesc = (quoteCount < 2)
                continue
            }

            if isInDesc {
                if line.contains("\"") {
                    isInDesc = false
                    currentDesc += " " + line.replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespaces)
                } else {
                    currentDesc += " " + line
                }
                continue
            }

            // Check for OID assignment: ::= { parent index } or direct dotted OID
            if line.contains("::=") {
                if let name = currentName {
                    // Try extracting parent and index
                    if let startIdx = line.firstIndex(of: "{"), let endIdx = line.firstIndex(of: "}") {
                        let block = line[line.index(after: startIdx)..<endIdx].trimmingCharacters(in: .whitespaces)
                        let comps = block.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                        if comps.count >= 2 {
                            let parent = comps[0]
                            let index = comps[1]
                            // Derive synthetic or mapped OID
                            let derivedOID: String
                            if parent == "system" {
                                derivedOID = "1.3.6.1.2.1.1.\(index)"
                            } else if parent == "interfaces" {
                                derivedOID = "1.3.6.1.2.1.2.\(index)"
                            } else if parent == "ip" {
                                derivedOID = "1.3.6.1.2.1.4.\(index)"
                            } else if parent == "tcp" {
                                derivedOID = "1.3.6.1.2.1.6.\(index)"
                            } else if parent == "udp" {
                                derivedOID = "1.3.6.1.2.1.7.\(index)"
                            } else {
                                derivedOID = "1.3.6.1.4.1.99999.\(index)"
                            }
                            results.append(MIBNodeInfo(
                                oid: derivedOID,
                                name: name,
                                syntax: currentSyntax,
                                access: currentAccess,
                                description: currentDesc.trimmingCharacters(in: .whitespaces)
                            ))
                        }
                    }
                    currentName = nil
                }
            }

            // Also support simple tabular/CSV format: OID, Name, Syntax, Access, Description
            let commaParts = line.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if commaParts.count >= 2 && (commaParts[0].hasPrefix("1.3.") || commaParts[0].hasPrefix(".1.3.")) {
                let oid = commaParts[0]
                let name = commaParts[1]
                let syntax = commaParts.count > 2 ? commaParts[2] : "DisplayString"
                let access = commaParts.count > 3 ? commaParts[3] : "read-only"
                let desc = commaParts.count > 4 ? commaParts[4] : ""
                results.append(MIBNodeInfo(oid: oid, name: name, syntax: syntax, access: access, description: desc))
            }
        }

        return results
    }
}
