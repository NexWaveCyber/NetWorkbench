import Testing
import Foundation
@testable import PersistenceKit

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
}
