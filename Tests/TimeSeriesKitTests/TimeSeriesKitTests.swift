import Testing
import Foundation
@testable import TimeSeriesKit
@testable import PersistenceKit

@Suite("TimeSeriesKit Storage & Aggregation Tests")
struct TimeSeriesKitTests {

    @Test("TimeRange Start Date and Bucket Count")
    func testTimeRangeCalculations() {
        let now = Date()
        let tenMin = TimeRange.last10Minutes.startDate(from: now)
        #expect(abs(now.timeIntervalSince(tenMin) - 600) < 0.1)

        let oneHour = TimeRange.lastHour.startDate(from: now)
        #expect(abs(now.timeIntervalSince(oneHour) - 3600) < 0.1)

        let oneDay = TimeRange.last24Hours.startDate(from: now)
        #expect(abs(now.timeIntervalSince(oneDay) - 86400) < 0.1)

        #expect(TimeRange.last10Minutes.targetBucketCount == 60)
        #expect(TimeRange.last24Hours.targetBucketCount == 96)
    }

    @Test("Downsampling Buckets and Packet Loss Math")
    func testDownsamplingBuckets() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test_ts_\(UUID().uuidString).sqlite").path
        let db = try SQLiteDatabase(path: dbPath)
        let repo = TimeSeriesRepository(database: db)

        let baseTime = Date()
        var samples: [LatencySample] = []

        // 10 samples: 8 valid (10ms to 80ms), 2 timeouts
        for i in 0..<8 {
            samples.append(LatencySample(
                target: "10.0.0.1",
                timestamp: baseTime.addingTimeInterval(Double(i * 10)),
                latencyMs: Double((i + 1) * 10),
                isTimeout: false,
                jitterMs: 2.0
            ))
        }
        samples.append(LatencySample(
            target: "10.0.0.1",
            timestamp: baseTime.addingTimeInterval(85),
            latencyMs: nil,
            isTimeout: true
        ))
        samples.append(LatencySample(
            target: "10.0.0.1",
            timestamp: baseTime.addingTimeInterval(95),
            latencyMs: nil,
            isTimeout: true
        ))

        let buckets = repo.downsample(
            samples: samples,
            from: baseTime,
            to: baseTime.addingTimeInterval(100),
            bucketCount: 1
        )

        #expect(buckets.count == 1)
        let b = buckets[0]
        #expect(b.sampleCount == 10)
        #expect(b.packetLossPct == 20.0) // 2 out of 10 timeouts = 20%
        #expect(b.minMs == 10.0)
        #expect(b.maxMs == 80.0)
        #expect(b.avgMs == 45.0) // (10+20+30+40+50+60+70+80)/8 = 360/8 = 45.0
    }

    @Test("SQLite Repository Insertion and Query")
    func testRepositoryCRUD() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test_crud_\(UUID().uuidString).sqlite").path
        let db = try SQLiteDatabase(path: dbPath)
        let repo = TimeSeriesRepository(database: db)

        let now = Date()
        let sample1 = LatencySample(target: "1.1.1.1", timestamp: now, latencyMs: 12.5, isTimeout: false, jitterMs: 1.2)
        let sample2 = LatencySample(target: "1.1.1.1", timestamp: now.addingTimeInterval(2), latencyMs: 14.1, isTimeout: false, jitterMs: 1.6)
        let sample3 = LatencySample(target: "1.1.1.1", timestamp: now.addingTimeInterval(4), latencyMs: nil, isTimeout: true, jitterMs: nil)

        try repo.insertBatch(samples: [sample1, sample2, sample3])

        let fetched = try repo.fetchRaw(target: "1.1.1.1", from: now.addingTimeInterval(-1), to: now.addingTimeInterval(10))
        #expect(fetched.count == 3)
        #expect(fetched[0].latencyMs == 12.5)
        #expect(fetched[2].isTimeout == true)

        // SLA Alert recording
        let alert = SLAMonitorAlert(
            target: "1.1.1.1",
            targetName: "Cloudflare DNS",
            timestamp: now,
            alertType: .packetLoss,
            measuredValue: 15.0,
            thresholdValue: 5.0,
            message: "Packet loss breached 5% SLA"
        )
        try repo.recordAlert(alert: alert)

        let alerts = try repo.fetchAlerts(target: "1.1.1.1")
        #expect(alerts.count == 1)
        #expect(alerts[0].alertType == .packetLoss)
        #expect(alerts[0].measuredValue == 15.0)
    }

    @Test("SLA Alert Model Properties")
    func testSLAAlertProperties() {
        let alert1 = SLAMonitorAlert(
            target: "172.16.16.1",
            targetName: "Core Gateway",
            alertType: .latencySpike,
            measuredValue: 125.0,
            thresholdValue: 50.0,
            message: "High latency detected"
        )
        #expect(alert1.alertType.badgeColor == "#F59E0B")

        let alert2 = SLAMonitorAlert(
            target: "192.168.10.1",
            targetName: "Core Gateway",
            alertType: .targetDown,
            measuredValue: 100.0,
            thresholdValue: 50.0,
            message: "Host is unreachable"
        )
        #expect(alert2.alertType.badgeColor == "#EF4444")
    }

    @Test("Monitor Target CRUD Persistence")
    func testTargetCRUD() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test_target_crud_\(UUID().uuidString).sqlite").path
        let db = try SQLiteDatabase(path: dbPath)
        let repo = TimeSeriesRepository(database: db)

        let target1 = MonitorTargetConfig(
            target: "192.168.10.1",
            name: "Local Gateway Router",
            intervalSeconds: 2.0,
            latencyThresholdMs: 25.0,
            packetLossThresholdPct: 4.0,
            probeProtocol: .icmp
        )
        let target2 = MonitorTargetConfig(
            target: "api.github.com",
            name: "GitHub API HTTPS",
            intervalSeconds: 5.0,
            latencyThresholdMs: 100.0,
            packetLossThresholdPct: 5.0,
            probeProtocol: .tcp,
            port: 443
        )

        try repo.insertOrUpdateTarget(config: target1)
        try repo.insertOrUpdateTarget(config: target2)

        var targets = try repo.fetchTargets()
        #expect(targets.count == 2)
        #expect(targets[0].target == "192.168.10.1")
        #expect(targets[0].probeProtocol == .icmp)
        #expect(targets[1].target == "api.github.com")
        #expect(targets[1].probeProtocol == .tcp)
        #expect(targets[1].port == 443)

        // Update target1
        var updated = target1
        updated.name = "Renamed Gateway"
        updated.latencyThresholdMs = 30.0
        try repo.insertOrUpdateTarget(config: updated)

        targets = try repo.fetchTargets()
        #expect(targets.count == 2)
        let found = targets.first(where: { $0.id == target1.id })
        #expect(found?.name == "Renamed Gateway")
        #expect(found?.latencyThresholdMs == 30.0)

        // Delete target2
        try repo.deleteTarget(id: target2.id)
        targets = try repo.fetchTargets()
        #expect(targets.count == 1)
        #expect(targets[0].id == target1.id)
    }

    @Test("Alert Acknowledgment and Clear All")
    func testAlertManagement() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test_alert_mgmt_\(UUID().uuidString).sqlite").path
        let db = try SQLiteDatabase(path: dbPath)
        let repo = TimeSeriesRepository(database: db)

        let alertId = UUID()
        let alert = SLAMonitorAlert(
            id: alertId,
            target: "1.1.1.1",
            targetName: "Cloudflare",
            alertType: .latencySpike,
            measuredValue: 120.0,
            thresholdValue: 50.0,
            message: "Latency spike detected"
        )
        try repo.recordAlert(alert: alert)

        var alerts = try repo.fetchAlerts(target: "1.1.1.1")
        #expect(alerts.count == 1)
        #expect(alerts[0].isAcknowledged == false)

        // Acknowledge alert
        try repo.acknowledgeAlert(id: alertId)
        alerts = try repo.fetchAlerts(target: "1.1.1.1")
        #expect(alerts.count == 1)
        #expect(alerts[0].isAcknowledged == true)

        // Clear all alerts
        try repo.clearAllAlerts(target: "1.1.1.1")
        alerts = try repo.fetchAlerts(target: "1.1.1.1")
        #expect(alerts.isEmpty)
    }

    @Test("CSV Export Generation")
    func testCSVExport() {
        let now = Date()
        let bucket1 = AggregatedBucket(
            timestamp: now,
            minMs: 1.2,
            avgMs: 2.5,
            maxMs: 5.1,
            jitterMs: 0.8,
            packetLossPct: 0.0,
            sampleCount: 20
        )
        let csv = [bucket1].toCSV(target: "192.168.10.1", targetName: "Gateway")
        #expect(csv.contains("Timestamp,Target,Name,MinMs,AvgMs,MaxMs,JitterMs,PacketLossPct,SampleCount"))
        #expect(csv.contains("192.168.10.1,Gateway,1.20,2.50,5.10,0.80,0.0,20"))
    }

    @Test("Retention Pruning")
    func testRetentionPruning() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test_prune_\(UUID().uuidString).sqlite").path
        let db = try SQLiteDatabase(path: dbPath)
        let repo = TimeSeriesRepository(database: db)

        let oldDate = Date().addingTimeInterval(-10 * 86400) // 10 days ago
        let recentDate = Date().addingTimeInterval(-2 * 86400) // 2 days ago

        let oldSample = LatencySample(target: "8.8.8.8", timestamp: oldDate, latencyMs: 20.0)
        let recentSample = LatencySample(target: "8.8.8.8", timestamp: recentDate, latencyMs: 22.0)

        try repo.insertBatch(samples: [oldSample, recentSample])

        // Prune older than 7 days
        try repo.pruneOldSamples(olderThanDays: 7)

        let remaining = try repo.fetchRaw(target: "8.8.8.8", from: Date().addingTimeInterval(-30 * 86400), to: Date())
        #expect(remaining.count == 1)
        #expect(remaining[0].id == recentSample.id)
    }
}
