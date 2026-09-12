import Testing
import Foundation
@testable import ParserKit
@testable import NetworkCore

@Suite("ParserKit Tests")
struct ParserKitTests {

    let sampleIPIntBrief = """
    Interface              IP-Address      OK? Method Status                Protocol
    FastEthernet0/0        192.168.1.1     YES NVRAM  up                    up      
    FastEthernet0/1        unassigned      YES unset  administratively down down    
    GigabitEthernet0/0/0   10.0.0.1        YES manual up                    up      
    Loopback0              127.0.0.1       YES unset  up                    up      
    """

    let sampleShowInterfaces = """
    GigabitEthernet0/1 is up, line protocol is up
      Hardware is Gigabit Ethernet, address is 0050.56b2.1a2b (bia 0050.56b2.1a2b)
      Internet address is 10.0.0.1/24
      MTU 1500 bytes, BW 1000000 Kbit/sec, DLY 10 usec,
         Full-duplex, 1000Mb/s, media type is RJ45
         1234567 packets input, 891234567 bytes, 0 no buffer
         Received 123 broadcasts (0 IP multicasts)
         0 runts, 0 giants, 0 throttles
         14 input errors, 14 CRC, 0 frame, 0 overrun, 0 ignored
         987654 packets output, 654321987 bytes, 0 underruns
    """

    let sampleShowIPRoute = """
    Codes: L - local, C - connected, S - static, R - RIP, M - mobile, B - BGP
           D - EIGRP, EX - EIGRP external, O - OSPF, IA - OSPF inter area 

    Gateway of last resort is 10.0.0.1 to network 0.0.0.0

    C        10.0.0.0/24 is directly connected, GigabitEthernet0/1
    S*       0.0.0.0/0 [1/0] via 10.0.0.1
    O        172.16.1.0/24 [110/20] via 10.0.0.2, GigabitEthernet0/1
    B        192.168.100.0/24 [20/0] via 10.255.255.1
    """

    let sampleShowMac = """
              Mac Address Table
    -------------------------------------------
    Vlan    Mac Address       Type        Ports
    ----    -----------       --------    -----
      10    0014.2201.2345    DYNAMIC     Gi0/1
      20    0050.56a1.b2c3    DYNAMIC     Gi0/2
     100    0000.0c07.ac01    STATIC      Router
    """

    let sampleShowARP = """
    Protocol  Address          Age (min)  Hardware Addr   Type   Interface
    Internet  192.168.1.1             -   0050.56b2.1a2b  ARPA   GigabitEthernet0/0
    Internet  192.168.1.50           12   3c22.fb12.3456  ARPA   GigabitEthernet0/0
    """

    let sampleShowNeighbors = """
    Capability Codes: R - Router, T - Trans Bridge, B - Source Route Bridge
                      S - Switch, H - Host, I - IGMP, r - Repeater, P - Phone

    Device ID        Local Intrfce     Hldtme    Capability  Platform  Port ID
    sw-core-01       Gig 0/1           154              R S  WS-C3850  Gig 1/0/24
    router-edge      Gig 0/0           120              R    ISR4451   Gig 0/0/0
    """

    let sampleShowBGP = """
    BGP router identifier 10.255.255.1, local AS number 65001
    BGP table version is 42, main routing table version 42

    Neighbor        V           AS MsgRcvd MsgSent   TblVer  InQ OutQ Up/Down  State/PfxRcd
    10.0.0.2        4        65002    1204    1205       42    0    0 02:14:22        5
    10.0.0.6        4        65003     500     502       42    0    0 00:10:05    Active
    """

    @Test("Show IP Interface Brief Parser extracts all interfaces")
    func testShowIPInterfaceBrief() throws {
        let parser = ShowIPInterfaceBriefParser()
        #expect(parser.canParse(rawOutput: sampleIPIntBrief) > 0.8)

        let result = try parser.parse(rawOutput: sampleIPIntBrief)
        guard case .ipInterfaceBrief(let entries) = result else {
            Issue.record("Expected .ipInterfaceBrief result")
            return
        }

        #expect(entries.count == 4)
        #expect(entries[0].interface == "FastEthernet0/0")
        #expect(entries[0].ipAddress == "192.168.1.1")
        #expect(entries[0].isUp == true)

        #expect(entries[1].interface == "FastEthernet0/1")
        #expect(entries[1].status == "administratively down")
        #expect(entries[1].isUp == false)
    }

    @Test("Show Interfaces Parser extracts counters and flags anomalies")
    func testShowInterfaces() throws {
        let parser = ShowInterfacesParser()
        #expect(parser.canParse(rawOutput: sampleShowInterfaces) > 0.8)

        let result = try parser.parse(rawOutput: sampleShowInterfaces)
        guard case .interfaceDetails(let entries) = result else {
            Issue.record("Expected .interfaceDetails result")
            return
        }

        #expect(entries.count == 1)
        let intf = entries[0]
        #expect(intf.name == "GigabitEthernet0/1")
        #expect(intf.ipAddress == "10.0.0.1/24")
        #expect(intf.mtu == 1500)
        #expect(intf.crcErrors == 14)
        #expect(intf.anomalies.contains(where: { $0.contains("CRC") }))
    }

    @Test("Show IP Route Parser extracts routing table")
    func testShowIPRoute() throws {
        let parser = ShowIPRouteParser()
        #expect(parser.canParse(rawOutput: sampleShowIPRoute) > 0.8)

        let result = try parser.parse(rawOutput: sampleShowIPRoute)
        guard case .routes(let entries) = result else {
            Issue.record("Expected .routes result")
            return
        }

        #expect(entries.count == 4)
        let defaultRoute = entries.first(where: { $0.prefix == "0.0.0.0/0" })
        #expect(defaultRoute?.nextHop == "10.0.0.1")

        let ospfRoute = entries.first(where: { $0.prefix == "172.16.1.0/24" })
        #expect(ospfRoute != nil)
        #expect(ospfRoute?.adminDistance == 110)
        #expect(ospfRoute?.metric == 20)
    }

    @Test("Show MAC Address Table Parser extracts dynamic/static entries")
    func testShowMacAddressTable() throws {
        let parser = ShowMacAddressTableParser()
        #expect(parser.canParse(rawOutput: sampleShowMac) > 0.8)

        let result = try parser.parse(rawOutput: sampleShowMac)
        guard case .macTable(let entries) = result else {
            Issue.record("Expected .macTable result")
            return
        }

        #expect(entries.count == 3)
        #expect(entries[0].vlan == 10)
        #expect(entries[0].port == "Gi0/1")
        #expect(entries[2].type == "STATIC")
    }

    @Test("Show ARP Parser extracts entries and resolves vendor")
    func testShowARP() throws {
        let parser = ShowARPParser()
        #expect(parser.canParse(rawOutput: sampleShowARP) > 0.8)

        let result = try parser.parse(rawOutput: sampleShowARP)
        guard case .arp(let entries) = result else {
            Issue.record("Expected .arp result")
            return
        }

        #expect(entries.count == 2)
        #expect(entries[0].ipAddress == "192.168.1.1")
        #expect(entries[0].vendor?.contains("VMware") == true)
    }

    @Test("Show Neighbors Parser extracts CDP / LLDP links")
    func testShowNeighbors() throws {
        let parser = ShowNeighborsParser()
        #expect(parser.canParse(rawOutput: sampleShowNeighbors) > 0.8)

        let result = try parser.parse(rawOutput: sampleShowNeighbors)
        guard case .neighbors(let entries) = result else {
            Issue.record("Expected .neighbors result")
            return
        }

        #expect(entries.count == 2)
        #expect(entries[0].deviceId == "sw-core-01")
        #expect(entries[0].platform == "WS-C3850")
    }

    @Test("Show BGP Summary Parser extracts peering status")
    func testShowBGPSummary() throws {
        let parser = ShowBGPSummaryParser()
        #expect(parser.canParse(rawOutput: sampleShowBGP) > 0.8)

        let result = try parser.parse(rawOutput: sampleShowBGP)
        guard case .bgpSummary(let entries) = result else {
            Issue.record("Expected .bgpSummary result")
            return
        }

        #expect(entries.count == 2)
        #expect(entries[0].neighborIP == "10.0.0.2")
        #expect(entries[0].isEstablished == true)
        #expect(entries[1].neighborIP == "10.0.0.6")
        #expect(entries[1].isEstablished == false)
    }

    @Test("Parser Registry auto-detects command type")
    func testParserRegistryAutoDetect() throws {
        let registry = ParserRegistry.shared
        let (p1, res1) = try registry.parse(text: sampleIPIntBrief)
        #expect(p1.commandFamily == .showIPInterfaceBrief)
        #expect(res1.recordCount == 4)

        let (p2, res2) = try registry.parse(text: sampleShowBGP)
        #expect(p2.commandFamily == .showBGPSummary)
        #expect(res2.recordCount == 2)
    }
}
