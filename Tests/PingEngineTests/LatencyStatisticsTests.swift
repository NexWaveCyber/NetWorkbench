import Testing
@testable import PingEngine

@Suite("LatencyStatistics and RFC 3550 Jitter")
struct LatencyStatisticsTests {
    @Test("Percentile and Jitter Math")
    func testLatencyStats() {
        let samples = [10.0, 12.0, 15.0, 14.0, 20.0, 11.0, 13.0, 18.0]
        let stats = LatencyStatistics(samples: samples, sentCount: 10)

        #expect(stats.sent == 10)
        #expect(stats.received == 8)
        #expect(stats.lost == 2)
        #expect(stats.lossPercentage == 20.0)

        #expect(stats.minMs == 10.0)
        #expect(stats.maxMs == 20.0)
        #expect(stats.avgMs > 13.0 && stats.avgMs < 15.0)
        #expect(stats.medianMs >= 12.0 && stats.medianMs <= 14.5)
        #expect(stats.p95Ms > 18.0)
        #expect(stats.jitterMs > 0)
    }

    @Test("Empty Samples Safety")
    func testEmptySamples() {
        let stats = LatencyStatistics(samples: [], sentCount: 5)
        #expect(stats.received == 0)
        #expect(stats.lost == 5)
        #expect(stats.lossPercentage == 100.0)
        #expect(stats.minMs == 0.0)
        #expect(stats.maxMs == 0.0)
        #expect(stats.medianMs == 0.0)
        #expect(stats.jitterMs == 0.0)
    }
}
