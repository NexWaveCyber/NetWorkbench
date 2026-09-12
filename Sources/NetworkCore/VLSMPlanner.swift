import Foundation

public struct VLSMRequirement: Sendable, Identifiable {
    public let id: UUID
    public var name: String
    public var requiredHosts: Int

    public init(id: UUID = UUID(), name: String, requiredHosts: Int) {
        self.id = id
        self.name = name
        self.requiredHosts = max(1, requiredHosts)
    }
}

public struct VLSMAllocation: Sendable, Identifiable {
    public var id: UUID { requirement.id }
    public let requirement: VLSMRequirement
    public let allocatedNetwork: IPNetwork
    public let allocatedHosts: Int
    public let wastedHosts: Int

    public init(requirement: VLSMRequirement, allocatedNetwork: IPNetwork) {
        self.requirement = requirement
        self.allocatedNetwork = allocatedNetwork
        let usable = Int(allocatedNetwork.usableHostCount)
        self.allocatedHosts = usable
        self.wastedHosts = max(0, usable - requirement.requiredHosts)
    }
}

public struct VLSMResult: Sendable {
    public let majorNetwork: IPNetwork
    public let allocations: [VLSMAllocation]
    public let unallocatedSubnets: [IPNetwork]
    public let totalRequiredHosts: Int
    public let totalAllocatedHosts: Int
    public let totalCapacityHosts: Int
    public let isSuccess: Bool
    public let errorMessage: String?

    public var utilizationPercent: Double {
        guard totalCapacityHosts > 0 else { return 0.0 }
        return (Double(totalRequiredHosts) / Double(totalCapacityHosts)) * 100.0
    }
}

public enum VLSMPlanner {
    /// Calculates the minimum CIDR prefix length needed to accommodate `requiredHosts`.
    public static func requiredPrefix(forHosts hosts: Int) -> Int {
        if hosts == 1 { return 32 }
        if hosts == 2 { return 30 }
        var bits = 1
        while (1 << bits) - 2 < hosts {
            bits += 1
            if bits >= 32 { return 0 }
        }
        return 32 - bits
    }

    /// Computes optimal VLSM allocations for a given parent network and requirements.
    public static func plan(majorNetwork: IPNetwork, requirements: [VLSMRequirement]) -> VLSMResult {
        guard let majorNetAddr = majorNetwork.ipv4NetworkAddress,
              let majorBcastAddr = majorNetwork.ipv4BroadcastAddress else {
            return VLSMResult(
                majorNetwork: majorNetwork,
                allocations: [],
                unallocatedSubnets: [],
                totalRequiredHosts: 0,
                totalAllocatedHosts: 0,
                totalCapacityHosts: 0,
                isSuccess: false,
                errorMessage: "VLSM planner currently requires an IPv4 network block."
            )
        }

        let totalReq = requirements.reduce(0) { $0 + $1.requiredHosts }
        let totalCap = Int(majorNetwork.usableHostCount)

        // Sort descending by required hosts (VLSM best practice: largest subnets first)
        let sortedReqs = requirements.sorted { $0.requiredHosts > $1.requiredHosts }

        var currentStartRaw = majorNetAddr.rawValue
        let majorEndRaw = majorBcastAddr.rawValue

        var allocations: [VLSMAllocation] = []
        var failed = false

        for req in sortedReqs {
            let prefix = requiredPrefix(forHosts: req.requiredHosts)
            let hostBits = 32 - prefix
            let blockSize = UInt32(1) << hostBits

            // Align currentStartRaw to blockSize boundary
            let remainder = currentStartRaw % blockSize
            if remainder != 0 {
                currentStartRaw += (blockSize - remainder)
            }

            let blockEnd = currentStartRaw + blockSize - 1
            if blockEnd > majorEndRaw || currentStartRaw > majorEndRaw {
                failed = true
                break
            }

            let netAddr = IPAddress.IPv4(rawValue: currentStartRaw)
            guard let subnet = IPNetwork(address: .v4(netAddr), prefixLength: prefix) else {
                failed = true
                break
            }

            allocations.append(VLSMAllocation(requirement: req, allocatedNetwork: subnet))
            currentStartRaw = blockEnd + 1
        }

        if failed {
            return VLSMResult(
                majorNetwork: majorNetwork,
                allocations: allocations,
                unallocatedSubnets: [],
                totalRequiredHosts: totalReq,
                totalAllocatedHosts: allocations.reduce(0) { $0 + $1.allocatedHosts },
                totalCapacityHosts: totalCap,
                isSuccess: false,
                errorMessage: "Major network address space exhausted. Total required hosts (\(totalReq)) exceeds block or cannot be aligned."
            )
        }

        // Remaining unallocated space
        var unallocated: [IPNetwork] = []
        if currentStartRaw <= majorEndRaw {
            var cursor = currentStartRaw
            while cursor <= majorEndRaw {
                let remaining = majorEndRaw - cursor + 1
                var bits = 0
                while (cursor % (UInt32(1) << (bits + 1)) == 0) && ((UInt32(1) << (bits + 1)) <= remaining) && (bits < 32) {
                    bits += 1
                }
                let prefix = 32 - bits
                let netAddr = IPAddress.IPv4(rawValue: cursor)
                if let net = IPNetwork(address: .v4(netAddr), prefixLength: prefix) {
                    unallocated.append(net)
                }
                cursor += (UInt32(1) << bits)
            }
        }

        return VLSMResult(
            majorNetwork: majorNetwork,
            allocations: allocations,
            unallocatedSubnets: unallocated,
            totalRequiredHosts: totalReq,
            totalAllocatedHosts: allocations.reduce(0) { $0 + $1.allocatedHosts },
            totalCapacityHosts: totalCap,
            isSuccess: true,
            errorMessage: nil
        )
    }
}
