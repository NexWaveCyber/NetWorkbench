import Foundation

/// Interactive simulated network operating system (Cisco IOS-XE / Arista EOS)
/// Provides offline CLI interaction, prompt transitions, and command outputs for testing and demonstration.
public final class SimulatedDeviceCLI: @unchecked Sendable {
    public let hostname: String
    public let vendor: String
    private var isConfigMode: Bool = false
    public var onOutput: ((String) -> Void)?

    public init(hostname: String = "nexwave-core01", vendor: String = "Cisco IOS-XE") {
        self.hostname = hostname
        self.vendor = vendor
    }

    public var currentPrompt: String {
        isConfigMode ? "\(hostname)(config)# " : "\(hostname)# "
    }

    public func start() {
        let banner = """
        
        \u{1B}[1;36m*-------------------------------------------------------------------*
        * NexWave Network Workbench - High-Fidelity Device CLI Simulator   *
        * Platform: \(vendor) (Release 17.9.4a)                         *
        * Hostname: \(hostname)                                          *
        *-------------------------------------------------------------------*\u{1B}[0m
        
        User Access Verification
        Username: admin
        Password: [authenticated via Keychain]
        
        Last login: Today from 10.100.1.50
        
        \(currentPrompt)
        """
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

        if cmd == "help" || cmd == "?" {
            response = """
            Exec commands:
              show <...>            Show running system information
              ping <ip>             Send ICMP echo request
              traceroute <ip>       Trace route to destination
              configure terminal    Enter global configuration mode
              write memory          Save running configuration to NVRAM
              reload                Halt and perform a cold restart
              exit                  Exit current CLI mode or close session
            """
        } else if isConfigMode {
            if cmd == "exit" || cmd == "end" {
                isConfigMode = false
                response = ""
            } else if cmd.hasPrefix("interface ") || cmd.hasPrefix("int ") {
                response = "\(hostname)(config-if)# "
            } else if cmd.hasPrefix("router ") {
                response = "\(hostname)(config-router)# "
            } else if cmd.hasPrefix("hostname ") {
                response = ""
            } else {
                response = "% Invalid configuration command or unrecognized keyword."
            }
        } else {
            // Privileged Exec Mode
            if cmd == "configure terminal" || cmd == "conf t" {
                isConfigMode = true
                response = "Enter configuration commands, one per line.  End with CNTL/Z."
            } else if cmd.hasPrefix("show ip int") || cmd == "sh ip int br" || cmd == "show ip interface brief" {
                response = """
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
                response = """
                Cisco IOS XE Software, Version 17.09.04a
                Cisco IOS Software [Cupertino], Catalyst L3 Switch Software (CAT9K_IOSXE), Version 17.9.4a, RELEASE SOFTWARE (fc2)
                Technical Support: http://www.cisco.com/techsupport
                Compiled Fri 15-Sep-23 04:12 by mcpre

                System uptime is 42 weeks, 3 days, 14 hours, 28 minutes
                Uptime for this control processor is 42 weeks, 3 days, 14 hours, 31 minutes
                System returned to ROM by reload
                System image file is "bootflash:packages.conf"
                Last reload reason: LocalReload

                cisco C9300-48UXM (X86) processor with 16777216K bytes of physical memory.
                Model Number: C9300-48UXM
                System Serial Number: FOC2341L0R9
                """
            } else if cmd.hasPrefix("show cdp nei") || cmd.hasPrefix("show lldp nei") {
                response = """
                Capability Codes: R - Router, T - Trans Bridge, B - Source Route Bridge
                                  S - Switch, H - Host, I - IGMP, r - Repeater, P - Phone, 
                                  D - Remote, C - DOCSIS, s - Station, m - Multiple

                Device ID        Local Intrfce     Holdtme    Capability  Platform  Port ID
                dist-sw01.nexwave Gig 1/0/1        142              S I   WS-C3850  Gig 1/0/48
                dist-sw02.nexwave Gig 1/0/2        138              S I   WS-C3850  Gig 1/0/48
                edge-ap-3f.nex    Gig 1/0/12       165             r T P  C9130AXI  Eth 0
                core-spine01      Te 1/1/1         124            R S I   N9K-C9336 Eth 1/1
                """
            } else if cmd.hasPrefix("show run") || cmd == "sh run" {
                response = """
                Building configuration...

                Current configuration : 2842 bytes
                !
                version 17.9
                service timestamps debug datetime msec
                service timestamps log datetime msec
                no service password-encryption
                !
                hostname \(hostname)
                !
                boot-start-marker
                boot-end-marker
                !
                spanning-tree mode rapid-pvst
                spanning-tree extend system-id
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
                response = """
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
                response = """
                Codes: L - local, C - connected, S - static, R - RIP, M - mobile, B - BGP
                       D - EIGRP, EX - EIGRP external, O - OSPF, IA - OSPF inter area 

                Gateway of last resort is 192.168.100.2 to network 0.0.0.0

                O*E2  0.0.0.0/0 [110/1] via 192.168.100.2, 3w2d, TenGigabitEthernet1/1/1
                      10.0.0.0/8 is variably subnetted, 4 subnets, 2 masks
                C        10.10.10.0/24 is directly connected, GigabitEthernet1/0/1
                L        10.10.10.1/32 is directly connected, GigabitEthernet1/0/1
                C        10.10.20.0/24 is directly connected, GigabitEthernet1/0/2
                C        10.255.255.1/32 is directly connected, Loopback0
                """
            } else if cmd.hasPrefix("ping ") {
                let target = cmd.replacingOccurrences(of: "ping ", with: "").trimmingCharacters(in: .whitespaces)
                response = """
                Type escape sequence to abort.
                Sending 5, 100-byte ICMP Echos to \(target), timeout is 2 seconds:
                !!!!!
                Success rate is 100 percent (5/5), round-trip min/avg/max = 1/2/4 ms
                """
            } else if cmd == "write memory" || cmd == "wr" || cmd == "copy run start" {
                response = """
                Building configuration...
                [OK]
                """
            } else if cmd == "terminal length 0" || cmd == "term len 0" {
                response = ""
            } else if cmd == "exit" || cmd == "quit" {
                response = "\n[Session terminated by user]"
            } else {
                response = "% Invalid input detected at '^' marker.\n             ^\nType '?' or 'help' for supported commands."
            }
        }

        let outputBlock: String
        if response.isEmpty {
            outputBlock = "\n\(currentPrompt)"
        } else {
            outputBlock = "\n\(response)\n\(currentPrompt)"
        }

        onOutput?(outputBlock)
    }
}
