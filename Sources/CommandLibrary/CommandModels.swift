import Foundation
import NetworkCore

public enum VendorOS: String, Sendable, CaseIterable, Identifiable {
    case ciscoIOSXE = "Cisco IOS-XE"
    case ciscoNXOS = "Cisco NX-OS"
    case aristaEOS = "Arista EOS"
    case juniperJunos = "Juniper Junos"

    public var id: String { rawValue }
}

public enum CommandCategory: String, Sendable, CaseIterable, Identifiable {
    case interfaces = "Interfaces"
    case optics = "Optics & Transceivers"
    case routing = "Routing & Protocols"
    case bgp = "BGP"
    case vlan = "VLAN & Trunking"
    case arp = "ARP & MAC"
    case neighbors = "Neighbors (LLDP/CDP)"
    case system = "System & Hardware"

    public var id: String { rawValue }
}

public struct VendorCommand: Hashable, Sendable, Identifiable {
    public let id: String
    public let intent: String
    public let category: CommandCategory
    public let vendor: VendorOS
    public let syntax: String
    public let description: String

    public init(intent: String, category: CommandCategory, vendor: VendorOS, syntax: String, description: String = "") {
        self.id = "\(vendor.rawValue)_\(intent)"
        self.intent = intent
        self.category = category
        self.vendor = vendor
        self.syntax = syntax
        self.description = description
    }
}

public struct CommandDatabase: Sendable {
    public static let shared = CommandDatabase()

    public let commands: [VendorCommand]

    public init() {
        self.commands = [
            // Transceiver Detail
            VendorCommand(intent: "Show Transceiver Diagnostics", category: .optics, vendor: .ciscoIOSXE, syntax: "show interfaces transceiver detail", description: "Displays optical Tx/Rx power, temperature, and bias current."),
            VendorCommand(intent: "Show Transceiver Diagnostics", category: .optics, vendor: .ciscoNXOS, syntax: "show interface ethernet 1/1 transceiver details", description: "Displays DOM optical metrics on NX-OS interfaces."),
            VendorCommand(intent: "Show Transceiver Diagnostics", category: .optics, vendor: .aristaEOS, syntax: "show interfaces transceiver", description: "Displays DOM optical power levels on Arista EOS interfaces."),
            VendorCommand(intent: "Show Transceiver Diagnostics", category: .optics, vendor: .juniperJunos, syntax: "show interfaces diagnostics optics", description: "Displays laser output and optical receiver power."),

            // Interface Status
            VendorCommand(intent: "Show Interface Summary", category: .interfaces, vendor: .ciscoIOSXE, syntax: "show ip interface brief", description: "Summarizes IPv4 address, layer 1 status, and line protocol."),
            VendorCommand(intent: "Show Interface Summary", category: .interfaces, vendor: .ciscoNXOS, syntax: "show ip interface brief", description: "Summarizes IP configuration and VRF bindings."),
            VendorCommand(intent: "Show Interface Summary", category: .interfaces, vendor: .aristaEOS, syntax: "show ip interface brief", description: "Lists interface IP addresses, line status, and MTU."),
            VendorCommand(intent: "Show Interface Summary", category: .interfaces, vendor: .juniperJunos, syntax: "show interfaces terse", description: "Displays interface status and family addresses in terse table."),

            // Interface Errors & Counters
            VendorCommand(intent: "Show Interface Errors", category: .interfaces, vendor: .ciscoIOSXE, syntax: "show interfaces counters errors", description: "Displays CRC, alignment, overrun, and frame errors."),
            VendorCommand(intent: "Show Interface Errors", category: .interfaces, vendor: .ciscoNXOS, syntax: "show interface counters errors", description: "Displays CRC, input error, and discard metrics."),
            VendorCommand(intent: "Show Interface Errors", category: .interfaces, vendor: .aristaEOS, syntax: "show interfaces counters errors", description: "Displays FCS, alignment, and symbol error counts."),
            VendorCommand(intent: "Show Interface Errors", category: .interfaces, vendor: .juniperJunos, syntax: "show interfaces extensive | match error", description: "Extracts interface error statistics."),

            // BGP Summary
            VendorCommand(intent: "Show BGP Summary", category: .bgp, vendor: .ciscoIOSXE, syntax: "show ip bgp summary", description: "Displays state of all BGP neighbors, ASN, and received prefix counts."),
            VendorCommand(intent: "Show BGP Summary", category: .bgp, vendor: .ciscoNXOS, syntax: "show ip bgp summary vrf all", description: "Summarizes BGP peers across all VRFs."),
            VendorCommand(intent: "Show BGP Summary", category: .bgp, vendor: .aristaEOS, syntax: "show ip bgp summary", description: "Lists BGP neighbor states and prefix counts."),
            VendorCommand(intent: "Show BGP Summary", category: .bgp, vendor: .juniperJunos, syntax: "show bgp summary", description: "Displays BGP peering sessions and active RIB counts."),

            // Neighbors (CDP / LLDP)
            VendorCommand(intent: "Show LLDP Neighbors", category: .neighbors, vendor: .ciscoIOSXE, syntax: "show lldp neighbors detail", description: "Discovers adjacent device models, management IPs, and port IDs."),
            VendorCommand(intent: "Show LLDP Neighbors", category: .neighbors, vendor: .ciscoNXOS, syntax: "show lldp neighbors detail", description: "Details LLDP neighbor capabilities and port descriptions."),
            VendorCommand(intent: "Show LLDP Neighbors", category: .neighbors, vendor: .aristaEOS, syntax: "show lldp neighbors detail", description: "Displays LLDP neighbor chassis ID and port IDs."),
            VendorCommand(intent: "Show LLDP Neighbors", category: .neighbors, vendor: .juniperJunos, syntax: "show lldp neighbors", description: "Lists adjacent network switches and routers via LLDP."),

            // MAC Address Table
            VendorCommand(intent: "Show MAC Address Table", category: .arp, vendor: .ciscoIOSXE, syntax: "show mac address-table", description: "Lists learned MAC addresses, VLANs, and egress switchports."),
            VendorCommand(intent: "Show MAC Address Table", category: .arp, vendor: .ciscoNXOS, syntax: "show mac address-table", description: "Displays Layer 2 forwarding table."),
            VendorCommand(intent: "Show MAC Address Table", category: .arp, vendor: .aristaEOS, syntax: "show mac address-table", description: "Displays MAC address forwarding database."),
            VendorCommand(intent: "Show MAC Address Table", category: .arp, vendor: .juniperJunos, syntax: "show ethernet-switching table", description: "Displays bridging MAC address table.")
        ]
    }

    public func search(query: String) -> [VendorCommand] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return commands }
        return commands.filter {
            $0.intent.lowercased().contains(q) ||
            $0.syntax.lowercased().contains(q) ||
            $0.vendor.rawValue.lowercased().contains(q) ||
            $0.category.rawValue.lowercased().contains(q)
        }
    }
}
