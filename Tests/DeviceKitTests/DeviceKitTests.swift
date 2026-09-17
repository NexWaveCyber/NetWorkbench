import Testing
import Foundation
import CoreGraphics
@testable import DeviceKit
@testable import PersistenceKit
@testable import SecurityKit

@Suite("DeviceKit Tests")
struct DeviceKitTests {

    @Test("OUI Vendor Resolution and Private MAC Detection")
    func testOUIResolution() {
        #expect(OUIResolver.resolve(mac: "00:00:0c:12:34:56") == "Cisco Systems, Inc")
        #expect(OUIResolver.resolve(mac: "00-1C-73-AA-BB-CC") == "Arista Networks")
        #expect(OUIResolver.resolve(mac: "00:19:e2:11:22:33") == "Juniper Networks")
        #expect(OUIResolver.resolve(mac: "f8:ff:c2:01:02:03") == "Apple, Inc.")
        #expect(OUIResolver.resolve(mac: "24:a4:3c:99:88:77") == "Ubiquiti Inc")
        #expect(OUIResolver.resolve(mac: "00:09:0f:55:44:33") == "Fortinet, Inc.")
        #expect(OUIResolver.resolve(mac: "00:0c:29:1a:2b:3c") == "VMware, Inc.")
        #expect(OUIResolver.resolve(mac: "b8:27:eb:11:22:33") == "Raspberry Pi Foundation")

        // Private / Randomized MAC detection (bit 1 of first octet is set)
        #expect(OUIResolver.isLocallyAdministered(mac: "aa:bb:cc:dd:ee:ff") == true)
        #expect(OUIResolver.isLocallyAdministered(mac: "02:00:00:00:00:00") == true)
        #expect(OUIResolver.isLocallyAdministered(mac: "00:00:0c:12:34:56") == false)
        #expect(OUIResolver.resolve(mac: "aa:bb:cc:dd:ee:ff") == "Private MAC (Locally Administered)")
        #expect(OUIResolver.resolve(mac: "72:5:41:93:2d:cd") == "Private MAC (Locally Administered)")
        #expect(OUIResolver.resolve(mac: "12:63:8d:f9:ff:5e") == "Private MAC (Locally Administered)")

        // Non-locally-administered unassigned MAC
        #expect(OUIResolver.resolve(mac: "70:00:00:11:22:33") == nil)

        // Well-known home & enterprise router vendors
        #expect(OUIResolver.resolve(mac: "68:7f:f0:55:35:45") == "TP-Link Systems Inc")
        #expect(OUIResolver.resolve(mac: "00:14:bf:12:34:56") == "Cisco-Linksys, LLC")
        #expect(OUIResolver.resolve(mac: "58:6d:8f:11:22:33") == "Cisco-Linksys, LLC")
        #expect(OUIResolver.resolve(mac: "50:c7:bf:11:22:33") == "TP-LINK TECHNOLOGIES CO.,LTD.")
        #expect(OUIResolver.resolve(mac: "00:09:5b:aa:bb:cc") == "NETGEAR")
        #expect(OUIResolver.resolve(mac: "00:1e:8c:12:34:56") == "ASUSTek COMPUTER INC.")

        // Darwin ARP unpadded octet format resolution
        #expect(OUIResolver.resolve(mac: "0:1c:c2:79:17:7b") == "Part II Research, Inc.")
        #expect(OUIResolver.resolve(mac: "ac:0:7a:ec:bd:31") == "Apple, Inc.")
        #expect(OUIResolver.resolve(mac: "40:ed:0:57:7b:c0") == "TP-Link Systems Inc")
        #expect(OUIResolver.resolve(mac: "bc:7e:8b:9e:d8:4") == "Samsung Electronics Co.,Ltd")
        #expect(OUIResolver.resolve(mac: "68:1d:ef:35:25:2") == "Shenzhen CYX Technology Co., Ltd.")
        #expect(OUIResolver.resolve(mac: "90:47:48:86:a9:de") == "Sony Interactive Entertainment Inc.")
        #expect(OUIResolver.resolve(mac: "fc:34:97:4c:20:57") == "ASUSTek COMPUTER INC.")
        #expect(OUIResolver.resolve(mac: "e4:54:e8:5e:87:a7") == "Dell Inc.")

        // Vendor inference
        #expect(OUIResolver.inferVendor(mac: "00:00:0c:00:00:00") == .cisco)
        #expect(OUIResolver.inferVendor(mac: "00:1c:73:00:00:00") == .arista)
        #expect(OUIResolver.inferVendor(mac: "68:7f:f0:55:35:45") == .tpLink)
        #expect(OUIResolver.inferVendor(mac: "00:14:bf:11:22:33") == .linksys)
        #expect(OUIResolver.inferVendor(mac: "58:6d:8f:11:22:33") == .linksys)
        #expect(OUIResolver.inferVendor(mac: "00:09:5b:aa:bb:cc") == .netgear)
        #expect(OUIResolver.inferVendor(mac: "50:c7:bf:11:22:33") == .tpLink)
        #expect(OUIResolver.inferVendor(mac: "00:1e:8c:11:22:33") == .asus)
        #expect(OUIResolver.inferVendor(mac: "bc:7e:8b:9e:d8:4") == .samsung)
        #expect(OUIResolver.inferVendor(mac: "90:47:48:86:a9:de") == .sony)
        #expect(OUIResolver.inferVendor(mac: "e4:54:e8:5e:87:a7") == .dell)
        #expect(OUIResolver.inferVendor(fromName: "Linksys / Belkin") == .linksys)
        #expect(OUIResolver.inferVendor(fromName: "TP-Link Systems Inc.") == .tpLink)
        #expect(OUIResolver.inferVendor(fromName: "Samsung Electronics Co.,Ltd") == .samsung)
        #expect(OUIResolver.inferVendor(fromName: "Sony Interactive Entertainment Inc.") == .sony)
        #expect(OUIResolver.inferVendor(mac: "ff:ff:ff:ff:ff:ff") == .generic)
    }

    @Test("Full User Subnet Discovered MAC Accuracy Verification")
    func testFullUserSubnetDiscoveredMACAccuracy() {
        let subnetCases: [(raw: String, expectedNorm: String, expectedVendor: String, isPrivate: Bool, expectedEnum: DeviceVendor)] = [
            ("68:7f:f0:55:35:45", "68:7f:f0:55:35:45", "TP-Link Systems Inc", false, .tpLink),
            ("9c:53:22:a7:b9:fc", "9c:53:22:a7:b9:fc", "TP-Link Systems Inc", false, .tpLink),
            ("e4:54:e8:5e:87:a7", "e4:54:e8:5e:87:a7", "Dell Inc.", false, .dell),
            ("72:5:41:93:2d:cd", "72:05:41:93:2d:cd", "Private MAC (Locally Administered)", true, .apple),
            ("c8:f7:50:f4:31:dd", "c8:f7:50:f4:31:dd", "Dell Inc.", false, .dell),
            ("6c:5a:b0:71:d7:7a", "6c:5a:b0:71:d7:7a", "TP-Link Systems Inc", false, .tpLink),
            ("12:63:8d:f9:ff:5e", "12:63:8d:f9:ff:5e", "Private MAC (Locally Administered)", true, .apple),
            ("b0:a7:b9:ed:59:47", "b0:a7:b9:ed:59:47", "TP-Link Systems Inc", false, .tpLink),
            ("f0:a7:31:36:ff:2e", "f0:a7:31:36:ff:2e", "TP-Link Systems Inc", false, .tpLink),
            ("8a:11:1e:f4:4e:7c", "8a:11:1e:f4:4e:7c", "Private MAC (Locally Administered)", true, .apple),
            ("d2:dc:23:f5:d3:93", "d2:dc:23:f5:d3:93", "Private MAC (Locally Administered)", true, .apple),
            ("bc:7e:8b:9e:d8:4", "bc:7e:8b:9e:d8:04", "Samsung Electronics Co.,Ltd", false, .samsung),
            ("6c:5a:b0:71:d2:53", "6c:5a:b0:71:d2:53", "TP-Link Systems Inc", false, .tpLink),
            ("6c:5a:b0:23:99:bf", "6c:5a:b0:23:99:bf", "TP-Link Systems Inc", false, .tpLink),
            ("76:20:72:4:c6:f7", "76:20:72:04:c6:f7", "Private MAC (Locally Administered)", true, .apple),
            ("74:cc:40:a7:7a:ef", "74:cc:40:a7:7a:ef", "Apple, Inc.", false, .apple),
            ("4e:79:88:fe:f7:5a", "4e:79:88:fe:f7:5a", "Private MAC (Locally Administered)", true, .apple),
            ("b0:a7:b9:b2:4b:3d", "b0:a7:b9:b2:4b:3d", "TP-Link Systems Inc", false, .tpLink),
            ("0:1c:c2:79:17:7b", "00:1c:c2:79:17:7b", "Part II Research, Inc.", false, .generic),
            ("ac:0:7a:ec:bd:31", "ac:00:7a:ec:bd:31", "Apple, Inc.", false, .apple),
            ("68:1d:ef:35:25:2", "68:1d:ef:35:25:02", "Shenzhen CYX Technology Co., Ltd.", false, .generic),
            ("40:ed:0:57:7b:c0", "40:ed:00:57:7b:c0", "TP-Link Systems Inc", false, .tpLink),
            ("68:1d:ef:35:25:1", "68:1d:ef:35:25:01", "Shenzhen CYX Technology Co., Ltd.", false, .generic),
            ("fc:34:97:4c:20:57", "fc:34:97:4c:20:57", "ASUSTek COMPUTER INC.", false, .asus),
            ("cc:11:5a:19:51:38", "cc:11:5a:19:51:38", "Apple, Inc.", false, .apple),
            ("d0:c2:4e:2e:c1:e8", "d0:c2:4e:2e:c1:e8", "Samsung Electronics Co.,Ltd", false, .samsung),
            ("7e:a4:a3:7d:54:f3", "7e:a4:a3:7d:54:f3", "Private MAC (Locally Administered)", true, .apple)
        ]

        for item in subnetCases {
            let norm = OUIResolver.normalizeMAC(item.raw)
            #expect(norm == item.expectedNorm)

            let isPriv = OUIResolver.isLocallyAdministered(mac: item.raw)
            #expect(isPriv == item.isPrivate)

            let resolved = OUIResolver.resolve(mac: item.raw)
            #expect(resolved == item.expectedVendor)

            let inferred = OUIResolver.inferVendor(mac: item.raw)
            #expect(inferred == item.expectedEnum)
        }
    }

    @Test("ARP Output Parsing")
    func testARPOutputParsing() async {
        let sampleARP = """
        ? (192.168.1.1) at 0:1c:73:a1:b2:c3 on en0 ifscope [ethernet]
        ? (192.168.1.50) at f8:ff:c2:12:34:56 on en0 ifscope [ethernet]
        ? (192.168.1.255) at (incomplete) on en0 [ethernet]
        ? (10.0.0.1) at 0:0:c:11:22:33 on bridge0 ifscope [ethernet]
        """

        let engine = LocalDiscoveryEngine()
        let neighbors = await engine.parseARPOutput(sampleARP)

        #expect(neighbors.count == 3)

        let aristaNeighbor = neighbors.first { $0.ipAddress == "192.168.1.1" }
        #expect(aristaNeighbor != nil)
        #expect(aristaNeighbor?.macAddress == "00:1c:73:a1:b2:c3")
        #expect(aristaNeighbor?.ouiVendor == "Arista Networks")
        #expect(aristaNeighbor?.interface == "en0")

        let appleNeighbor = neighbors.first { $0.ipAddress == "192.168.1.50" }
        #expect(appleNeighbor != nil)
        #expect(appleNeighbor?.ouiVendor == "Apple, Inc.")

        let ciscoNeighbor = neighbors.first { $0.ipAddress == "10.0.0.1" }
        #expect(ciscoNeighbor != nil)
        #expect(ciscoNeighbor?.macAddress == "00:00:0c:11:22:33")
        #expect(ciscoNeighbor?.ouiVendor == "Cisco Systems, Inc")
    }

    @Test("NDP IPv6 Output Parsing Excludes Link-Local and Keeps Unique IPv6")
    func testNDPOutputParsing() async {
        let sampleNDP = """
        Neighbor                             Linklayer Address  Netif Expire    St Flgs Prbs
        fe80::1%en0                          0:1c:73:a1:b2:c3   en0   23h59m59s R
        2001:db8::50                         f8:ff:c2:12:34:56  en0   23h58m12s R
        fd00:abcd::1                         0:1c:73:a1:b2:c3   en0   23h59m59s R
        fe80::2%en0                          (incomplete)       en0   expired   I
        """

        let engine = LocalDiscoveryEngine()
        let neighbors = await engine.parseNDPOutput(sampleNDP)

        // Only unique IPv6 (Global Unicast 2001:db8::50 and ULA fd00:abcd::1) are accepted; fe80:: is excluded!
        #expect(neighbors.count == 2)
        #expect(neighbors.allSatisfy { !$0.ipAddress.hasPrefix("fe80") })
        #expect(neighbors[0].ipAddress == "2001:db8::50")
        #expect(neighbors[0].ouiVendor == "Apple, Inc.")
        #expect(neighbors[1].ipAddress == "fd00:abcd::1")
        #expect(neighbors[1].macAddress == "00:1c:73:a1:b2:c3")
        #expect(neighbors[1].ouiVendor == "Arista Networks")
    }

    @Test("Dual-Stack Neighbor Consolidation Drops Link-Local and Keeps Unique IPv6")
    func testDualStackNeighborConsolidation() async {
        let arp = """
        ? (192.168.1.50) at f8:ff:c2:12:34:56 on en0 ifscope [ethernet]
        """
        let ndp = """
        Neighbor                             Linklayer Address  Netif Expire    St Flgs Prbs
        fe80::1c0a:6f6e:f286:2be8%en0        f8:ff:c2:12:34:56  en0   23h59m59s R
        2001:db8:1:10:917c:bd7a:aaa6:4dc6    f8:ff:c2:12:34:56  en0   23h58m12s R
        """

        let engine = LocalDiscoveryEngine()
        let arpNeighbors = await engine.parseARPOutput(arp)
        let ndpNeighbors = await engine.parseNDPOutput(ndp)

        #expect(arpNeighbors.count == 1)
        #expect(ndpNeighbors.count == 1) // Link-local fe80:: is completely excluded!
        #expect(ndpNeighbors[0].ipAddress == "2001:db8:1:10:917c:bd7a:aaa6:4dc6")
        #expect(ndpNeighbors[0].macAddress == "f8:ff:c2:12:34:56")
    }

    @Test("Device CRUD and MAC Address Persistence in SQLite")
    func testDeviceCRUDAndBaselines() throws {
        let tempDBPath = FileManager.default.temporaryDirectory.appendingPathComponent("test_device_\(UUID().uuidString).sqlite").path
        let db = try SQLiteDatabase(path: tempDBPath)
        let manager = DeviceManager(database: db)

        // Create with MAC Address
        let device = NetworkDevice(
            displayName: "Core-Switch-01",
            hostname: "core-sw01.corp.internal",
            managementIP: "10.0.0.1",
            macAddress: "00:1c:73:aa:bb:cc",
            vendor: .cisco,
            role: .switchRole,
            platform: "IOS-XE",
            model: "Catalyst 9300",
            site: "HQ-DC1",
            tags: ["core", "campus", "critical"],
            status: .online,
            snmpConfig: SNMPDeviceConfig(community: "corp-snmp", port: 161, version: "v2c")
        )

        try manager.createDevice(device)

        // List & verify MAC persistence
        let list = try manager.listDevices()
        #expect(list.count == 1)
        #expect(list[0].displayName == "Core-Switch-01")
        #expect(list[0].macAddress == "00:1c:73:aa:bb:cc")
        #expect(list[0].vendor == .cisco)
        #expect(list[0].tags.count == 3)
        #expect(list[0].snmpConfig?.community == "corp-snmp")

        // Update
        var updated = list[0]
        updated.displayName = "Core-Switch-01-Renamed"
        updated.macAddress = "00:1c:73:aa:bb:dd"
        updated.status = .online
        try manager.updateDevice(updated)

        let reList = try manager.listDevices()
        #expect(reList[0].displayName == "Core-Switch-01-Renamed")
        #expect(reList[0].macAddress == "00:1c:73:aa:bb:dd")

        // Baselines
        let baseline = DeviceBaseline(
            deviceId: device.id,
            avgLatencyMs: 1.5,
            packetLossPct: 0.0,
            openPorts: [22, 161, 443],
            snmpSysDescr: "Cisco IOS XE Software, Catalyst L3 Switch",
            notes: "Initial deployment baseline"
        )
        try manager.saveBaseline(baseline)

        let fetchedBaseline = try manager.getLatestBaseline(forDeviceId: device.id)
        #expect(fetchedBaseline != nil)
        #expect(fetchedBaseline?.avgLatencyMs == 1.5)
        #expect(fetchedBaseline?.openPorts == [22, 161, 443])

        // Baseline Comparison
        let comparison = manager.compareWithBaseline(
            currentLatency: 25.0, // degraded (1.5 -> 25)
            currentLoss: 2.0,     // degraded (0 -> 2.0%)
            currentOpenPorts: [22, 80], // missing 161 & 443, unexpected 80
            baseline: baseline
        )

        #expect(comparison.isLatencyDegraded == true)
        #expect(comparison.isLossDegraded == true)
        #expect(comparison.missingPorts == [161, 443])
        #expect(comparison.unexpectedPorts == [80])
        #expect(comparison.overallHealthScore < 50)

        // Delete
        try manager.deleteDevice(id: device.id)
        #expect(try manager.listDevices().isEmpty)

        // Cleanup
        try? FileManager.default.removeItem(atPath: tempDBPath)
    }

    @Test("DeviceAuditor Active Probe and Baseline Drift Audit")
    func testDeviceAuditorProbe() async throws {
        let auditor = DeviceAuditor()
        // Probe localhost (127.0.0.1) with ping train & ports
        let sample = await auditor.probeLiveBaseline(
            ipAddress: "127.0.0.1",
            customPorts: [80, 443],
            pingCount: 2
        )

        #expect(sample.avgLatencyMs >= 0.0)
        #expect(sample.packetLossPct >= 0.0 && sample.packetLossPct <= 100.0)

        // Test drift audit against a synthetic baseline
        let device = NetworkDevice(
            name: "Loopback-Test",
            ipAddress: "127.0.0.1",
            macAddress: "00:00:00:00:00:01"
        )
        let baseline = DeviceBaseline(
            deviceId: device.id,
            avgLatencyMs: 1.0,
            packetLossPct: 0.0,
            openPorts: []
        )

        let tempDBPath = FileManager.default.temporaryDirectory.appendingPathComponent("test_audit_\(UUID().uuidString).sqlite").path
        let db = try SQLiteDatabase(path: tempDBPath)
        let manager = DeviceManager(database: db)

        let auditResult = await auditor.auditDevice(device: device, baseline: baseline, manager: manager)
        #expect(auditResult.comparison.overallHealthScore >= 0 && auditResult.comparison.overallHealthScore <= 100)

        try? FileManager.default.removeItem(atPath: tempDBPath)
    }

    @Test("Graph Mutation, Path Finding, and VLAN Filtering")
    func testGraphPathFindingAndVLANFiltering() {
        var graph = TopologyGraph.buildEnterpriseDemo()

        // 1. Path finding from core to access AP
        let path = graph.findShortestPath(from: "core-rtr01", to: "ap-lobby")
        #expect(path != nil)
        #expect(path?.nodeIds.first == "core-rtr01")
        #expect(path?.nodeIds.last == "ap-lobby")
        #expect((path?.nodeIds.count ?? 0) >= 3) // core -> dist -> acc -> ap

        // 2. VLAN 20 filtering
        let vlan20 = graph.filterByVLAN(20)
        #expect(vlan20.matchingNodeIds.contains("core-rtr01"))
        #expect(vlan20.matchingNodeIds.contains("dist-sw01"))

        // 3. Multi-link detection
        let parallelLinks = graph.linksBetween(nodeA: "dist-sw01", nodeB: "acc-sw01")
        #expect(parallelLinks.count >= 1)

        // 4. Graph mutation
        let customNode = TopologyNode(
            id: "custom-switch",
            label: "custom-sw01",
            role: .switchRole,
            ipAddress: "10.0.99.1"
        )
        graph.addNode(customNode)
        #expect(graph.nodes.contains(where: { $0.id == "custom-switch" }))

        let customLink = TopologyLink(
            id: "link-custom",
            sourceNodeId: "dist-sw01",
            targetNodeId: "custom-switch",
            sourceInterface: "Eth1/40",
            targetInterface: "Gi0/1"
        )
        graph.addLink(customLink)
        #expect(graph.links.contains(where: { $0.id == "link-custom" }))

        graph.removeNode(id: "custom-switch")
        #expect(!graph.nodes.contains(where: { $0.id == "custom-switch" }))
        #expect(!graph.links.contains(where: { $0.id == "link-custom" })) // cascading link deletion
    }

    @Test("CIDR Subnet Target IP Generation")
    func testCIDRTargetGeneration() {
        let engine = LocalDiscoveryEngine()

        // Standard /24 subnet (e.g. 192.168.1.0/24) -> 254 usable host addresses
        let ips24 = engine.generateTargetIPs(cidr: "192.168.1.0/24")
        #expect(ips24.count == 254)
        #expect(ips24.first == "192.168.1.1")
        #expect(ips24.last == "192.168.1.254")

        // Small /30 subnet (e.g. 10.0.0.0/30) -> 2 usable host addresses
        let ips30 = engine.generateTargetIPs(cidr: "10.0.0.0/30")
        #expect(ips30.count == 2)
        #expect(ips30.first == "10.0.0.1")
        #expect(ips30.last == "10.0.0.2")

        // Empty fallback
        let emptyIPs = engine.generateTargetIPs(cidr: "invalid-cidr")
        #expect(emptyIPs.isEmpty)
    }

    @Test("DiscoveredNeighbor Latency Formatting")
    func testDiscoveredNeighborLatency() {
        let neighborFast = DiscoveredNeighbor(
            ipAddress: "192.168.1.1",
            macAddress: "00:1c:73:00:11:22",
            discoverySource: .arp,
            ouiVendor: "Arista Networks",
            latencyMs: 1.234
        )
        #expect(neighborFast.latencyMs == 1.234)
        #expect(neighborFast.latencyDisplay == "1.2 ms")

        let neighborNone = DiscoveredNeighbor(
            ipAddress: "192.168.1.2",
            macAddress: "00:1c:73:00:11:33",
            discoverySource: .arp,
            ouiVendor: "Arista Networks"
        )
        #expect(neighborNone.latencyMs == nil)
        #expect(neighborNone.latencyDisplay == nil)
    }

    @Test("Active Interface Resolution")
    func testActiveInterfaceResolution() {
        let iface = LocalDiscoveryEngine.resolveActiveInterface()
        // On a running Mac with network connectivity, an active interface exists
        if let iface = iface {
            #expect(!iface.name.isEmpty)
            #expect(!iface.ipv4.isEmpty)
            #expect(!iface.cidr.isEmpty)
            #expect(iface.prefixLength > 0 && iface.prefixLength <= 32)
        }
    }

    @Test("Multi-Interface Enumeration and Preferred Target Interface Resolution")
    func testMultiInterfaceEnumeration() {
        let interfaces = LocalDiscoveryEngine.enumerateActiveInterfaces()
        for iface in interfaces {
            #expect(!iface.name.isEmpty)
            #expect(!iface.name.hasPrefix("lo"))
            #expect(!iface.name.hasPrefix("utun"))
            #expect(!iface.name.hasPrefix("awdl"))
            #expect(!iface.ipAddress.isEmpty)
            #expect(!iface.cidr.isEmpty)
        }

        // Test preferred target interface resolution
        if let first = interfaces.first {
            let resolved = LocalDiscoveryEngine.resolveTargetInterface(preferredName: first.name)
            #expect(resolved?.name == first.name)
        }

        // Test nonexistent interface falls back to default active interface
        let fallback = LocalDiscoveryEngine.resolveTargetInterface(preferredName: "nonexistent_iface_999")
        let active = LocalDiscoveryEngine.resolveActiveInterface()
        #expect(fallback?.name == active?.name)
    }

    @Test("Quick Port Audit Concurrent Execution")
    func testQuickPortAudit() async {
        // Probe local loopback on top ports
        let openPorts = await LocalDiscoveryEngine.quickScanPorts(
            ip: "127.0.0.1",
            ports: [22, 80, 443, 8080],
            timeoutSeconds: 0.2
        )
        // Result is a valid sorted integer array
        #expect(openPorts.sorted() == openPorts)
    }

    @Test("Proactive IPv6 All-Nodes Multicast Probe")
    func testIPv6MulticastProbe() {
        // Must complete in bounded time without throwing or crashing
        LocalDiscoveryEngine.pingIPv6AllNodesMulticast(interface: "en0")
    }

    @Test("RFC 4180 CSV Device Import with OUI Inference and Upsert")
    func testCSVDeviceImport() throws {
        let tempDBPath = FileManager.default.temporaryDirectory.appendingPathComponent("test_csv_import_\(UUID().uuidString).sqlite").path
        let db = try SQLiteDatabase(path: tempDBPath)
        let manager = DeviceManager(database: db)

        let csvContent = """
        Device Name,IP Address,MAC Address,Vendor,Role,Site,Tags
        Switch-Core-01,10.0.1.1,00:00:0c:12:34:56,,Switch,"Data Center, Bldg 1","core, backbone"
        Router-Border-01,10.0.1.2,00:1c:73:aa:bb:cc,Arista,Router,HQ,"edge, wan"
        """

        let result = try manager.importDevicesFromCSV(content: csvContent)
        #expect(result.totalProcessed == 2)
        #expect(result.addedCount == 2)
        #expect(result.updatedCount == 0)
        #expect(result.errors.isEmpty)

        let devices = try manager.listDevices()
        #expect(devices.count == 2)

        let sw = devices.first { $0.ipAddress == "10.0.1.1" }
        #expect(sw != nil)
        #expect(sw?.name == "Switch-Core-01")
        #expect(sw?.vendor == .cisco) // auto-inferred from 00:00:0c OUI!
        #expect(sw?.role == .switchRole)
        #expect(sw?.location == "Data Center, Bldg 1") // RFC 4180 quoted comma
        #expect(sw?.tags.contains("core") == true)
        #expect(sw?.tags.contains("backbone") == true)

        // Test Upsert: re-import with updated site and new tag for 10.0.1.1
        let updatedCSV = """
        Device Name,IP Address,MAC Address,Vendor,Role,Site,Tags
        Switch-Core-01-Renamed,10.0.1.1,00:00:0c:12:34:56,Cisco,Switch,"Data Center, Bldg 2","core, spine"
        """
        let updateResult = try manager.importDevicesFromCSV(content: updatedCSV)
        #expect(updateResult.totalProcessed == 1)
        #expect(updateResult.addedCount == 0)
        #expect(updateResult.updatedCount == 1)

        let updatedDevices = try manager.listDevices()
        #expect(updatedDevices.count == 2)
        let swUpdated = updatedDevices.first { $0.ipAddress == "10.0.1.1" }
        #expect(swUpdated?.name == "Switch-Core-01-Renamed")
        #expect(swUpdated?.location == "Data Center, Bldg 2")

        try? FileManager.default.removeItem(atPath: tempDBPath)
    }

    @Test("JSON Device Import with Standard and Key-Value Formats")
    func testJSONDeviceImport() throws {
        let tempDBPath = FileManager.default.temporaryDirectory.appendingPathComponent("test_json_import_\(UUID().uuidString).sqlite").path
        let db = try SQLiteDatabase(path: tempDBPath)
        let manager = DeviceManager(database: db)

        let jsonString = """
        [
            {
                "name": "Firewall-PaloAlto",
                "ip": "10.0.2.1",
                "mac": "00:1b:17:11:22:33",
                "role": "Firewall",
                "site": "DMZ",
                "tags": "security, perimeter"
            },
            {
                "devicename": "AP-Conference",
                "ip_address": "10.0.2.2",
                "mac_address": "24:a4:3c:99:88:77",
                "role": "Access Point",
                "site": "Floor 3"
            }
        ]
        """
        guard let data = jsonString.data(using: .utf8) else {
            #expect(Bool(false))
            return
        }

        let result = try manager.importDevicesFromJSON(data: data)
        #expect(result.totalProcessed == 2)
        #expect(result.addedCount == 2)
        #expect(result.errors.isEmpty)

        let devices = try manager.listDevices()
        #expect(devices.count == 2)

        let ap = devices.first { $0.ipAddress == "10.0.2.2" }
        #expect(ap != nil)
        #expect(ap?.name == "AP-Conference")
        #expect(ap?.vendor == .ubiquiti) // inferred from 24:a4:3c OUI!
        #expect(ap?.role == .accessPoint)
        #expect(ap?.location == "Floor 3")

        try? FileManager.default.removeItem(atPath: tempDBPath)
    }

    @Test("Bulk Fleet Operations: Tagging, Site Re-assignment, and Deletion")
    func testBulkFleetOperations() throws {
        let tempDBPath = FileManager.default.temporaryDirectory.appendingPathComponent("test_bulk_\(UUID().uuidString).sqlite").path
        let db = try SQLiteDatabase(path: tempDBPath)
        let manager = DeviceManager(database: db)

        let dev1 = NetworkDevice(name: "Dev1", ipAddress: "10.10.1.1", location: "SiteA", tags: ["alpha"])
        let dev2 = NetworkDevice(name: "Dev2", ipAddress: "10.10.1.2", location: "SiteA", tags: ["beta"])
        let dev3 = NetworkDevice(name: "Dev3", ipAddress: "10.10.1.3", location: "SiteB", tags: ["gamma"])

        try manager.saveDevice(dev1)
        try manager.saveDevice(dev2)
        try manager.saveDevice(dev3)

        let ids = [dev1.id, dev2.id]

        // 1. Bulk add tags
        try manager.bulkAddTags(ids: ids, tags: ["production", "tier-1"])
        let afterTags = try manager.listDevices()
        let d1After = afterTags.first { $0.id == dev1.id }!
        let d2After = afterTags.first { $0.id == dev2.id }!
        let d3After = afterTags.first { $0.id == dev3.id }!

        #expect(d1After.tags.contains("production"))
        #expect(d1After.tags.contains("alpha"))
        #expect(d2After.tags.contains("tier-1"))
        #expect(!d3After.tags.contains("production"))

        // 2. Bulk remove tag
        try manager.bulkRemoveTags(ids: ids, tags: ["tier-1"])
        let afterRemove = try manager.listDevices()
        #expect(!afterRemove.first { $0.id == dev1.id }!.tags.contains("tier-1"))

        // 3. Bulk assign site
        try manager.bulkAssignSite(ids: ids, site: "Campus-West")
        let afterSite = try manager.listDevices()
        #expect(afterSite.first { $0.id == dev1.id }?.location == "Campus-West")
        #expect(afterSite.first { $0.id == dev2.id }?.location == "Campus-West")
        #expect(afterSite.first { $0.id == dev3.id }?.location == "SiteB")

        // 4. Bulk delete
        try manager.bulkDeleteDevices(ids: [dev1.id, dev2.id])
        let afterDelete = try manager.listDevices()
        #expect(afterDelete.count == 1)
        #expect(afterDelete.first?.id == dev3.id)

        try? FileManager.default.removeItem(atPath: tempDBPath)
    }

    @Test("Canvas Node Coordinate Persistence in SQLite")
    func testTopologyNodePositionPersistence() throws {
        let tempDBPath = FileManager.default.temporaryDirectory.appendingPathComponent("test_canvas_\(UUID().uuidString).sqlite").path
        let db = try SQLiteDatabase(path: tempDBPath)
        let manager = DeviceManager(database: db)

        // Save node positions for enterprise preset
        try manager.saveNodePosition(preset: "enterprise", nodeId: "core-rtr01", position: CGPoint(x: 450.5, y: 120.0))
        try manager.saveNodePosition(preset: "enterprise", nodeId: "dist-sw01", position: CGPoint(x: 250.0, y: 280.0))

        // Load
        let loaded = try manager.loadNodePositions(preset: "enterprise")
        #expect(loaded.count == 2)
        #expect(loaded["core-rtr01"]?.x == 450.5)
        #expect(loaded["core-rtr01"]?.y == 120.0)
        #expect(loaded["dist-sw01"]?.x == 250.0)
        #expect(loaded["dist-sw01"]?.y == 280.0)

        // Clear / Reset
        try manager.clearNodePositions(preset: "enterprise")
        let cleared = try manager.loadNodePositions(preset: "enterprise")
        #expect(cleared.isEmpty)

        try? FileManager.default.removeItem(atPath: tempDBPath)
    }
}

