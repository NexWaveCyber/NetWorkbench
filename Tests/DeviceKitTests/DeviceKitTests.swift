import Testing
import Foundation
@testable import DeviceKit
@testable import PersistenceKit
@testable import SecurityKit

@Suite("DeviceKit Tests")
struct DeviceKitTests {

    @Test("OUI Vendor Resolution and Private MAC Detection")
    func testOUIResolution() {
        #expect(OUIResolver.resolve(mac: "00:00:0c:12:34:56") == "Cisco Systems")
        #expect(OUIResolver.resolve(mac: "00-1C-73-AA-BB-CC") == "Arista Networks")
        #expect(OUIResolver.resolve(mac: "00:19:e2:11:22:33") == "Juniper Networks")
        #expect(OUIResolver.resolve(mac: "f8:ff:c2:01:02:03") == "Apple")
        #expect(OUIResolver.resolve(mac: "24:a4:3c:99:88:77") == "Ubiquiti Networks")
        #expect(OUIResolver.resolve(mac: "00:09:0f:55:44:33") == "Fortinet")
        #expect(OUIResolver.resolve(mac: "00:0c:29:1a:2b:3c") == "VMware")
        #expect(OUIResolver.resolve(mac: "b8:27:eb:11:22:33") == "Raspberry Pi")

        // Private / Randomized MAC detection (bit 1 of first octet is set)
        #expect(OUIResolver.isLocallyAdministered(mac: "aa:bb:cc:dd:ee:ff") == true)
        #expect(OUIResolver.isLocallyAdministered(mac: "02:00:00:00:00:00") == true)
        #expect(OUIResolver.isLocallyAdministered(mac: "00:00:0c:12:34:56") == false)
        #expect(OUIResolver.resolve(mac: "aa:bb:cc:dd:ee:ff") == "Private MAC (Locally Administered)")

        // Non-locally-administered unassigned MAC
        #expect(OUIResolver.resolve(mac: "00:00:01:dd:ee:ff") == nil)

        // Well-known home & enterprise router vendors
        #expect(OUIResolver.resolve(mac: "68:7f:f0:55:35:45") == "Linksys / Belkin")
        #expect(OUIResolver.resolve(mac: "00:14:bf:12:34:56") == "Linksys")
        #expect(OUIResolver.resolve(mac: "50:c7:bf:11:22:33") == "TP-Link")
        #expect(OUIResolver.resolve(mac: "00:09:5b:aa:bb:cc") == "Netgear")
        #expect(OUIResolver.resolve(mac: "00:1e:8c:12:34:56") == "ASUS")

        #expect(OUIResolver.inferVendor(mac: "00:00:0c:00:00:00") == .cisco)
        #expect(OUIResolver.inferVendor(mac: "00:1c:73:00:00:00") == .arista)
        #expect(OUIResolver.inferVendor(mac: "68:7f:f0:55:35:45") == .linksys)
        #expect(OUIResolver.inferVendor(mac: "00:14:bf:11:22:33") == .linksys)
        #expect(OUIResolver.inferVendor(mac: "00:09:5b:aa:bb:cc") == .netgear)
        #expect(OUIResolver.inferVendor(mac: "50:c7:bf:11:22:33") == .tpLink)
        #expect(OUIResolver.inferVendor(mac: "00:1e:8c:11:22:33") == .asus)
        #expect(OUIResolver.inferVendor(fromName: "Linksys / Belkin") == .linksys)
        #expect(OUIResolver.inferVendor(mac: "ff:ff:ff:ff:ff:ff") == .generic)
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
        #expect(appleNeighbor?.ouiVendor == "Apple")

        let ciscoNeighbor = neighbors.first { $0.ipAddress == "10.0.0.1" }
        #expect(ciscoNeighbor != nil)
        #expect(ciscoNeighbor?.macAddress == "00:00:0c:11:22:33")
        #expect(ciscoNeighbor?.ouiVendor == "Cisco Systems")
    }

    @Test("NDP IPv6 Output Parsing")
    func testNDPOutputParsing() async {
        let sampleNDP = """
        Neighbor                             Linklayer Address  Netif Expire    St Flgs Prbs
        fe80::1%en0                          0:1c:73:a1:b2:c3   en0   23h59m59s R
        2001:db8::50                         f8:ff:c2:12:34:56  en0   23h58m12s R
        fe80::2%en0                          (incomplete)       en0   expired   I
        """

        let engine = LocalDiscoveryEngine()
        let neighbors = await engine.parseNDPOutput(sampleNDP)

        #expect(neighbors.count == 2)
        #expect(neighbors[0].ipAddress == "fe80::1")
        #expect(neighbors[0].macAddress == "00:1c:73:a1:b2:c3")
        #expect(neighbors[0].ouiVendor == "Arista Networks")
        #expect(neighbors[1].ipAddress == "2001:db8::50")
        #expect(neighbors[1].ouiVendor == "Apple")
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
}
