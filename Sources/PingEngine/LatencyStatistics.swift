import Foundation

/// Statistical latency analysis including percentiles and RFC 3550 jitter.
public struct LatencyStatistics: Sendable, Hashable {
    public let sent: Int
    public let received: Int
    public let lost: Int
    public let lossPercentage: Double
    public let minMs: Double
    public let maxMs: Double
    public let avgMs: Double
    public let medianMs: Double
    public let p95Ms: Double
    public let p99Ms: Double
    public let jitterMs: Double
    public let rawSamples: [Double]

    public enum ProbeProtocol: String, Sendable, Hashable, Codable {
        case icmp = "ICMP"
        case tcp = "TCP"
    }

    public let probeProtocol: ProbeProtocol
    public let isFallback: Bool

    public init(
        samples: [Double],
        sentCount: Int,
        probeProtocol: ProbeProtocol = .icmp,
        isFallback: Bool = false
    ) {
        self.rawSamples = samples
        self.sent = sentCount
        self.received = samples.count
        self.lost = max(0, sentCount - samples.count)
        self.lossPercentage = sentCount > 0 ? (Double(self.lost) / Double(sentCount)) * 100.0 : 0.0
        self.probeProtocol = probeProtocol
        self.isFallback = isFallback

        guard !samples.isEmpty else {
            self.minMs = 0
            self.maxMs = 0
            self.avgMs = 0
            self.medianMs = 0
            self.p95Ms = 0
            self.p99Ms = 0
            self.jitterMs = 0
            return
        }

        let sorted = samples.sorted()
        self.minMs = sorted.first!
        self.maxMs = sorted.last!
        self.avgMs = sorted.reduce(0, +) / Double(sorted.count)
        self.medianMs = LatencyStatistics.percentile(sorted: sorted, p: 0.50)
        self.p95Ms = LatencyStatistics.percentile(sorted: sorted, p: 0.95)
        self.p99Ms = LatencyStatistics.percentile(sorted: sorted, p: 0.99)
        self.jitterMs = LatencyStatistics.calculateRFC3550Jitter(samples: samples)
    }

    private static func percentile(sorted: [Double], p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let index = Double(sorted.count - 1) * p
        let lower = Int(floor(index))
        let upper = Int(ceil(index))
        if lower == upper { return sorted[lower] }
        let weight = index - Double(lower)
        return sorted[lower] * (1.0 - weight) + sorted[upper] * weight
    }

    /// RFC 3550 Jitter: J(i) = J(i-1) + (|D(i-1,i)| - J(i-1))/16
    private static func calculateRFC3550Jitter(samples: [Double]) -> Double {
        guard samples.count > 1 else { return 0 }
        var jitter: Double = 0
        for i in 1..<samples.count {
            let diff = abs(samples[i] - samples[i - 1])
            jitter += (diff - jitter) / 16.0
        }
        return jitter
    }
}
