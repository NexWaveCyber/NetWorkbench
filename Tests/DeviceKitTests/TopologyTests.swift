import Testing
import Foundation
import CoreGraphics
@testable import DeviceKit
import NetworkCore

@Suite("Topology Graph & Layout Tests")
struct TopologyTests {

    @Test("Enterprise Campus Demo Graph contains 3-tier hierarchy and links")
    func enterpriseDemoGraph() {
        let graph = TopologyGraph.buildEnterpriseDemo(bounds: CGSize(width: 1000, height: 800))
        #expect(graph.nodes.count >= 6)
        #expect(graph.links.count >= 7)

        let coreNodes = graph.nodes.filter { $0.tier == .core }
        #expect(!coreNodes.isEmpty)

        let distNodes = graph.nodes.filter { $0.tier == .distribution }
        #expect(distNodes.count >= 2)

        // Verify layout positions were assigned
        for node in graph.nodes {
            #expect(node.position.x > 0)
            #expect(node.position.y > 0)
        }

        // Verify tier Y positions: Core tier Y should be higher up (smaller Y) than Access tier
        if let coreY = coreNodes.first?.position.y,
           let accessY = graph.nodes.first(where: { $0.tier == .access })?.position.y {
            #expect(coreY < accessY)
        }
    }

    @Test("Data Center Spine-Leaf Graph structure")
    func dataCenterDemoGraph() {
        let graph = TopologyGraph.buildDataCenterDemo(bounds: CGSize(width: 1000, height: 800))
        #expect(graph.nodes.count == 8)
        #expect(graph.links.count == 10)

        let spines = graph.nodes.filter { $0.tier == .core }
        #expect(spines.count == 2)

        let leafs = graph.nodes.filter { $0.tier == .distribution }
        #expect(leafs.count == 4)
    }

    @Test("Radial Layout distributes nodes around center")
    func radialLayoutAlgorithm() {
        var graph = TopologyGraph.buildEnterpriseDemo(bounds: CGSize(width: 800, height: 800))
        graph.applyRadialLayout(bounds: CGSize(width: 800, height: 800))

        // Center should be roughly (400, 400)
        let coreNode = graph.nodes.first(where: { $0.tier == .core })
        #expect(coreNode != nil)
        #expect(abs(coreNode!.position.x - 400) < 5)
        #expect(abs(coreNode!.position.y - 400) < 5)

        // Non-core nodes should be spread out around the radius
        for node in graph.nodes where node.tier != .core {
            let dist = hypot(node.position.x - 400, node.position.y - 400)
            #expect(dist > 50)
        }
    }

    @Test("Build Topology from Discovered LAN Neighbors")
    func discoveredLANTopology() {
        let neighbors = [
            DiscoveredNeighbor(ipAddress: "192.168.1.1", macAddress: "00:50:56:C0:00:01", hostname: "router.lan", discoverySource: .arp, ouiVendor: "Cisco"),
            DiscoveredNeighbor(ipAddress: "192.168.1.50", macAddress: "00:1A:2B:3C:4D:5E", hostname: "nas.lan", discoverySource: .arp, ouiVendor: "Intel"),
            DiscoveredNeighbor(ipAddress: "192.168.1.105", macAddress: "DE:AD:BE:EF:00:01", hostname: "printer.lan", discoverySource: .bonjour, ouiVendor: "HP")
        ]

        let graph = TopologyGraph.buildFromDiscoveredLAN(neighbors: neighbors, gatewayIP: "192.168.1.1")
        #expect(graph.nodes.count >= 4) // local machine + gateway + 3 neighbors (one matches gateway)
        #expect(!graph.links.isEmpty)

        let hasLocal = graph.nodes.contains(where: { $0.id == "local-mac" })
        #expect(hasLocal == true)

        let hasGateway = graph.nodes.contains(where: { $0.id == "gateway-router" })
        #expect(hasGateway == true)
    }

    @Test("Build Topology from Managed Inventory Devices")
    func inventoryTopology() {
        let devices = [
            NetworkDevice(displayName: "Core-RTR", hostname: "core.corp", managementIP: "10.0.0.1", vendor: .cisco, role: .router),
            NetworkDevice(displayName: "Dist-SW1", hostname: "dist1.corp", managementIP: "10.0.1.1", vendor: .arista, role: .switchRole),
            NetworkDevice(displayName: "Access-AP1", hostname: "ap1.corp", managementIP: "10.0.2.1", vendor: .cisco, role: .accessPoint)
        ]

        let graph = TopologyGraph.buildFromInventory(devices: devices)
        #expect(graph.nodes.count == 3)
        #expect(!graph.links.isEmpty)
    }
}
