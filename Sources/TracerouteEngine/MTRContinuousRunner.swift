import Foundation
import NetworkCore

public struct MTRHopSnapshot: Sendable, Identifiable {
    public var id: Int { hopNumber }
    public let hopNumber: Int
    public var primaryAddress: String?
    public var allDiscoveredAddresses: Set<String>
    public var hostname: String?
    public var sent: Int
    public var received: Int
    public var lastRTT: Double?
    public var bestRTT: Double?
    public var worstRTT: Double?
    public var rttSamples: [Double]
    public var history: [Double?] // For sparkline (last 30 probes, nil = timeout)
    public var lastJitter: Double

    public var lossPercent: Double {
        guard sent > 0 else { return 0.0 }
        let lost = sent - received
        return (Double(lost) / Double(sent)) * 100.0
    }

    public var avgRTT: Double {
        guard !rttSamples.isEmpty else { return 0.0 }
        return rttSamples.reduce(0.0, +) / Double(rttSamples.count)
    }

    public var stDev: Double {
        guard rttSamples.count > 1 else { return 0.0 }
        let mean = avgRTT
        let sumSquaredDiff = rttSamples.reduce(0.0) { $0 + pow($1 - mean, 2) }
        return sqrt(sumSquaredDiff / Double(rttSamples.count - 1))
    }

    public var hasDrift: Bool {
        return allDiscoveredAddresses.count > 1
    }

    public init(hopNumber: Int) {
        self.hopNumber = hopNumber
        self.primaryAddress = nil
        self.allDiscoveredAddresses = []
        self.hostname = nil
        self.sent = 0
        self.received = 0
        self.lastRTT = nil
        self.bestRTT = nil
        self.worstRTT = nil
        self.rttSamples = []
        self.history = []
        self.lastJitter = 0.0
    }
}

public struct MTRReport: Sendable {
    public let target: String
    public let roundCount: Int
    public let isRunning: Bool
    public let hops: [MTRHopSnapshot]
    public let lastUpdated: Date

    public init(target: String, roundCount: Int, isRunning: Bool, hops: [MTRHopSnapshot], lastUpdated: Date = Date()) {
        self.target = target
        self.roundCount = roundCount
        self.isRunning = isRunning
        self.hops = hops
        self.lastUpdated = lastUpdated
    }
}

public actor MTRContinuousRunner {
    private var target: String = ""
    private var maxHops: Int = 15
    private var intervalSeconds: Double = 1.0
    private var isRunning: Bool = false
    private var loopTask: Task<Void, Never>? = nil
    private var hopData: [Int: MTRHopSnapshot] = [:]
    private var roundCount: Int = 0
    private var onUpdate: (@Sendable (MTRReport) -> Void)?

    public init() {}

    public func start(
        target: String,
        maxHops: Int = 15,
        intervalSeconds: Double = 1.0,
        onUpdate: @escaping @Sendable (MTRReport) -> Void
    ) {
        if self.target != target {
            self.hopData.removeAll()
            self.roundCount = 0
        }
        self.target = target
        self.maxHops = maxHops
        self.intervalSeconds = max(0.5, intervalSeconds)
        self.isRunning = true
        self.onUpdate = onUpdate

        loopTask?.cancel()
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { break }
                let active = await self.checkIsRunning()
                guard active else { break }

                await self.executeRound()

                let sleepSec = await self.getInterval()
                let nanoSec = UInt64(sleepSec * 1_000_000_000.0)
                try? await Task.sleep(nanoseconds: nanoSec)
            }
        }
    }

    public func pause() {
        self.isRunning = false
        self.loopTask?.cancel()
        self.loopTask = nil
        publishCurrent()
    }

    public func reset() {
        self.isRunning = false
        self.loopTask?.cancel()
        self.loopTask = nil
        self.hopData.removeAll()
        self.roundCount = 0
        publishCurrent()
    }

    private func checkIsRunning() -> Bool {
        return self.isRunning
    }

    private func getInterval() -> Double {
        return self.intervalSeconds
    }

    private func executeRound() async {
        roundCount += 1
        let runner = TracerouteRunner()
        let observation = await runner.trace(target: target, maxHops: maxHops)

        var seenHopNums = Set<Int>()

        for hop in observation.hops {
            seenHopNums.insert(hop.hopNumber)
            var stats = hopData[hop.hopNumber] ?? MTRHopSnapshot(hopNumber: hop.hopNumber)
            stats.sent += 1

            if let rtt = hop.rttMs, let addr = hop.address {
                stats.received += 1
                stats.allDiscoveredAddresses.insert(addr)
                stats.primaryAddress = addr

                // RFC 3550 Jitter calculation: D(i,j) = |(R_j - S_j) - (R_i - S_i)|; J = J + (|D| - J)/16
                if let last = stats.lastRTT {
                    let diff = abs(rtt - last)
                    stats.lastJitter += (diff - stats.lastJitter) / 16.0
                }

                stats.lastRTT = rtt
                stats.bestRTT = min(stats.bestRTT ?? rtt, rtt)
                stats.worstRTT = max(stats.worstRTT ?? rtt, rtt)
                stats.rttSamples.append(rtt)
                if stats.rttSamples.count > 100 {
                    stats.rttSamples.removeFirst()
                }

                stats.history.append(rtt)
                if stats.history.count > 30 {
                    stats.history.removeFirst()
                }
            } else {
                // Timeout
                stats.history.append(nil)
                if stats.history.count > 30 {
                    stats.history.removeFirst()
                }
            }

            hopData[hop.hopNumber] = stats
        }

        publishCurrent()
    }

    private func publishCurrent() {
        let sortedHops = hopData.values.sorted { $0.hopNumber < $1.hopNumber }
        let report = MTRReport(
            target: target,
            roundCount: roundCount,
            isRunning: isRunning,
            hops: sortedHops
        )
        onUpdate?(report)
    }
}
