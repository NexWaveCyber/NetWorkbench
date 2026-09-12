import Testing
import Foundation
@testable import DeviceKit
@testable import PersistenceKit
@testable import SecurityKit

@Suite("DeviceKit Tests")
struct DeviceKitTests {

    @Test("OUI Vendor Resolution")
    func testOUIResolution() {
        #expect(OUIResolver.resolve(mac: "00:00:0c:12:34:56") == "Cisco Systems")
        #expect(OUIResolver.resolve(mac: "00-1C-73-AA-BB-CC") == "Arista Networks")
        #expect(OUIResolver.resolve(mac: "00:19:e2:11:22:33") == "Juniper Networks")
        #expect(OUIResolver.resolve(mac: "f8:ff:c2:01:02:03") == "Apple")
        #expect(OUIResolver.resolve(mac: "24:a4:3c:99:88:77") == "Ubiquiti Networks")
        #expect(OUIResolver.resolve(mac: "00:09:0f:55:44:33") == "Fortinet")
        #expect(OUIResolver.resolve(mac: "00:0c:29:1a:2b:3c") == "VMware")
        #expect(OUIResolver.resolve(mac: "b8:27:eb:11:22:33") == "Raspberry Pi")
        #expect(OUIResolver.resolve(mac: "aa:bb:cc:dd:ee:ff") == nil)

        #expect(OUIResolver.inferVendor(mac: "00:00:0c:00:00:00") == .cisco)
        #expect(OUIResolver.inferVendor(mac: "00:1c:73:00:00:00") == .arista)
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

    @Test("Device CRUD and Baselines in SQLite")
    func testDeviceCRUDAndBaselines() throws {
        let tempDBPath = FileManager.default.temporaryDirectory.appendingPathComponent("test_device_\(UUID().uuidString).sqlite").path
        let db = try SQLiteDatabase(path: tempDBPath)
        let manager = DeviceManager(database: db)

        // Create
        let device = NetworkDevice(
            displayName: "Core-Switch-01",
            hostname: "core-sw01.corp.internal",
            managementIP: "10.0.0.1",
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

        // List
        let list = try manager.listDevices()
        #expect(list.count == 1)
        #expect(list[0].displayName == "Core-Switch-01")
        #expect(list[0].vendor == .cisco)
        #expect(list[0].tags.count == 3)
        #expect(list[0].snmpConfig?.community == "corp-snmp")

        // Update
        var updated = list[0]
        updated.displayName = "Core-Switch-01-Renamed"
        updated.status = .online
        try manager.updateDevice(updated)

        let reList = try manager.listDevices()
        #expect(reList[0].displayName == "Core-Switch-01-Renamed")

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
}
