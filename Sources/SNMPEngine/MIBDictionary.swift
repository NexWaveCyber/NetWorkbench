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
        trie.insert(oid: "1.3.6.1.2.1.4.20.1.1", name: "ipAdEntAddr", syntax: "IpAddress", description: "IPv4 address corresponding to interface")
    }

    public static let standardNodes: [MIBNodeInfo] = [
        MIBNodeInfo(oid: "1.3.6.1.2.1.1.1", name: "sysDescr", syntax: "DisplayString", access: "read-only", description: "A textual description of the entity. Includes full hardware and OS software version."),
        MIBNodeInfo(oid: "1.3.6.1.2.1.1.2", name: "sysObjectID", syntax: "OBJECT IDENTIFIER", access: "read-only", description: "The vendor's authoritative identification of the network management subsystem."),
        MIBNodeInfo(oid: "1.3.6.1.2.1.1.3", name: "sysUpTime", syntax: "TimeTicks", access: "read-only", description: "The time (in hundredths of a second) since network management was last re-initialized."),
        MIBNodeInfo(oid: "1.3.6.1.2.1.1.4", name: "sysContact", syntax: "DisplayString", access: "read-write", description: "Textual contact person for this managed node and contact instructions."),
        MIBNodeInfo(oid: "1.3.6.1.2.1.1.5", name: "sysName", syntax: "DisplayString", access: "read-write", description: "An administratively-assigned name for this node (typically FQDN)."),
        MIBNodeInfo(oid: "1.3.6.1.2.1.1.6", name: "sysLocation", syntax: "DisplayString", access: "read-write", description: "Physical location of this node (e.g. Data Center, Rack 14B)."),
        MIBNodeInfo(oid: "1.3.6.1.2.1.1.7", name: "sysServices", syntax: "INTEGER", access: "read-only", description: "Indicates the set of services that this entity primarily offers."),
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
        MIBNodeInfo(oid: "1.3.6.1.2.1.31.1.1.1.1", name: "ifName", syntax: "DisplayString", access: "read-only", description: "Textual name of interface (e.g. GigabitEthernet0/1)."),
        MIBNodeInfo(oid: "1.3.6.1.2.1.31.1.1.1.6", name: "ifHCInOctets", syntax: "Counter64", access: "read-only", description: "64-bit high-capacity total octets received."),
        MIBNodeInfo(oid: "1.3.6.1.2.1.31.1.1.1.10", name: "ifHCOutOctets", syntax: "Counter64", access: "read-only", description: "64-bit high-capacity total octets transmitted."),
        MIBNodeInfo(oid: "1.3.6.1.2.1.4.1", name: "ipForwarding", syntax: "INTEGER", access: "read-write", description: "IP gateway packet forwarding enabled flag.")
    ]

    public func resolve(oid: String) -> String {
        trie.resolveName(oid: oid)
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
