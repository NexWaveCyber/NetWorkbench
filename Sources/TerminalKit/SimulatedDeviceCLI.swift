import Foundation

/// Supported simulated network appliance operating system personalities
public enum SimulatedVendor: String, Sendable, CaseIterable, Identifiable, Codable {
    case ciscoIOSXE = "Cisco IOS-XE (Catalyst 9300)"
    case aristaEOS = "Arista EOS (7050X Spine)"
    case juniperJunos = "Juniper Junos (EX4300)"

    public var id: String { rawValue }

    public static func from(presetName: String) -> SimulatedVendor {
        let lower = presetName.lowercased()
        if lower.contains("arista") || lower.contains("eos") {
            return .aristaEOS
        } else if lower.contains("juniper") || lower.contains("junos") || lower.contains("ex4300") {
            return .juniperJunos
        }
        return .ciscoIOSXE
    }
}

/// Interactive simulated network operating system providing multi-vendor CLI interaction,
/// mode transitions, authentic prompt banners, and context-sensitive help.
public final class SimulatedDeviceCLI: @unchecked Sendable {
    public let hostname: String
    public let vendor: SimulatedVendor
    private var isConfigMode: Bool = false
    private var subConfigContext: String = ""
    public var onOutput: ((String) -> Void)?

    public init(hostname: String? = nil, vendor: SimulatedVendor = .ciscoIOSXE) {
        self.vendor = vendor
        if let h = hostname, !h.isEmpty {
            self.hostname = h
        } else {
            switch vendor {
            case .ciscoIOSXE: self.hostname = "nexwave-cat9300-core01"
            case .aristaEOS:   self.hostname = "nexwave-eos7050-spine01"
            case .juniperJunos: self.hostname = "nexwave-junos4300-dist01"
            }
        }
    }

    public convenience init(hostname: String = "nexwave-core01", vendor: String) {
        let detected = SimulatedVendor.from(presetName: vendor)
        self.init(hostname: hostname, vendor: detected)
    }

    public convenience init(hostname: String = "nexwave-core01", presetName: String) {
        let detected = SimulatedVendor.from(presetName: presetName)
        self.init(hostname: hostname, vendor: detected)
    }

    public var currentPrompt: String {
        switch vendor {
        case .ciscoIOSXE:
            if isConfigMode {
                return subConfigContext.isEmpty ? "\(hostname)(config)# " : "\(hostname)(config-\(subConfigContext))# "
            }
            return "\(hostname)# "

        case .aristaEOS:
            if isConfigMode {
                return "\(hostname)(config)# "
            }
            return "\(hostname)# "

        case .juniperJunos:
            if isConfigMode {
                let hierarchy = subConfigContext.isEmpty ? "[edit]" : "[edit \(subConfigContext)]"
                return "\(hierarchy)\nadmin@\(hostname)# "
            }
            return "admin@\(hostname)> "
        }
    }

    public func start() {
        let banner: String
        switch vendor {
        case .ciscoIOSXE:
            banner = """
            
            \u{1B}[1;36m*-------------------------------------------------------------------*
            * NexWave Network Workbench - Cisco IOS-XE Simulation Engine        *
            * Platform: Catalyst 9300-48UXM (Cisco IOS-XE 17.9.4a)             *
            * Hostname: \(hostname)                                          *
            *-------------------------------------------------------------------*\u{1B}[0m
            
            User Access Verification
            Username: admin
            Password: [authenticated via Keychain]
            Last login: Today from 10.100.1.50
            
            \(currentPrompt)
            """

        case .aristaEOS:
            banner = """
            
            \u{1B}[1;34m*-------------------------------------------------------------------*
            * NexWave Network Workbench - Arista EOS Spine Simulation Engine    *
            * Platform: Arista DCS-7050SX3-48YC8 (EOS Version 4.29.2F)          *
            * Hostname: \(hostname)                                          *
            *-------------------------------------------------------------------*\u{1B}[0m
            
            Arista Networks EOS - High Density 100G/25G Spine Switch
            admin@\(hostname)'s password: [verified]
            Last login: Today from 10.100.1.50 on pts/1
            
            \(currentPrompt)
            """

        case .juniperJunos:
            banner = """
            
            \u{1B}[1;35m*-------------------------------------------------------------------*
            * NexWave Network Workbench - Juniper Junos Simulation Engine       *
            * Platform: Juniper Networks EX4300-48T (Junos OS 22.4R1.10)        *
            * Hostname: \(hostname)                                          *
            *-------------------------------------------------------------------*\u{1B}[0m
            
            --- JUNOS 22.4R1.10 built 2023-03-24 07:15:32 UTC ---
            Last login: Today from 10.100.1.50
            
            \(currentPrompt)
            """
        }

        onOutput?(banner)
    }

    public func processInput(_ rawInput: String) {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            onOutput?("\n\(currentPrompt)")
            return
        }

        let cmd = trimmed.lowercased()
        var response = ""

        switch vendor {
        case .ciscoIOSXE:
            response = processCisco(cmd: cmd, raw: trimmed)
        case .aristaEOS:
            response = processArista(cmd: cmd, raw: trimmed)
        case .juniperJunos:
            response = processJunos(cmd: cmd, raw: trimmed)
        }

        let outputBlock = response.isEmpty ? "\n\(currentPrompt)" : "\n\(response)\n\(currentPrompt)"
        onOutput?(outputBlock)
    }

    // MARK: - Cisco IOS-XE Engine

    private func processCisco(cmd: String, raw: String) -> String {
        if cmd == "help" || cmd == "?" {
            return """
            Exec commands:
              show <...>            Show running system information
              ping <ip>             Send ICMP echo request
              traceroute <ip>       Trace route to destination
              configure terminal    Enter global configuration mode
              write memory          Save running configuration to NVRAM
              reload                Halt and perform a cold restart
              exit                  Exit current CLI mode or close session
            """
        }

        if isConfigMode {
            if cmd == "exit" {
                if !subConfigContext.isEmpty {
                    subConfigContext = ""
                    return ""
                }
                isConfigMode = false
                return ""
            } else if cmd == "end" {
                isConfigMode = false
                subConfigContext = ""
                return ""
            } else if cmd.hasPrefix("interface ") || cmd.hasPrefix("int ") {
                let parts = cmd.components(separatedBy: " ")
                subConfigContext = parts.count > 1 ? "if" : ""
                return ""
            } else if cmd.hasPrefix("router ") {
                subConfigContext = "router"
                return ""
            } else if cmd.hasPrefix("ip address ") || cmd.hasPrefix("ip addr ") {
                return ""
            } else if cmd == "no shutdown" || cmd == "no shut" {
                return "%LINK-3-UPDOWN: Interface GigabitEthernet1/0/1, changed state to up\n%LINEPROTO-5-UPDOWN: Line protocol on Interface GigabitEthernet1/0/1, changed state to up"
            } else if cmd.hasPrefix("hostname ") {
                return ""
            } else {
                return "% Invalid configuration command or unrecognized keyword."
            }
        }

        // Privileged Exec Mode
        if cmd == "configure terminal" || cmd == "conf t" {
            isConfigMode = true
            subConfigContext = ""
            return "Enter configuration commands, one per line. End with CNTL/Z."
        } else if cmd.hasPrefix("show ip int") || cmd == "sh ip int br" || cmd == "show ip interface brief" {
            return """
            Interface              IP-Address      OK? Method Status                Protocol
            GigabitEthernet1/0/1   10.10.10.1      YES NVRAM  up                    up      
            GigabitEthernet1/0/2   10.10.20.1      YES NVRAM  up                    up      
            GigabitEthernet1/0/3   172.16.1.1      YES manual up                    up      
            GigabitEthernet1/0/4   unassigned      YES unset  down                  down    
            TenGigabitEthernet1/1/1 192.168.100.1   YES NVRAM  up                    up      
            TenGigabitEthernet1/1/2 unassigned      YES unset  administratively down down    
            Loopback0              10.255.255.1    YES NVRAM  up                    up      
            Vlan10                 10.10.10.254    YES NVRAM  up                    up      
            Vlan20                 10.10.20.254    YES NVRAM  up                    up      
            """
        } else if cmd.hasPrefix("show ver") {
            return """
            Cisco IOS XE Software, Version 17.09.04a
            Cisco IOS Software [Cupertino], Catalyst L3 Switch Software (CAT9K_IOSXE), Version 17.9.4a, RELEASE SOFTWARE (fc2)
            Compiled Fri 15-Sep-23 04:12 by mcpre

            System uptime is 42 weeks, 3 days, 14 hours, 28 minutes
            System returned to ROM by reload
            System image file is "bootflash:packages.conf"
            cisco C9300-48UXM (X86) processor with 16777216K bytes of physical memory.
            System Serial Number: FOC2341L0R9
            """
        } else if cmd.hasPrefix("show cdp nei") || cmd.hasPrefix("show lldp nei") {
            return """
            Capability Codes: R - Router, T - Trans Bridge, B - Source Route Bridge, S - Switch
            Device ID        Local Intrfce     Holdtme    Capability  Platform  Port ID
            dist-sw01.nexwave Gig 1/0/1        142              S I   WS-C3850  Gig 1/0/48
            dist-sw02.nexwave Gig 1/0/2        138              S I   WS-C3850  Gig 1/0/48
            edge-ap-3f.nex    Gig 1/0/12       165             r T P  C9130AXI  Eth 0
            core-spine01      Te 1/1/1         124            R S I   N9K-C9336 Eth 1/1
            """
        } else if cmd.hasPrefix("show run") || cmd == "sh run" {
            return """
            Building configuration...
            Current configuration : 2842 bytes
            !
            version 17.9
            hostname \(hostname)
            !
            spanning-tree mode rapid-pvst
            !
            interface Loopback0
             ip address 10.255.255.1 255.255.255.255
            !
            interface TenGigabitEthernet1/1/1
             description UPLINK-TO-CORE-SPINE01
             no switchport
             ip address 192.168.100.1 255.255.255.252
             ip ospf 1 area 0
            !
            router ospf 1
             router-id 10.255.255.1
             passive-interface default
             no passive-interface TenGigabitEthernet1/1/1
            !
            end
            """
        } else if cmd.hasPrefix("show mac") {
            return """
                      Mac Address Table
            -------------------------------------------
            Vlan    Mac Address       Type        Ports
            ----    -----------       --------    -----
              10    001b.d4c2.8801    DYNAMIC     Gi1/0/1
              10    de06.f4f1.6e35    DYNAMIC     Gi1/0/5
              20    000c.29fa.1189    DYNAMIC     Gi1/0/12
              20    b827.eb99.0123    DYNAMIC     Gi1/0/14
            Total Mac Addresses for this criterion: 4
            """
        } else if cmd.hasPrefix("show ip route") {
            return """
            Codes: L - local, C - connected, S - static, R - RIP, O - OSPF, B - BGP
            Gateway of last resort is 192.168.100.2 to network 0.0.0.0

            O*E2  0.0.0.0/0 [110/1] via 192.168.100.2, 3w2d, TenGigabitEthernet1/1/1
            C        10.10.10.0/24 is directly connected, GigabitEthernet1/0/1
            C        10.10.20.0/24 is directly connected, GigabitEthernet1/0/2
            C        10.255.255.1/32 is directly connected, Loopback0
            """
        } else if cmd.hasPrefix("show ip bgp") {
            return """
            BGP table version is 14, local router ID is 10.255.255.1
            Neighbor        V     AS MsgRcvd MsgSent   TblVer  InQ OutQ Up/Down  State/PfxRcd
            192.168.100.2   4  65001   14281   14282       14    0    0 03:14:22       12
            """
        } else if cmd.hasPrefix("ping ") {
            let target = cmd.replacingOccurrences(of: "ping ", with: "").trimmingCharacters(in: .whitespaces)
            return """
            Sending 5, 100-byte ICMP Echos to \(target), timeout is 2 seconds:
            !!!!!
            Success rate is 100 percent (5/5), round-trip min/avg/max = 1/2/4 ms
            """
        } else if cmd == "write memory" || cmd == "wr" || cmd == "copy run start" {
            return "Building configuration...\n[OK]"
        } else if cmd == "exit" || cmd == "quit" {
            return "\n[Session terminated by user]"
        } else {
            return "% Invalid input detected at '^' marker.\n             ^\nType '?' or 'help' for supported commands."
        }
    }

    // MARK: - Arista EOS Engine

    private func processArista(cmd: String, raw: String) -> String {
        let isJSON = cmd.contains("| json") || cmd.contains("|json")

        if cmd == "help" || cmd == "?" {
            return """
            Available commands:
              show interfaces status     Display status and duplex of all ports
              show ip route summary      Show summary of active IP routes
              show lldp neighbors        Display connected LLDP devices
              show running-config diff   Display uncommitted configuration changes
              show version               Display EOS release and hardware
              enable                     Enter privileged mode
              configure                  Enter configuration mode
              exit                       Exit current mode
            """
        }

        if isConfigMode {
            if cmd == "exit" || cmd == "end" {
                isConfigMode = false
                return ""
            }
            return "% Invalid configuration command."
        }

        if cmd == "configure" || cmd == "conf" || cmd == "conf t" {
            isConfigMode = true
            return ""
        } else if cmd.hasPrefix("show int status") || cmd.hasPrefix("show interfaces status") {
            if isJSON {
                return """
                {
                  "interfaceStatuses": {
                    "Ethernet1/1": { "linkStatus": "connected", "speed": "25Gbps", "vlanId": 100 },
                    "Ethernet2/1": { "linkStatus": "connected", "speed": "100Gbps", "vlanId": "trunk" },
                    "Management1": { "linkStatus": "connected", "speed": "1Gbps", "vlanId": "mgmt" }
                  }
                }
                """
            }
            return """
            Port       Name           Status       Vlan     Duplex Speed   Type
            Et1/1      LEAF-01-UPLINK connected    100      full   25G     25GBASE-CR
            Et1/2      LEAF-02-UPLINK connected    100      full   25G     25GBASE-CR
            Et2/1      SPINE-PEER-1   connected    trunk    full   100G    100GBASE-CR4
            Et2/2      SPINE-PEER-2   connected    trunk    full   100G    100GBASE-CR4
            Ma1        OOB-MGMT       connected    routed   full   1G      1000BASE-T
            """
        } else if cmd.hasPrefix("show ip route summary") {
            return """
            Operating mode: Multi-agent BGP (EVPN-VXLAN)
            Total routes: 48
            Direct: 8
            Static: 2
            OSPF: 0
            BGP: 38 (38 external, 0 internal)
            """
        } else if cmd.hasPrefix("show lldp nei") {
            return """
            Last table change: 0:14:22 ago
            Neighbor               Neighbor Interface   Chassis ID          Port ID
            leaf01-tor.nexwave     Ethernet49/1         001c.7314.9921      Et49/1
            leaf02-tor.nexwave     Ethernet49/1         001c.7314.9922      Et49/1
            spine02.nexwave        Ethernet1/1          001c.7314.8801      Et1/1
            """
        } else if cmd.hasPrefix("show ver") {
            return """
            Arista DCS-7050SX3-48YC8
            Hardware version:    11.02
            Serial number:       JPE19420012
            System MAC address:  001c.73ff.0101
            Software image version: 4.29.2F
            Architecture:        x86_64
            Uptime:              18 weeks, 2 days, 4 hours, 11 minutes
            """
        } else if cmd.hasPrefix("ping ") {
            let target = cmd.replacingOccurrences(of: "ping ", with: "").replacingOccurrences(of: "| json", with: "").trimmingCharacters(in: .whitespaces)
            return """
            PING \(target) (\(target)) 72(100) bytes of data.
            80 bytes from \(target): icmp_seq=1 ttl=64 time=0.842 ms
            80 bytes from \(target): icmp_seq=2 ttl=64 time=0.791 ms
            80 bytes from \(target): icmp_seq=3 ttl=64 time=0.812 ms
            --- \(target) ping statistics ---
            3 packets transmitted, 3 received, 0% packet loss, rtt 0.791/0.815/0.842 ms
            """
        } else if cmd.hasPrefix("show run diff") {
            return """
            --- flash:/startup-config
            +++ system:/running-config
            @@ -42,3 +42,5 @@
            +vlan 300
            +   name SERVERS_DMZ
            """
        } else if cmd == "exit" || cmd == "quit" {
            return "\n[Session terminated by user]"
        } else {
            return "% CLI command error: unrecognized command '\(raw)'"
        }
    }

    // MARK: - Juniper Junos Engine

    private func processJunos(cmd: String, raw: String) -> String {
        if cmd == "help" || cmd == "?" {
            return """
            Junos CLI commands:
              show interfaces terse      View interfaces and protocol status
              show route                 Display active forwarding table
              show chassis hardware      Display inventory FRUs and optics
              show system uptime         Display kernel and routing engine uptime
              configure                  Enter candidate configuration mode
              show configuration         Display active or candidate configuration
              commit                     Commit candidate configuration
              commit confirmed <mins>    Safe rollback commit
              rollback                   Discard candidate changes
              exit                       Exit current mode or logout
            """
        }

        if isConfigMode {
            if cmd == "exit" {
                if !subConfigContext.isEmpty {
                    subConfigContext = ""
                    return ""
                }
                isConfigMode = false
                return "Exiting configuration mode"
            } else if cmd == "top" {
                subConfigContext = ""
                return ""
            } else if cmd.hasPrefix("set ") {
                return "" // Candidate update simulated
            } else if cmd.hasPrefix("edit ") {
                let path = cmd.replacingOccurrences(of: "edit ", with: "")
                subConfigContext = path
                return ""
            } else if cmd == "commit" {
                return "commit complete"
            } else if cmd.hasPrefix("commit confirmed") {
                return "commit confirmed will be automatically rolled back in 5 minutes unless confirmed\ncommit complete"
            } else if cmd == "rollback" {
                return "load complete"
            } else if cmd == "show configuration" || cmd == "show | compare" {
                return """
                [edit interfaces]
                +   ge-0/0/0 {
                +       unit 0 {
                +           family inet {
                +               address 10.50.1.1/24;
                +           }
                +       }
                +   }
                """
            } else {
                return "syntax error, expecting <command>"
            }
        }

        // Operational Mode
        if cmd == "configure" || cmd == "edit" {
            isConfigMode = true
            subConfigContext = ""
            return "Entering configuration mode\nThe configuration has been changed but not committed"
        } else if cmd.hasPrefix("show int terse") || cmd == "show interfaces terse" {
            return """
            Interface               Admin Link Proto    Local                 Remote
            ge-0/0/0                up    up
            ge-0/0/0.0              up    up   inet     10.50.1.1/24        
            ge-0/0/1                up    up
            ge-0/0/1.0              up    up   inet     10.50.2.1/24        
            xe-0/2/0                up    up   inet     172.16.100.1/30     
            lo0.0                   up    up   inet     10.255.255.3        --> 0/0
            me0.0                   up    up   inet     192.168.1.50/24     
            """
        } else if cmd.hasPrefix("show route") {
            return """
            inet.0: 6 destinations, 6 routes (6 active, 0 holddown, 0 hidden)
            + = Active Route, - = Last Active, * = Both

            0.0.0.0/0          *[Static/5] 4w2d 11:21:05
                                > to 172.16.100.2 via xe-0/2/0.0
            10.50.1.0/24       *[Direct/0] 4w2d 11:21:05
                                > via ge-0/0/0.0
            10.255.255.3/32    *[Direct/0] 4w2d 11:21:05
                                > via lo0.0
            """
        } else if cmd.hasPrefix("show chassis hardware") {
            return """
            Hardware inventory:
            Item             Version  Part number  Serial number     Description
            Chassis                                PE3919420011      EX4300-48T
            Routing Engine 0 REV 14   750-045389   PE3919420011      EX4300-48T
            FPC 0            REV 14   750-045389   PE3919420011      EX4300-48T
              PIC 0                   BUILTIN      BUILTIN           48x 10/100/1000 Base-T
              PIC 1          REV 04   711-048567   CA2818390022      4x 1G/10G SFP/SFP+
                Xcvr 0       REV 01   740-021308   SP3920192301      SFP+-10G-SR
            Power Supply 0   REV 02   740-046864   1E029410192       PSU 350W AC
            """
        } else if cmd.hasPrefix("show system uptime") {
            return """
            Current time: 2026-09-17 06:58:12 UTC
            System started: 2026-08-15 19:37:07 UTC (4 weeks 4 days 11:21 ago)
            Last configured: 2026-09-10 14:02:11 UTC by admin
            Protocols started: 2026-08-15 19:38:00 UTC
            """
        } else if cmd.hasPrefix("ping ") {
            let target = cmd.replacingOccurrences(of: "ping ", with: "").trimmingCharacters(in: .whitespaces)
            return """
            PING \(target) (\(target)): 56 data bytes
            64 bytes from \(target): icmp_seq=0 ttl=64 time=1.042 ms
            64 bytes from \(target): icmp_seq=1 ttl=64 time=0.912 ms
            64 bytes from \(target): icmp_seq=2 ttl=64 time=0.885 ms
            --- \(target) ping statistics ---
            3 packets transmitted, 3 packets received, 0% packet loss
            round-trip min/avg/max/stddev = 0.885/0.946/1.042/0.068 ms
            """
        } else if cmd == "exit" || cmd == "quit" {
            return "\n[Session terminated by user]"
        } else {
            return "unknown command: \(raw)"
        }
    }
}
