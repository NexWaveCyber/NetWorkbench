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
            target: "172.16.16.1",
            targetName: "Core Gateway",
            alertType: .targetDown,
            measuredValue: 100.0,
            thresholdValue: 50.0,
            message: "Host is unreachable"
        )
        #expect(alert2.alertType.badgeColor == "#EF4444")
    }
}
