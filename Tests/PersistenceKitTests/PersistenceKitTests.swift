import Testing
import Foundation
@testable import PersistenceKit
@testable import InvestigationKit

@Suite("PersistenceKit SQLite WAL Storage")
struct PersistenceKitTests {
    @Test("Database Migration and CRUD Operations")
    func testPersistenceCRUD() throws {
        // Use temporary file for test isolation
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test_\(UUID().uuidString).sqlite").path

        let db = try SQLiteDatabase(path: dbPath)
        let invRepo = InvestigationRepository(database: db)
        let histRepo = DiagnosticHistoryRepository(database: db)

        // 1. Test Investigation Insert & Fetch
        let invId = UUID().uuidString
        let inv = InvestigationRecord(
            id: invId,
            title: "Switch Gi1/0/24 CRC Errors",
            description: "Interface CRC errors escalating",
            severity: "High"
        )
        try invRepo.insert(inv)

        let fetched = try invRepo.fetchAll()
        #expect(fetched.contains(where: { $0.id == invId && $0.title == "Switch Gi1/0/24 CRC Errors" }))

        // 2. Test Timeline Event
        let event = TimelineEventRecord(
            investigationId: invId,
            title: "Cable Tested",
            detail: "Physical layer verified with Fluke tester",
            category: "Manual"
        )
        try invRepo.addTimelineEvent(event)

        let events = try invRepo.fetchEvents(forInvestigationId: invId)
        #expect(events.count == 1)
        #expect(events.first?.title == "Cable Tested")

        // 3. Test Diagnostic History
        let hist = DiagnosticHistoryRecord(
            target: "10.0.0.1",
            targetType: "IPv4 Address",
            dnsHealthy: true,
            pingLatency: 1.4,
            packetLoss: 0.0,
            tcpHealthy: true,
            tlsHealthy: true,
            httpStatus: 200,
            summary: "Healthy gateway",
            rawJson: "{}"
        )
        try histRepo.record(hist)

        let recent = try histRepo.fetchRecent(limit: 10)
        #expect(recent.contains(where: { $0.target == "10.0.0.1" }))

        // Clean up
        try? FileManager.default.removeItem(atPath: dbPath)
    }

    @Test("Investigation Bundle (.nwi) Export, Import, and Database Roundtrip")
    func testInvestigationBundleRoundtrip() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath1 = tempDir.appendingPathComponent("test_origin_\(UUID().uuidString).sqlite").path
        let dbPath2 = tempDir.appendingPathComponent("test_target_\(UUID().uuidString).sqlite").path
        let bundleFileUrl = tempDir.appendingPathComponent("incident_bundle_\(UUID().uuidString).nwi")

        let originDb = try SQLiteDatabase(path: dbPath1)
        let targetDb = try SQLiteDatabase(path: dbPath2)

        let originManager = InvestigationManager(database: originDb)
        let targetManager = InvestigationManager(database: targetDb)

        // 1. Create origin investigation with timeline notes
        let inv = try originManager.createInvestigation(
            title: "BGP Flapping on AS64500",
            description: "Transit link peer resetting every 45s",
            severity: .critical
        )

        // 2. Export investigation bundle to file
        let sampleConfig = AttachedConfigFile(
            filename: "edge_router_running_config.txt",
            deviceHostname: "edge-rt01.corp",
            content: "router bgp 64500\n neighbor 192.0.2.1 remote-as 65000\n timers 10 30"
        )
        try originManager.exportInvestigationBundle(
            id: inv.id,
            to: bundleFileUrl,
            notes: "Exported bundle for tier 3 Escalation review",
            configFiles: [sampleConfig],
            pcapData: "FAKE_PCAP_DATA".data(using: .utf8)
        )

        #expect(FileManager.default.fileExists(atPath: bundleFileUrl.path))

        // 3. Import bundle into target database
        let importedInv = try targetManager.importInvestigationBundle(from: bundleFileUrl)
        #expect(importedInv.id == inv.id)
        #expect(importedInv.title == "BGP Flapping on AS64500")
        #expect(importedInv.severity == .critical)

        // Verify loaded bundle structure directly
        let loadedBundle = try InvestigationBundleManager.loadBundle(from: bundleFileUrl)
        #expect(loadedBundle.investigation.title == "BGP Flapping on AS64500")
        #expect(loadedBundle.timelineEvents.count >= 1)
        #expect(loadedBundle.attachedConfigFiles.count == 1)
        #expect(loadedBundle.attachedConfigFiles.first?.filename == "edge_router_running_config.txt")
        #expect(loadedBundle.notes == "Exported bundle for tier 3 Escalation review")
        #expect(loadedBundle.packetCaptureBase64 != nil)

        // Verify target database has the investigation and timeline
        let targetList = try targetManager.listInvestigations()
        #expect(targetList.contains(where: { $0.id == inv.id }))

        let targetTimeline = try targetManager.fetchTimeline(forInvestigationId: inv.id)
        #expect(!targetTimeline.isEmpty)

        // Clean up temporary files
        try? FileManager.default.removeItem(atPath: dbPath1)
        try? FileManager.default.removeItem(atPath: dbPath2)
        try? FileManager.default.removeItem(atPath: bundleFileUrl.path)
    }
}
