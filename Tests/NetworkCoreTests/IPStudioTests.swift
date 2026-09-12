import Testing
@testable import NetworkCore

@Suite("IP Studio: VLSM, CIDR Aggregator & Wildcard Mask Tests")
struct IPStudioTests {
    @Test("VLSM Planning Optimal Partitioning")
    func testVLSMPlanning() {
        guard let major = IPNetwork("192.168.1.0/24") else {
            Issue.record("Failed to create major network")
            return
        }

        let reqs = [
            VLSMRequirement(name: "Engineering", requiredHosts: 50),
            VLSMRequirement(name: "Marketing", requiredHosts: 25),
            VLSMRequirement(name: "Executive", requiredHosts: 10),
            VLSMRequirement(name: "Point-to-Point WAN", requiredHosts: 2)
        ]

        let result = VLSMPlanner.plan(majorNetwork: major, requirements: reqs)
        #expect(result.isSuccess)
        #expect(result.allocations.count == 4)

        // First allocation (Engineering - 50 hosts) needs /26 (62 usable)
        let first = result.allocations[0]
        #expect(first.requirement.name == "Engineering")
        #expect(first.allocatedNetwork.prefixLength == 26)
        #expect(first.allocatedNetwork.networkAddress.description == "192.168.1.0")

        // Second allocation (Marketing - 25 hosts) needs /27 (30 usable)
        let second = result.allocations[1]
        #expect(second.requirement.name == "Marketing")
        #expect(second.allocatedNetwork.prefixLength == 27)
        #expect(second.allocatedNetwork.networkAddress.description == "192.168.1.64")

        // Third allocation (Executive - 10 hosts) needs /28 (14 usable)
        let third = result.allocations[2]
        #expect(third.requirement.name == "Executive")
        #expect(third.allocatedNetwork.prefixLength == 28)
        #expect(third.allocatedNetwork.networkAddress.description == "192.168.1.96")

        // Fourth allocation (WAN - 2 hosts) needs /30 (2 usable)
        let fourth = result.allocations[3]
        #expect(fourth.requirement.name == "Point-to-Point WAN")
        #expect(fourth.allocatedNetwork.prefixLength == 30)
        #expect(fourth.allocatedNetwork.networkAddress.description == "192.168.1.112")
    }

    @Test("CIDR Route Aggregation of 4 Contiguous /24s into a /22")
    func testCIDRAggregation() {
        let nets = [
            IPNetwork("10.0.0.0/24")!,
            IPNetwork("10.0.1.0/24")!,
            IPNetwork("10.0.2.0/24")!,
            IPNetwork("10.0.3.0/24")!
        ]

        let result = CIDRAggregator.aggregate(nets)
        #expect(result.summaryCount == 1)
        #expect(result.aggregatedNetworks.first?.description == "10.0.0.0/22")
        #expect(result.reductionPercent == 75.0)
    }

    @Test("CIDR Aggregation Deduplication and Containment")
    func testCIDRContainment() {
        let nets = [
            IPNetwork("192.168.0.0/16")!,
            IPNetwork("192.168.1.0/24")!,
            IPNetwork("192.168.2.0/24")!
        ]

        let result = CIDRAggregator.aggregate(nets)
        #expect(result.summaryCount == 1)
        #expect(result.aggregatedNetworks.first?.description == "192.168.0.0/16")
    }

    @Test("Wildcard Mask Inversion and Matching")
    func testWildcardMask() {
        let wm24 = WildcardMask(prefixLength: 24)
        #expect(wm24.description == "0.0.0.255")
        #expect(wm24.invertedSubnetMask == "255.255.255.0")
        #expect(wm24.isContiguous)
        #expect(wm24.prefixLength == 24)

        let base = IPAddress.IPv4("192.168.1.0")!
        let matchHost = IPAddress.IPv4("192.168.1.155")!
        let outsideHost = IPAddress.IPv4("192.168.2.1")!

        #expect(wm24.matches(base: base, candidate: matchHost))
        #expect(!wm24.matches(base: base, candidate: outsideHost))

        let customWM = WildcardMask("0.0.3.255")
        #expect(customWM != nil)
        #expect(customWM?.prefixLength == 22)
    }
}
