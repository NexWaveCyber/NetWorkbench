import Foundation

public struct CIDRAggregatorResult: Sendable {
    public let originalNetworks: [IPNetwork]
    public let aggregatedNetworks: [IPNetwork]

    public var originalCount: Int { originalNetworks.count }
    public var summaryCount: Int { aggregatedNetworks.count }
    public var reductionPercent: Double {
        guard originalCount > 0 else { return 0.0 }
        return Double(originalCount - summaryCount) / Double(originalCount) * 100.0
    }

    public init(originalNetworks: [IPNetwork], aggregatedNetworks: [IPNetwork]) {
        self.originalNetworks = originalNetworks
        self.aggregatedNetworks = aggregatedNetworks
    }
}

public enum CIDRAggregator {
    /// Summarizes/aggregates a collection of IPv4 subnets into minimal contiguous supernets.
    public static func aggregate(_ inputNetworks: [IPNetwork]) -> CIDRAggregatorResult {
        guard !inputNetworks.isEmpty else {
            return CIDRAggregatorResult(originalNetworks: [], aggregatedNetworks: [])
        }

        // 1. Remove duplicates and subnets that are completely contained within a larger subnet
        var uniqueNets = Array(Set(inputNetworks))
        uniqueNets.sort { (a: IPNetwork, b: IPNetwork) -> Bool in
            let aRaw = a.ipv4NetworkAddress?.rawValue ?? 0
            let bRaw = b.ipv4NetworkAddress?.rawValue ?? 0
            if aRaw != bRaw {
                return aRaw < bRaw
            }
            return a.prefixLength < b.prefixLength // wider prefix first
        }

        var filtered: [IPNetwork] = []
        for net in uniqueNets {
            let isContained = filtered.contains { (existing: IPNetwork) -> Bool in
                guard let netAddr = net.ipv4NetworkAddress,
                      let bcastAddr = net.ipv4BroadcastAddress else { return false }
                return existing.contains(.v4(netAddr)) && existing.contains(.v4(bcastAddr))
            }
            if !isContained {
                filtered.append(net)
            }
        }

        // 2. Iteratively merge partner pairs
        var current = filtered
        var changed = true

        while changed {
            changed = false
            current.sort { (a: IPNetwork, b: IPNetwork) -> Bool in
                if a.prefixLength != b.prefixLength {
                    return a.prefixLength > b.prefixLength // merge deeper prefixes first
                }
                let aRaw = a.ipv4NetworkAddress?.rawValue ?? 0
                let bRaw = b.ipv4NetworkAddress?.rawValue ?? 0
                return aRaw < bRaw
            }

            var nextRound: [IPNetwork] = []
            var skipIndices = Set<Int>()

            for i in 0..<current.count {
                if skipIndices.contains(i) { continue }

                let netA = current[i]
                guard let aRaw = netA.ipv4NetworkAddress?.rawValue else {
                    nextRound.append(netA)
                    continue
                }

                var merged = false

                if i + 1 < current.count {
                    for j in (i + 1)..<current.count {
                        if skipIndices.contains(j) { continue }
                        let netB = current[j]
                        guard let bRaw = netB.ipv4NetworkAddress?.rawValue else { continue }

                        if netA.prefixLength == netB.prefixLength && netA.prefixLength > 0 {
                            let prefix = netA.prefixLength
                            let step = UInt32(1) << (32 - prefix)
                            let partnerRaw = aRaw ^ step

                            if bRaw == partnerRaw {
                                // Check if base is aligned to prefix - 1
                                let supernetPrefix = prefix - 1
                                let supernetBaseRaw = min(aRaw, bRaw)
                                let supernetMask = supernetPrefix == 0 ? 0 : (~UInt32(0) << (32 - supernetPrefix))

                                if (supernetBaseRaw & ~supernetMask) == 0 {
                                    let superAddr = IPAddress.IPv4(rawValue: supernetBaseRaw)
                                    if let supernet = IPNetwork(address: .v4(superAddr), prefixLength: supernetPrefix) {
                                        nextRound.append(supernet)
                                        skipIndices.insert(i)
                                        skipIndices.insert(j)
                                        merged = true
                                        changed = true
                                        break
                                    }
                                }
                            }
                        }
                    }
                }

                if !merged && !skipIndices.contains(i) {
                    nextRound.append(netA)
                }
            }

            current = nextRound
        }

        // Final sort
        current.sort { (a: IPNetwork, b: IPNetwork) -> Bool in
            let aRaw = a.ipv4NetworkAddress?.rawValue ?? 0
            let bRaw = b.ipv4NetworkAddress?.rawValue ?? 0
            return aRaw < bRaw
        }

        return CIDRAggregatorResult(originalNetworks: inputNetworks, aggregatedNetworks: current)
    }
}
