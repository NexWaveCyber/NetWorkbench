import Foundation
import NetworkCore

public enum VendorOS: String, Sendable, CaseIterable, Identifiable, Codable {
    case ciscoIOSXE = "Cisco IOS-XE"
    case ciscoNXOS = "Cisco NX-OS"
    case aristaEOS = "Arista EOS"
    case juniperJunos = "Juniper Junos"
    case fortinetFortiOS = "Fortinet FortiOS"
    case mikrotikRouterOS = "MikroTik RouterOS"
    case paloAltoPANOS = "Palo Alto PAN-OS"
    case linuxNet = "Linux (iproute2/nftables)"

    public var id: String { rawValue }

    public var shortBadge: String {
        switch self {
        case .ciscoIOSXE: return "IOS-XE"
        case .ciscoNXOS: return "NX-OS"
        case .aristaEOS: return "EOS"
        case .juniperJunos: return "JUNOS"
        case .fortinetFortiOS: return "FORTIOS"
        case .mikrotikRouterOS: return "ROUTEROS"
        case .paloAltoPANOS: return "PAN-OS"
        case .linuxNet: return "LINUX"
        }
    }
}

public enum CommandCategory: String, Sendable, CaseIterable, Identifiable, Codable {
    case interfaces = "Interfaces & Physical"
    case optics = "Optics & Transceivers"
    case routing = "Routing & Protocols"
    case bgp = "BGP"
    case ospf = "OSPF & IS-IS"
    case vlan = "VLAN & Trunking"
    case arp = "ARP & MAC"
    case neighbors = "Neighbors (LLDP/CDP)"
    case firewall = "Security & Firewalls"
    case system = "System & Hardware"
    case packetCapture = "Packet Capture & SPAN"
    case troubleshooting = "Troubleshooting & Verification"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .interfaces: return "cable.connector"
        case .optics: return "laser.burst"
        case .routing: return "arrow.triangle.swap"
        case .bgp: return "globe.americas.fill"
        case .ospf: return "point.3.connected.trianglepath.dotted"
        case .vlan: return "square.stack.3d.down.right.fill"
        case .arp: return "tablecells"
        case .neighbors: return "antenna.radiowaves.left.and.right"
        case .firewall: return "shield.lefthalf.filled"
        case .system: return "cpu"
        case .packetCapture: return "waveform.path.ecg"
        case .troubleshooting: return "stethoscope"
        }
    }
}

public struct CommandParameter: Hashable, Sendable, Identifiable, Codable {
    public let key: String
    public let label: String
    public let defaultValue: String
    public let placeholder: String
    public let description: String

    public var id: String { key }

    public init(
        key: String,
        label: String,
        defaultValue: String = "",
        placeholder: String = "",
        description: String = ""
    ) {
        self.key = key
        self.label = label
        self.defaultValue = defaultValue
        self.placeholder = placeholder
        self.description = description
    }
}

public struct VendorCommand: Hashable, Sendable, Identifiable, Codable {
    public let id: String
    public let intent: String
    public let category: CommandCategory
    public let vendor: VendorOS
    public let syntax: String
    public let description: String
    public let parameters: [CommandParameter]
    public var isCustom: Bool
    public var isFavorite: Bool

    public init(
        id: String? = nil,
        intent: String,
        category: CommandCategory,
        vendor: VendorOS,
        syntax: String,
        description: String = "",
        parameters: [CommandParameter] = [],
        isCustom: Bool = false,
        isFavorite: Bool = false
    ) {
        self.id = id ?? "\(vendor.rawValue)_\(intent)"
        self.intent = intent
        self.category = category
        self.vendor = vendor
        self.syntax = syntax
        self.description = description
        self.parameters = parameters
        self.isCustom = isCustom
        self.isFavorite = isFavorite
    }

    /// Interpolates parameter placeholders formatted as {{key}} with provided dictionary values or default values.
    public func interpolate(with values: [String: String]) -> String {
        var result = syntax
        for param in parameters {
            let token = "{{\(param.key)}}"
            let val = values[param.key]?.trimmingCharacters(in: .whitespaces)
            let replacement = (val != nil && !val!.isEmpty) ? val! : (param.defaultValue.isEmpty ? "<\(param.key)>" : param.defaultValue)
            result = result.replacingOccurrences(of: token, with: replacement)
        }
        return result
    }
}

public struct CommandDatabase: Sendable {
    public static let shared = CommandDatabase()

    public let commands: [VendorCommand]

    public init() {
        var list: [VendorCommand] = []

        // Helper parameter definitions
        let ifaceParam = CommandParameter(key: "interface", label: "Interface", defaultValue: "GigabitEthernet1/0/1", placeholder: "e.g. eth1/1, ge-0/0/0, GigabitEthernet1/0/1", description: "Target physical or logical port")
        let prefixParam = CommandParameter(key: "prefix", label: "Subnet / Prefix", defaultValue: "10.0.0.0/24", placeholder: "e.g. 192.168.1.0/24", description: "IPv4 or IPv6 CIDR prefix")
        let ipParam = CommandParameter(key: "ip", label: "IP Address", defaultValue: "10.0.0.1", placeholder: "e.g. 192.168.1.1", description: "Target host or peer IP")
        let srcParam = CommandParameter(key: "source", label: "Source IP / Intf", defaultValue: "Loopback0", placeholder: "e.g. 10.255.255.1, eth0", description: "Source address or interface")

        // 1. Show Transceiver Diagnostics (DOM)
        list.append(contentsOf: [
            VendorCommand(intent: "Show Transceiver Diagnostics", category: .optics, vendor: .ciscoIOSXE, syntax: "show interfaces {{interface}} transceiver detail", description: "Displays optical Tx/Rx power, temperature, and bias current with DOM alarms.", parameters: [ifaceParam]),
            VendorCommand(intent: "Show Transceiver Diagnostics", category: .optics, vendor: .ciscoNXOS, syntax: "show interface {{interface}} transceiver details", description: "Displays DOM optical metrics, calibrated Rx power, and lane status.", parameters: [ifaceParam]),
            VendorCommand(intent: "Show Transceiver Diagnostics", category: .optics, vendor: .aristaEOS, syntax: "show interfaces {{interface}} transceiver", description: "Displays DOM optical power levels, laser status, and lane metrics on EOS.", parameters: [ifaceParam]),
            VendorCommand(intent: "Show Transceiver Diagnostics", category: .optics, vendor: .juniperJunos, syntax: "show interfaces diagnostics optics {{interface}}", description: "Displays laser output power, receiver optical power, and high/low alarms.", parameters: [ifaceParam]),
            VendorCommand(intent: "Show Transceiver Diagnostics", category: .optics, vendor: .fortinetFortiOS, syntax: "get hardware nic {{interface}}", description: "Displays PHY media status, SFP transceiver details, and EEPROM telemetry.", parameters: [ifaceParam]),
            VendorCommand(intent: "Show Transceiver Diagnostics", category: .optics, vendor: .mikrotikRouterOS, syntax: "/interface ethernet monitor {{interface}} once", description: "Queries SFP/SFP+ optical Rx/Tx power, temperature, and link rate.", parameters: [ifaceParam]),
            VendorCommand(intent: "Show Transceiver Diagnostics", category: .optics, vendor: .paloAltoPANOS, syntax: "show system state filter-pretty sys.sfp.*", description: "Inspects optical transceiver diagnostics and link status across dataplane ports.", parameters: [ifaceParam]),
            VendorCommand(intent: "Show Transceiver Diagnostics", category: .optics, vendor: .linuxNet, syntax: "ethtool -m {{interface}}", description: "Dumps optical module EEPROM, DOM Rx/Tx powers, and temperature via ethtool.", parameters: [ifaceParam])
        ])

        // 2. Show Interface Summary
        list.append(contentsOf: [
            VendorCommand(intent: "Show Interface Summary", category: .interfaces, vendor: .ciscoIOSXE, syntax: "show ip interface brief", description: "Summarizes IPv4 address, layer 1 status, and line protocol."),
            VendorCommand(intent: "Show Interface Summary", category: .interfaces, vendor: .ciscoNXOS, syntax: "show ip interface brief vrf all", description: "Summarizes IP configuration, VRF bindings, and physical link state."),
            VendorCommand(intent: "Show Interface Summary", category: .interfaces, vendor: .aristaEOS, syntax: "show ip interface brief", description: "Lists interface IP addresses, line status, and MTU settings."),
            VendorCommand(intent: "Show Interface Summary", category: .interfaces, vendor: .juniperJunos, syntax: "show interfaces terse", description: "Displays interface admin/link status and family protocol addresses."),
            VendorCommand(intent: "Show Interface Summary", category: .interfaces, vendor: .fortinetFortiOS, syntax: "get system interface physical", description: "Summarizes physical interface link status, speed, duplex, and MTU."),
            VendorCommand(intent: "Show Interface Summary", category: .interfaces, vendor: .mikrotikRouterOS, syntax: "/ip address print", description: "Lists all IP addresses assigned to physical and logical interfaces."),
            VendorCommand(intent: "Show Interface Summary", category: .interfaces, vendor: .paloAltoPANOS, syntax: "show interface logical", description: "Lists all logical interfaces, zones, assigned IP addresses, and operational status."),
            VendorCommand(intent: "Show Interface Summary", category: .interfaces, vendor: .linuxNet, syntax: "ip -br addr show", description: "Terse multi-column display of interface names, UP/DOWN states, and IPs.")
        ])

        // 3. Show Interface Errors & Discards
        list.append(contentsOf: [
            VendorCommand(intent: "Show Interface Errors", category: .interfaces, vendor: .ciscoIOSXE, syntax: "show interfaces {{interface}} counters errors", description: "Displays CRC, alignment, overrun, and frame error counters.", parameters: [ifaceParam]),
            VendorCommand(intent: "Show Interface Errors", category: .interfaces, vendor: .ciscoNXOS, syntax: "show interface {{interface}} counters errors", description: "Displays CRC, input error, and discard metrics on NX-OS.", parameters: [ifaceParam]),
            VendorCommand(intent: "Show Interface Errors", category: .interfaces, vendor: .aristaEOS, syntax: "show interfaces {{interface}} counters errors", description: "Displays FCS, alignment, symbol error counts, and input discards.", parameters: [ifaceParam]),
            VendorCommand(intent: "Show Interface Errors", category: .interfaces, vendor: .juniperJunos, syntax: "show interfaces {{interface}} extensive | match \"error|drop\"", description: "Extracts CRC errors, input drops, and framing errors.", parameters: [ifaceParam]),
            VendorCommand(intent: "Show Interface Errors", category: .interfaces, vendor: .fortinetFortiOS, syntax: "diagnose netlink interface list name {{interface}}", description: "Outputs low-level kernel driver error counters, drops, and collisions.", parameters: [ifaceParam]),
            VendorCommand(intent: "Show Interface Errors", category: .interfaces, vendor: .mikrotikRouterOS, syntax: "/interface print stats where name=\"{{interface}}\"", description: "Prints transmit/receive packet counts, drops, and CRC errors.", parameters: [ifaceParam]),
            VendorCommand(intent: "Show Interface Errors", category: .interfaces, vendor: .paloAltoPANOS, syntax: "show interface {{interface}} | match \"error|drop\"", description: "Filters interface statistics for errors, drops, and CRC faults.", parameters: [ifaceParam]),
            VendorCommand(intent: "Show Interface Errors", category: .interfaces, vendor: .linuxNet, syntax: "ip -s link show dev {{interface}}", description: "Shows statistics for RX/TX bytes, packets, errors, dropped, and overruns.", parameters: [ifaceParam])
        ])

        // 4. Show IP Routing Table (FIB / RIB)
        list.append(contentsOf: [
            VendorCommand(intent: "Show IP Routing Table", category: .routing, vendor: .ciscoIOSXE, syntax: "show ip route", description: "Displays the global IPv4 routing information base (RIB)."),
            VendorCommand(intent: "Show IP Routing Table", category: .routing, vendor: .ciscoNXOS, syntax: "show ip route vrf all", description: "Displays routes across all VRFs on Cisco NX-OS."),
            VendorCommand(intent: "Show IP Routing Table", category: .routing, vendor: .aristaEOS, syntax: "show ip route", description: "Displays best routes, next hops, and protocol metrics in Arista EOS."),
            VendorCommand(intent: "Show IP Routing Table", category: .routing, vendor: .juniperJunos, syntax: "show route inet.0", description: "Displays the default IPv4 routing table (inet.0)."),
            VendorCommand(intent: "Show IP Routing Table", category: .routing, vendor: .fortinetFortiOS, syntax: "get router info routing-table all", description: "Displays kernel routing table with distance and interface names."),
            VendorCommand(intent: "Show IP Routing Table", category: .routing, vendor: .mikrotikRouterOS, syntax: "/ip route print", description: "Displays active, static, and dynamic routes in RouterOS."),
            VendorCommand(intent: "Show IP Routing Table", category: .routing, vendor: .paloAltoPANOS, syntax: "show routing route", description: "Displays active routing table entries in PAN-OS virtual router."),
            VendorCommand(intent: "Show IP Routing Table", category: .routing, vendor: .linuxNet, syntax: "ip route show", description: "Displays the Linux kernel routing table for the default VRF/namespace.")
        ])

        // 5. Show Route for Specific Prefix
        list.append(contentsOf: [
            VendorCommand(intent: "Show Specific Route", category: .routing, vendor: .ciscoIOSXE, syntax: "show ip route {{prefix}}", description: "Looks up longest-prefix match or exact routing entry.", parameters: [prefixParam]),
            VendorCommand(intent: "Show Specific Route", category: .routing, vendor: .ciscoNXOS, syntax: "show ip route {{prefix}}", description: "Inspects forwarding next-hop and outgoing interface for prefix.", parameters: [prefixParam]),
            VendorCommand(intent: "Show Specific Route", category: .routing, vendor: .aristaEOS, syntax: "show ip route {{prefix}}", description: "Inspects next-hop resolution, ECMP paths, and protocol source.", parameters: [prefixParam]),
            VendorCommand(intent: "Show Specific Route", category: .routing, vendor: .juniperJunos, syntax: "show route {{prefix}}", description: "Displays exact route entry, AS path, and protocol preferences.", parameters: [prefixParam]),
            VendorCommand(intent: "Show Specific Route", category: .routing, vendor: .fortinetFortiOS, syntax: "get router info routing-table exact {{prefix}}", description: "Finds exact routing entry and gateway in FortiOS table.", parameters: [prefixParam]),
            VendorCommand(intent: "Show Specific Route", category: .routing, vendor: .mikrotikRouterOS, syntax: "/ip route print where dst-address in {{prefix}}", description: "Filters routing table for matching destination CIDR.", parameters: [prefixParam]),
            VendorCommand(intent: "Show Specific Route", category: .routing, vendor: .paloAltoPANOS, syntax: "test routing fib-lookup ip {{prefix}}", description: "Tests FIB lookup in PAN-OS dataplane for target prefix.", parameters: [prefixParam]),
            VendorCommand(intent: "Show Specific Route", category: .routing, vendor: .linuxNet, syntax: "ip route get {{prefix}}", description: "Simulates FIB lookup to display outgoing device, source, and gateway.", parameters: [prefixParam])
        ])

        // 6. Show BGP Summary & Peering
        list.append(contentsOf: [
            VendorCommand(intent: "Show BGP Summary", category: .bgp, vendor: .ciscoIOSXE, syntax: "show ip bgp summary", description: "Displays state of all BGP neighbors, ASNs, uptime, and received prefix counts."),
            VendorCommand(intent: "Show BGP Summary", category: .bgp, vendor: .ciscoNXOS, syntax: "show ip bgp summary vrf all", description: "Summarizes BGP peers across all VRF scopes on NX-OS."),
            VendorCommand(intent: "Show BGP Summary", category: .bgp, vendor: .aristaEOS, syntax: "show ip bgp summary", description: "Lists BGP neighbor states, received/advertised prefixes, and router ID."),
            VendorCommand(intent: "Show BGP Summary", category: .bgp, vendor: .juniperJunos, syntax: "show bgp summary", description: "Displays BGP peering sessions, flap counts, and active RIB counts."),
            VendorCommand(intent: "Show BGP Summary", category: .bgp, vendor: .fortinetFortiOS, syntax: "get router info bgp summary", description: "Summarizes BGP neighbor states, local AS, and peer state machine."),
            VendorCommand(intent: "Show BGP Summary", category: .bgp, vendor: .mikrotikRouterOS, syntax: "/routing bgp session print", description: "Lists BGP sessions, remote AS, establish state, and prefix counts."),
            VendorCommand(intent: "Show BGP Summary", category: .bgp, vendor: .paloAltoPANOS, syntax: "show routing protocol bgp summary", description: "Displays summary of BGP peers and state machines in PAN-OS."),
            VendorCommand(intent: "Show BGP Summary", category: .bgp, vendor: .linuxNet, syntax: "vtysh -c \"show ip bgp summary\"", description: "Queries FRRouting / Quagga daemon for BGP peer states and prefix statistics.")
        ])

        // 7. Show BGP Neighbor Detail
        list.append(contentsOf: [
            VendorCommand(intent: "Show BGP Neighbor Detail", category: .bgp, vendor: .ciscoIOSXE, syntax: "show ip bgp neighbors {{ip}}", description: "Inspects hold timers, capabilities, prefix limits, and notification errors.", parameters: [ipParam]),
            VendorCommand(intent: "Show BGP Neighbor Detail", category: .bgp, vendor: .ciscoNXOS, syntax: "show ip bgp neighbors {{ip}} vrf all", description: "Details BGP capabilities, state machine, and error counters.", parameters: [ipParam]),
            VendorCommand(intent: "Show BGP Neighbor Detail", category: .bgp, vendor: .aristaEOS, syntax: "show ip bgp neighbors {{ip}}", description: "Comprehensive BGP session statistics, timers, and TCP connection state.", parameters: [ipParam]),
            VendorCommand(intent: "Show BGP Neighbor Detail", category: .bgp, vendor: .juniperJunos, syntax: "show bgp neighbor {{ip}}", description: "Displays negotiated capabilities, prefix limit, and BGP damping options.", parameters: [ipParam]),
            VendorCommand(intent: "Show BGP Neighbor Detail", category: .bgp, vendor: .fortinetFortiOS, syntax: "get router info bgp neighbors {{ip}}", description: "Inspects BGP neighbor capabilities, timers, and active session counters.", parameters: [ipParam]),
            VendorCommand(intent: "Show BGP Neighbor Detail", category: .bgp, vendor: .mikrotikRouterOS, syntax: "/routing bgp session print detail where remote.address=\"{{ip}}\"", description: "Detailed session diagnostics for specified BGP peer in RouterOS v7.", parameters: [ipParam]),
            VendorCommand(intent: "Show BGP Neighbor Detail", category: .bgp, vendor: .paloAltoPANOS, syntax: "show routing protocol bgp peer peer-name {{ip}}", description: "Inspects BGP peer status, prefix statistics, and flap history.", parameters: [ipParam]),
            VendorCommand(intent: "Show BGP Neighbor Detail", category: .bgp, vendor: .linuxNet, syntax: "vtysh -c \"show ip bgp neighbors {{ip}}\"", description: "Outputs FRR BGP neighbor state, holdtime, and prefix limits.", parameters: [ipParam])
        ])

        // 8. Show OSPF Neighbors
        list.append(contentsOf: [
            VendorCommand(intent: "Show OSPF Neighbors", category: .ospf, vendor: .ciscoIOSXE, syntax: "show ip ospf neighbor", description: "Displays OSPF neighbor router IDs, states (FULL/2WAY), and DR/BDR roles."),
            VendorCommand(intent: "Show OSPF Neighbors", category: .ospf, vendor: .ciscoNXOS, syntax: "show ip ospf neighbors vrf all", description: "Lists OSPF neighbors across all VRFs on NX-OS."),
            VendorCommand(intent: "Show OSPF Neighbors", category: .ospf, vendor: .aristaEOS, syntax: "show ip ospf neighbor", description: "Displays OSPF adjacency states, dead timers, and interface addresses."),
            VendorCommand(intent: "Show OSPF Neighbors", category: .ospf, vendor: .juniperJunos, syntax: "show ospf neighbor", description: "Displays OSPF neighbor adjacency table and interface names."),
            VendorCommand(intent: "Show OSPF Neighbors", category: .ospf, vendor: .fortinetFortiOS, syntax: "get router info ospf neighbor", description: "Lists OSPF neighbor IDs, states, and dead timer countdown."),
            VendorCommand(intent: "Show OSPF Neighbors", category: .ospf, vendor: .mikrotikRouterOS, syntax: "/routing ospf neighbor print", description: "Prints OSPF adjacencies and state machine in RouterOS."),
            VendorCommand(intent: "Show OSPF Neighbors", category: .ospf, vendor: .paloAltoPANOS, syntax: "show routing protocol ospf neighbor", description: "Lists OSPF peers and adjacency states in PAN-OS virtual router."),
            VendorCommand(intent: "Show OSPF Neighbors", category: .ospf, vendor: .linuxNet, syntax: "vtysh -c \"show ip ospf neighbor\"", description: "Queries FRR OSPF daemon for neighbor states and dead timers.")
        ])

        // 9. Show LLDP Neighbors Detail
        list.append(contentsOf: [
            VendorCommand(intent: "Show LLDP Neighbors", category: .neighbors, vendor: .ciscoIOSXE, syntax: "show lldp neighbors detail", description: "Discovers adjacent device models, management IPs, and remote port IDs."),
            VendorCommand(intent: "Show LLDP Neighbors", category: .neighbors, vendor: .ciscoNXOS, syntax: "show lldp neighbors detail", description: "Details LLDP neighbor capabilities, system names, and chassis IDs."),
            VendorCommand(intent: "Show LLDP Neighbors", category: .neighbors, vendor: .aristaEOS, syntax: "show lldp neighbors detail", description: "Displays LLDP neighbor chassis ID, management address, and port descriptions."),
            VendorCommand(intent: "Show LLDP Neighbors", category: .neighbors, vendor: .juniperJunos, syntax: "show lldp neighbors detail", description: "Extracts system name, chassis ID, and port descriptions from LLDP TLVs."),
            VendorCommand(intent: "Show LLDP Neighbors", category: .neighbors, vendor: .fortinetFortiOS, syntax: "diagnose lldp neighbor summary", description: "Summarizes discovered LLDP neighbors on all switchports."),
            VendorCommand(intent: "Show LLDP Neighbors", category: .neighbors, vendor: .mikrotikRouterOS, syntax: "/ip neighbor print detail", description: "Discovers adjacent MikroTik and third-party devices via LLDP/CDP/MNDP."),
            VendorCommand(intent: "Show LLDP Neighbors", category: .neighbors, vendor: .paloAltoPANOS, syntax: "show lldp neighbors all", description: "Displays LLDP neighbor table across all physical ethernet ports."),
            VendorCommand(intent: "Show LLDP Neighbors", category: .neighbors, vendor: .linuxNet, syntax: "lldpctl", description: "Uses lldpd client to display all discovered chassis IDs and port IDs.")
        ])

        // 10. Show MAC Address Table
        list.append(contentsOf: [
            VendorCommand(intent: "Show MAC Address Table", category: .arp, vendor: .ciscoIOSXE, syntax: "show mac address-table", description: "Lists learned MAC addresses, VLANs, and egress switchports."),
            VendorCommand(intent: "Show MAC Address Table", category: .arp, vendor: .ciscoNXOS, syntax: "show mac address-table", description: "Displays Layer 2 forwarding table and dynamic MAC entries."),
            VendorCommand(intent: "Show MAC Address Table", category: .arp, vendor: .aristaEOS, syntax: "show mac address-table", description: "Displays MAC address forwarding database on Arista switches."),
            VendorCommand(intent: "Show MAC Address Table", category: .arp, vendor: .juniperJunos, syntax: "show ethernet-switching table", description: "Displays bridging MAC address table and logical interfaces in Junos."),
            VendorCommand(intent: "Show MAC Address Table", category: .arp, vendor: .fortinetFortiOS, syntax: "diagnose switch mac-address-table list", description: "Lists hardware MAC address table on FortiSwitch ports."),
            VendorCommand(intent: "Show MAC Address Table", category: .arp, vendor: .mikrotikRouterOS, syntax: "/interface bridge host print", description: "Prints bridge forwarding table and learned MAC addresses in RouterOS."),
            VendorCommand(intent: "Show MAC Address Table", category: .arp, vendor: .paloAltoPANOS, syntax: "show mac all", description: "Displays Layer 2 forwarding database on PAN-OS firewall interfaces."),
            VendorCommand(intent: "Show MAC Address Table", category: .arp, vendor: .linuxNet, syntax: "bridge fdb show", description: "Displays the Linux bridge forwarding database (FDB).")
        ])

        // 11. Show ARP / Neighbor Cache
        list.append(contentsOf: [
            VendorCommand(intent: "Show ARP Table", category: .arp, vendor: .ciscoIOSXE, syntax: "show ip arp", description: "Lists IPv4-to-MAC address resolution mappings and aging timers."),
            VendorCommand(intent: "Show ARP Table", category: .arp, vendor: .ciscoNXOS, syntax: "show ip arp vrf all", description: "Displays ARP cache entries across all VRFs."),
            VendorCommand(intent: "Show ARP Table", category: .arp, vendor: .aristaEOS, syntax: "show ip arp", description: "Displays IPv4 ARP cache, interface bindings, and aging."),
            VendorCommand(intent: "Show ARP Table", category: .arp, vendor: .juniperJunos, syntax: "show arp", description: "Displays active ARP entries, MAC addresses, and interface names."),
            VendorCommand(intent: "Show ARP Table", category: .arp, vendor: .fortinetFortiOS, syntax: "get system arp", description: "Lists FortiOS ARP cache with IP, MAC, and physical interface."),
            VendorCommand(intent: "Show ARP Table", category: .arp, vendor: .mikrotikRouterOS, syntax: "/ip arp print", description: "Displays ARP cache table with dynamic and static entries."),
            VendorCommand(intent: "Show ARP Table", category: .arp, vendor: .paloAltoPANOS, syntax: "show arp all", description: "Lists all resolved ARP entries across all PAN-OS dataplane interfaces."),
            VendorCommand(intent: "Show ARP Table", category: .arp, vendor: .linuxNet, syntax: "ip neigh show", description: "Displays IPv4 ARP and IPv6 Neighbor Discovery (ND) cache entries.")
        ])

        // 12. Clear ARP Cache Entry
        list.append(contentsOf: [
            VendorCommand(intent: "Clear ARP Entry", category: .arp, vendor: .ciscoIOSXE, syntax: "clear ip arp {{ip}}", description: "Flushes specific IPv4 ARP entry from forwarding cache.", parameters: [ipParam]),
            VendorCommand(intent: "Clear ARP Entry", category: .arp, vendor: .ciscoNXOS, syntax: "clear ip arp {{ip}} vrf all", description: "Clears ARP cache entry on Cisco NX-OS across all VRFs.", parameters: [ipParam]),
            VendorCommand(intent: "Clear ARP Entry", category: .arp, vendor: .aristaEOS, syntax: "clear ip arp {{ip}}", description: "Removes ARP mapping for specified IP on Arista EOS.", parameters: [ipParam]),
            VendorCommand(intent: "Clear ARP Entry", category: .arp, vendor: .juniperJunos, syntax: "clear arp hostname {{ip}}", description: "Purges specific host ARP binding from Junos ARP table.", parameters: [ipParam]),
            VendorCommand(intent: "Clear ARP Entry", category: .arp, vendor: .fortinetFortiOS, syntax: "execute clear system arp {{ip}}", description: "Clears kernel ARP entry for specified host in FortiOS.", parameters: [ipParam]),
            VendorCommand(intent: "Clear ARP Entry", category: .arp, vendor: .mikrotikRouterOS, syntax: "/ip arp remove [find address=\"{{ip}}\"]", description: "Deletes matching dynamic ARP entry in RouterOS.", parameters: [ipParam]),
            VendorCommand(intent: "Clear ARP Entry", category: .arp, vendor: .paloAltoPANOS, syntax: "clear arp ip {{ip}}", description: "Clears ARP table entry in PAN-OS dataplane.", parameters: [ipParam]),
            VendorCommand(intent: "Clear ARP Entry", category: .arp, vendor: .linuxNet, syntax: "ip neigh del {{ip}} dev {{interface}}", description: "Deletes neighbor ARP/ND cache entry on specified interface.", parameters: [ipParam, ifaceParam])
        ])

        // 13. Show VLAN Configuration
        list.append(contentsOf: [
            VendorCommand(intent: "Show VLAN Configuration", category: .vlan, vendor: .ciscoIOSXE, syntax: "show vlan brief", description: "Displays VLAN IDs, names, status, and assigned switchports."),
            VendorCommand(intent: "Show VLAN Configuration", category: .vlan, vendor: .ciscoNXOS, syntax: "show vlan", description: "Displays VLAN database, names, and operational status."),
            VendorCommand(intent: "Show VLAN Configuration", category: .vlan, vendor: .aristaEOS, syntax: "show vlan", description: "Lists configured VLANs and port memberships."),
            VendorCommand(intent: "Show VLAN Configuration", category: .vlan, vendor: .juniperJunos, syntax: "show vlans", description: "Lists configured VLANs, tags, and associated interface names."),
            VendorCommand(intent: "Show VLAN Configuration", category: .vlan, vendor: .fortinetFortiOS, syntax: "get system interface | grep vlan", description: "Filters FortiOS interfaces for configured VLAN IDs and parent ports."),
            VendorCommand(intent: "Show VLAN Configuration", category: .vlan, vendor: .mikrotikRouterOS, syntax: "/interface bridge vlan print", description: "Displays bridge VLAN filtering entries, tagged, and untagged ports."),
            VendorCommand(intent: "Show VLAN Configuration", category: .vlan, vendor: .paloAltoPANOS, syntax: "show interface logical", description: "Displays subinterfaces and 802.1Q VLAN tags in PAN-OS."),
            VendorCommand(intent: "Show VLAN Configuration", category: .vlan, vendor: .linuxNet, syntax: "bridge vlan show", description: "Lists VLAN IDs associated with bridge ports on Linux.")
        ])

        // 14. Show System CPU & Memory Utilization
        list.append(contentsOf: [
            VendorCommand(intent: "Show System Resources", category: .system, vendor: .ciscoIOSXE, syntax: "show processes cpu sorted | exclude 0.00", description: "Displays top CPU consuming processes and memory usage."),
            VendorCommand(intent: "Show System Resources", category: .system, vendor: .ciscoNXOS, syntax: "show system resources", description: "Displays CPU utilization per core, memory usage, and load averages."),
            VendorCommand(intent: "Show System Resources", category: .system, vendor: .aristaEOS, syntax: "show processes top once", description: "Captures instantaneous snapshot of top CPU and memory consumers."),
            VendorCommand(intent: "Show System Resources", category: .system, vendor: .juniperJunos, syntax: "show system processes extensive", description: "Top-like snapshot of Routing Engine CPU and memory allocation."),
            VendorCommand(intent: "Show System Resources", category: .system, vendor: .fortinetFortiOS, syntax: "get system performance status", description: "Displays CPU core utilization, memory %, and network throughput."),
            VendorCommand(intent: "Show System Resources", category: .system, vendor: .mikrotikRouterOS, syntax: "/system resource print", description: "Prints uptime, CPU load %, free memory, and architecture in RouterOS."),
            VendorCommand(intent: "Show System Resources", category: .system, vendor: .paloAltoPANOS, syntax: "show system resources", description: "Displays management plane and dataplane CPU/memory consumption."),
            VendorCommand(intent: "Show System Resources", category: .system, vendor: .linuxNet, syntax: "top -b -n 1 | head -n 20", description: "Captures top 20 processes by CPU and memory on Linux.")
        ])

        // 15. Show Environment (Power Supplies & Fans)
        list.append(contentsOf: [
            VendorCommand(intent: "Show Environment Health", category: .system, vendor: .ciscoIOSXE, syntax: "show environment all", description: "Displays power supply status, fan speeds, and internal temperatures."),
            VendorCommand(intent: "Show Environment Health", category: .system, vendor: .ciscoNXOS, syntax: "show environment", description: "Comprehensive telemetry of chassis fans, PSUs, and thermal sensors."),
            VendorCommand(intent: "Show Environment Health", category: .system, vendor: .aristaEOS, syntax: "show environment all", description: "Displays fan trays, power consumption, and thermal zones on Arista."),
            VendorCommand(intent: "Show Environment Health", category: .system, vendor: .juniperJunos, syntax: "show chassis environment", description: "Displays chassis fans, power supplies, and temperature thresholds."),
            VendorCommand(intent: "Show Environment Health", category: .system, vendor: .fortinetFortiOS, syntax: "execute sensor list", description: "Queries hardware sensors for PSU voltage, fan RPM, and thermal status."),
            VendorCommand(intent: "Show Environment Health", category: .system, vendor: .mikrotikRouterOS, syntax: "/system health print", description: "Prints board temperature, voltage, and fan status in RouterOS."),
            VendorCommand(intent: "Show Environment Health", category: .system, vendor: .paloAltoPANOS, syntax: "show system state filter-pretty env.*", description: "Queries environmental sensor metrics in PAN-OS hardware."),
            VendorCommand(intent: "Show Environment Health", category: .system, vendor: .linuxNet, syntax: "sensors", description: "Reads LM-sensors data for CPU cores, fan speeds, and voltages.")
        ])

        // 16. Show Firewall Session Table / Active Connections
        list.append(contentsOf: [
            VendorCommand(intent: "Show Active Connections", category: .firewall, vendor: .ciscoIOSXE, syntax: "show conn count", description: "Displays active stateful inspection connections on IOS-XE firewall."),
            VendorCommand(intent: "Show Active Connections", category: .firewall, vendor: .ciscoNXOS, syntax: "show hardware rate-limiters", description: "Displays CoPP hardware rate-limiters and active dropped packets."),
            VendorCommand(intent: "Show Active Connections", category: .firewall, vendor: .aristaEOS, syntax: "show flow tracking", description: "Displays active telemetry flow tracking tables."),
            VendorCommand(intent: "Show Active Connections", category: .firewall, vendor: .juniperJunos, syntax: "show security flow session summary", description: "Displays active SRX firewall session counts and protocol distributions."),
            VendorCommand(intent: "Show Active Connections", category: .firewall, vendor: .fortinetFortiOS, syntax: "diagnose sys session full-stat", description: "Displays active state table session metrics, TCP states, and NAT flows."),
            VendorCommand(intent: "Show Active Connections", category: .firewall, vendor: .mikrotikRouterOS, syntax: "/ip firewall connection print count-only", description: "Counts active stateful connection tracking entries in RouterOS."),
            VendorCommand(intent: "Show Active Connections", category: .firewall, vendor: .paloAltoPANOS, syntax: "show session info", description: "Displays active session count, maximum throughput, and packet rate."),
            VendorCommand(intent: "Show Active Connections", category: .firewall, vendor: .linuxNet, syntax: "conntrack -S", description: "Outputs conntrack subsystem statistics and active flow counts.")
        ])

        // 17. Live Packet Capture / SPAN
        list.append(contentsOf: [
            VendorCommand(intent: "Live Packet Capture", category: .packetCapture, vendor: .ciscoIOSXE, syntax: "monitor capture CAP interface {{interface}} both start", description: "Starts embedded packet capture (EPC) buffer on interface.", parameters: [ifaceParam]),
            VendorCommand(intent: "Live Packet Capture", category: .packetCapture, vendor: .ciscoNXOS, syntax: "ethanalyzer local interface inband limit-captured-frames 50", description: "Captures control-plane packets directly to terminal on NX-OS."),
            VendorCommand(intent: "Live Packet Capture", category: .packetCapture, vendor: .aristaEOS, syntax: "tcpdump interface {{interface}} -c 50", description: "Runs native tcpdump on physical or management interface in EOS.", parameters: [ifaceParam]),
            VendorCommand(intent: "Live Packet Capture", category: .packetCapture, vendor: .juniperJunos, syntax: "monitor traffic interface {{interface}} count 50", description: "Captures packets on transit or management interface in Junos.", parameters: [ifaceParam]),
            VendorCommand(intent: "Live Packet Capture", category: .packetCapture, vendor: .fortinetFortiOS, syntax: "diagnose sniffer packet {{interface}} 'none' 4 50", description: "Runs high-speed packet sniffer with payload dump on FortiOS.", parameters: [ifaceParam]),
            VendorCommand(intent: "Live Packet Capture", category: .packetCapture, vendor: .mikrotikRouterOS, syntax: "/tool sniffer quick interface={{interface}}", description: "Captures packet headers live to terminal in RouterOS.", parameters: [ifaceParam]),
            VendorCommand(intent: "Live Packet Capture", category: .packetCapture, vendor: .paloAltoPANOS, syntax: "debug dataplane packet-diag show setting", description: "Displays configured packet filter and capture settings on dataplane."),
            VendorCommand(intent: "Live Packet Capture", category: .packetCapture, vendor: .linuxNet, syntax: "tcpdump -i {{interface}} -nn -c 50", description: "Runs tcpdump on Linux interface without DNS resolution for 50 packets.", parameters: [ifaceParam])
        ])

        // 18. Test Ping with Source Address
        list.append(contentsOf: [
            VendorCommand(intent: "Ping with Source", category: .troubleshooting, vendor: .ciscoIOSXE, syntax: "ping {{ip}} source {{source}} repeat 5", description: "Sends ICMP echo requests originating from specific IP or loopback.", parameters: [ipParam, srcParam]),
            VendorCommand(intent: "Ping with Source", category: .troubleshooting, vendor: .ciscoNXOS, syntax: "ping {{ip}} source {{source}} count 5", description: "Sends ICMP pings using specified source address on NX-OS.", parameters: [ipParam, srcParam]),
            VendorCommand(intent: "Ping with Source", category: .troubleshooting, vendor: .aristaEOS, syntax: "ping {{ip}} source {{source}} repeat 5", description: "Sends ICMP ping originating from specified interface or address.", parameters: [ipParam, srcParam]),
            VendorCommand(intent: "Ping with Source", category: .troubleshooting, vendor: .juniperJunos, syntax: "ping {{ip}} source {{source}} count 5", description: "Pings destination with specified source IP in Junos.", parameters: [ipParam, srcParam]),
            VendorCommand(intent: "Ping with Source", category: .troubleshooting, vendor: .fortinetFortiOS, syntax: "execute ping-options source {{source}}; execute ping {{ip}}", description: "Configures source ping options and fires ICMP probe in FortiOS.", parameters: [srcParam, ipParam]),
            VendorCommand(intent: "Ping with Source", category: .troubleshooting, vendor: .mikrotikRouterOS, syntax: "/ping {{ip}} src-address={{source}} count=5", description: "Sends 5 ping requests from designated source IP in RouterOS.", parameters: [ipParam, srcParam]),
            VendorCommand(intent: "Ping with Source", category: .troubleshooting, vendor: .paloAltoPANOS, syntax: "ping source {{source}} host {{ip}} count 5", description: "Sends ICMP pings from specified dataplane or management IP in PAN-OS.", parameters: [srcParam, ipParam]),
            VendorCommand(intent: "Ping with Source", category: .troubleshooting, vendor: .linuxNet, syntax: "ping -I {{source}} -c 5 {{ip}}", description: "Sends 5 ICMP echo packets bound to specific source interface or IP.", parameters: [srcParam, ipParam])
        ])

        // 19. Traceroute with Source Address
        list.append(contentsOf: [
            VendorCommand(intent: "Traceroute with Source", category: .troubleshooting, vendor: .ciscoIOSXE, syntax: "traceroute {{ip}} source {{source}}", description: "Traces hop-by-hop path using specific source address.", parameters: [ipParam, srcParam]),
            VendorCommand(intent: "Traceroute with Source", category: .troubleshooting, vendor: .ciscoNXOS, syntax: "traceroute {{ip}} source {{source}}", description: "Performs layer 3 traceroute originating from specific interface.", parameters: [ipParam, srcParam]),
            VendorCommand(intent: "Traceroute with Source", category: .troubleshooting, vendor: .aristaEOS, syntax: "traceroute {{ip}} source {{source}}", description: "Traceroute with custom source on Arista EOS.", parameters: [ipParam, srcParam]),
            VendorCommand(intent: "Traceroute with Source", category: .troubleshooting, vendor: .juniperJunos, syntax: "traceroute {{ip}} source {{source}}", description: "Hop-by-hop path probe with custom source in Junos.", parameters: [ipParam, srcParam]),
            VendorCommand(intent: "Traceroute with Source", category: .troubleshooting, vendor: .fortinetFortiOS, syntax: "execute traceroute {{ip}}", description: "Executes layer 3 traceroute to target host in FortiOS.", parameters: [ipParam]),
            VendorCommand(intent: "Traceroute with Source", category: .troubleshooting, vendor: .mikrotikRouterOS, syntax: "/tool traceroute {{ip}} src-address={{source}}", description: "Traceroute originating from specified source in RouterOS.", parameters: [ipParam, srcParam]),
            VendorCommand(intent: "Traceroute with Source", category: .troubleshooting, vendor: .paloAltoPANOS, syntax: "traceroute source {{source}} host {{ip}}", description: "Performs traceroute with specified source interface in PAN-OS.", parameters: [srcParam, ipParam]),
            VendorCommand(intent: "Traceroute with Source", category: .troubleshooting, vendor: .linuxNet, syntax: "traceroute -s {{source}} {{ip}}", description: "Traces path with specified source IP using Linux traceroute.", parameters: [srcParam, ipParam])
        ])

        // 20. Show NTP Status & Associations
        list.append(contentsOf: [
            VendorCommand(intent: "Show NTP Status", category: .system, vendor: .ciscoIOSXE, syntax: "show ntp associations", description: "Displays configured NTP servers, stratum, offset, and sync state."),
            VendorCommand(intent: "Show NTP Status", category: .system, vendor: .ciscoNXOS, syntax: "show ntp peer-status", description: "Displays NTP synchronization status and peer dispersion on NX-OS."),
            VendorCommand(intent: "Show NTP Status", category: .system, vendor: .aristaEOS, syntax: "show ntp associations", description: "Lists NTP servers, jitter, delay, and synchronization status."),
            VendorCommand(intent: "Show NTP Status", category: .system, vendor: .juniperJunos, syntax: "show ntp associations", description: "Lists active NTP peers, stratum levels, and offsets in Junos."),
            VendorCommand(intent: "Show NTP Status", category: .system, vendor: .fortinetFortiOS, syntax: "diagnose sys ntp status", description: "Queries FortiOS NTP synchronization, server reachable status, and stratum."),
            VendorCommand(intent: "Show NTP Status", category: .system, vendor: .mikrotikRouterOS, syntax: "/system ntp client print", description: "Displays NTP client status, active server IP, and time offset."),
            VendorCommand(intent: "Show NTP Status", category: .system, vendor: .paloAltoPANOS, syntax: "show ntp", description: "Displays NTP server addresses and sync status in PAN-OS."),
            VendorCommand(intent: "Show NTP Status", category: .system, vendor: .linuxNet, syntax: "chronyc sources -v", description: "Displays detailed chrony NTP source states, stratum, and offsets.")
        ])

        // 21. Save Configuration to Non-Volatile Memory
        list.append(contentsOf: [
            VendorCommand(intent: "Save Running Configuration", category: .system, vendor: .ciscoIOSXE, syntax: "write memory", description: "Commits running config to NVRAM startup-config."),
            VendorCommand(intent: "Save Running Configuration", category: .system, vendor: .ciscoNXOS, syntax: "copy running-config startup-config", description: "Copies active running config to persistent startup config."),
            VendorCommand(intent: "Save Running Configuration", category: .system, vendor: .aristaEOS, syntax: "write memory", description: "Saves running configuration to startup-config in EOS."),
            VendorCommand(intent: "Save Running Configuration", category: .system, vendor: .juniperJunos, syntax: "commit and-quit", description: "Commits candidate configuration changes to active database in Junos."),
            VendorCommand(intent: "Save Running Configuration", category: .system, vendor: .fortinetFortiOS, syntax: "execute backup config flash", description: "Backs up configuration to internal flash memory in FortiOS."),
            VendorCommand(intent: "Save Running Configuration", category: .system, vendor: .mikrotikRouterOS, syntax: "/system backup save name=nexwave_backup", description: "Creates full configuration backup file in RouterOS."),
            VendorCommand(intent: "Save Running Configuration", category: .system, vendor: .paloAltoPANOS, syntax: "commit", description: "Commits candidate configuration changes to running-config in PAN-OS."),
            VendorCommand(intent: "Save Running Configuration", category: .system, vendor: .linuxNet, syntax: "netplan apply", description: "Applies and persists network configuration on Linux netplan systems.")
        ])

        self.commands = list
    }

    public func search(query: String) -> [VendorCommand] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return commands }
        return commands.filter {
            $0.intent.lowercased().contains(q) ||
            $0.syntax.lowercased().contains(q) ||
            $0.vendor.rawValue.lowercased().contains(q) ||
            $0.category.rawValue.lowercased().contains(q) ||
            $0.description.lowercased().contains(q)
        }
    }

    /// Retrieves all unique operational intents supported in the database
    public var allIntents: [String] {
        Array(Set(commands.map { $0.intent })).sorted()
    }

    /// Generates a Multi-Vendor Rosetta Stone mapping for a specific operational intent
    public func rosettaStone(forIntent intent: String) -> [VendorOS: VendorCommand] {
        let matching = commands.filter { $0.intent.caseInsensitiveCompare(intent) == .orderedSame }
        var result: [VendorOS: VendorCommand] = [:]
        for cmd in matching {
            result[cmd.vendor] = cmd
        }
        return result
    }

    /// Exports database to a formatted Markdown Cheatsheet
    public func exportMarkdown(vendorFilter: VendorOS? = nil, categoryFilter: CommandCategory? = nil) -> String {
        var out = "# NexWave Network Operations Command Library Cheatsheet\n\n"
        out += "Generated: \(Date())\n\n"

        let targetCommands = commands.filter { cmd in
            if let vf = vendorFilter, cmd.vendor != vf { return false }
            if let cf = categoryFilter, cmd.category != cf { return false }
            return true
        }

        let grouped = Dictionary(grouping: targetCommands, by: { $0.category })
        for cat in CommandCategory.allCases {
            guard let cmds = grouped[cat], !cmds.isEmpty else { continue }
            out += "## \(cat.rawValue)\n\n"
            out += "| Operational Intent | Vendor OS | Syntax | Description |\n"
            out += "| :--- | :--- | :--- | :--- |\n"
            for c in cmds {
                out += "| **\(c.intent)** | `\(c.vendor.shortBadge)` | `\(c.syntax)` | \(c.description) |\n"
            }
            out += "\n"
        }
        return out
    }

    /// Exports commands as CSV
    public func exportCSV(vendorFilter: VendorOS? = nil) -> String {
        var csv = "Intent,Category,Vendor,Syntax,Description\n"
        let filtered = commands.filter { vendorFilter == nil || $0.vendor == vendorFilter }
        for c in filtered {
            let cleanIntent = c.intent.replacingOccurrences(of: "\"", with: "\"\"")
            let cleanCat = c.category.rawValue.replacingOccurrences(of: "\"", with: "\"\"")
            let cleanVendor = c.vendor.rawValue.replacingOccurrences(of: "\"", with: "\"\"")
            let cleanSyntax = c.syntax.replacingOccurrences(of: "\"", with: "\"\"")
            let cleanDesc = c.description.replacingOccurrences(of: "\"", with: "\"\"")
            csv += "\"\(cleanIntent)\",\"\(cleanCat)\",\"\(cleanVendor)\",\"\(cleanSyntax)\",\"\(cleanDesc)\"\n"
        }
        return csv
    }
}
