import Foundation
import NetworkCore

public struct HopRecord: Hashable, Sendable, Identifiable {
    public let id: Int // Hop number
    public let hopNumber: Int
    public let address: String?
    public let hostname: String?
    public let rttMs: Double?
    public let isTimeout: Bool

    public init(hopNumber: Int, address: String?, hostname: String?, rttMs: Double?, isTimeout: Bool) {
        self.id = hopNumber
        self.hopNumber = hopNumber
        self.address = address
        self.hostname = hostname
        self.rttMs = rttMs
        self.isTimeout = isTimeout
    }
}

public struct PathObservation: Sendable {
    public let target: String
    public let hops: [HopRecord]
    public let totalHops: Int
    public let finalHopReached: Bool
    public let latencyJumpHop: Int?
    public let latencyDeltaMs: Double?

    public init(target: String, hops: [HopRecord], finalHopReached: Bool) {
        self.target = target
        self.hops = hops
        self.totalHops = hops.count
        self.finalHopReached = finalHopReached

        // Detect significant latency jump (> 50ms increase between responding hops)
        var detectedJumpHop: Int? = nil
        var detectedDelta: Double? = nil

        var prevRtt: Double? = nil
        for hop in hops where !hop.isTimeout && hop.rttMs != nil {
            if let prev = prevRtt, let cur = hop.rttMs {
                let delta = cur - prev
                if delta > 50.0 && detectedJumpHop == nil {
                    detectedJumpHop = hop.hopNumber
                    detectedDelta = delta
                }
            }
            prevRtt = hop.rttMs
        }

        self.latencyJumpHop = detectedJumpHop
        self.latencyDeltaMs = detectedDelta
    }
}
