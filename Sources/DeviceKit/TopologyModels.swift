import Foundation
import CoreGraphics
import NetworkCore

public enum TopologyTier: String, Codable, Sendable, CaseIterable, Identifiable {
    case core = "Core Layer"
    case distribution = "Distribution / Aggregation"
    case access = "Access Layer"
    case edge = "Edge / Gateway"
    case endpoint = "Endpoints & APs"

    public var id: String { rawValue }

    public var tierLevel: Int {
        switch self {
        case .core: return 0
        case .edge: return 1
        case .distribution: return 2
        case .access: return 3
        case .endpoint: return 4
        }
    }
}

public enum TopologyLinkType: String, Codable, Sendable, CaseIterable {
    case ethernet = "1G Ethernet"
    case fiber10G = "10G SFP+"
    case fiber100G = "100G QSFP28"
    case portChannel = "LACP Port-Channel"
    case wireless = "802.11 Wireless Link"
    case vpnTunnel = "IPsec / GRE Tunnel"

    public var badgeColorHex: String {
        switch self {
        case .ethernet: return "#00F0FF"      // Cyan
        case .fiber10G: return "#10B981"      // Emerald
        case .fiber100G: return "#8B5CF6"     // Purple
        case .portChannel: return "#F59E0B"   // Amber
        case .wireless: return "#3B82F6"      // Blue
        case .vpnTunnel: return "#EC4899"     // Pink
        }
    }
}

public struct TopologyNode: Identifiable, Sendable, Codable, Equatable {
    public let id: String
    public var label: String
    public var role: DeviceRole
    public var vendor: DeviceVendor
    public var ipAddress: String
    public var ipv6Address: String?
    public var macAddress: String?
    public var platform: String?
    public var status: DeviceStatus
    public var tier: TopologyTier
    public var position: CGPoint
    public var vlans: [Int]
    public var alarmsCount: Int

    public init(
        id: String,
        label: String,
        role: DeviceRole,
        vendor: DeviceVendor = .cisco,
        ipAddress: String,
        ipv6Address: String? = nil,
        macAddress: String? = nil,
        platform: String? = nil,
        status: DeviceStatus = .online,
        tier: TopologyTier = .access,
        position: CGPoint = .zero,
        vlans: [Int] = [1],
        alarmsCount: Int = 0
    ) {
        self.id = id
        self.label = label
        self.role = role
        self.vendor = vendor
        self.ipAddress = ipAddress
        self.ipv6Address = ipv6Address
        self.macAddress = macAddress
        self.platform = platform
        self.status = status
        self.tier = tier
        self.position = position
        self.vlans = vlans
        self.alarmsCount = alarmsCount
    }
}

public struct TopologyLink: Identifiable, Sendable, Codable, Equatable {
    public let id: String
    public let sourceNodeId: String
    public let targetNodeId: String
    public let sourceInterface: String
    public let targetInterface: String
    public let linkType: TopologyLinkType
    public let speedMbps: Int
    public let status: DeviceStatus
    public let vlanId: Int?
    public var duplex: String
    public var mtu: Int
    public var vlanTrunkAllowed: [Int]
    public var packetLossPct: Double
    public var currentUtilizationMbps: Double

    public init(
        id: String = UUID().uuidString,
        sourceNodeId: String,
        targetNodeId: String,
        sourceInterface: String,
        targetInterface: String,
        linkType: TopologyLinkType = .fiber10G,
        speedMbps: Int = 10_000,
        status: DeviceStatus = .online,
        vlanId: Int? = nil,
        duplex: String = "Full",
        mtu: Int = 1500,
        vlanTrunkAllowed: [Int] = [],
        packetLossPct: Double = 0.0,
        currentUtilizationMbps: Double = 0.0
    ) {
        self.id = id
        self.sourceNodeId = sourceNodeId
        self.targetNodeId = targetNodeId
        self.sourceInterface = sourceInterface
        self.targetInterface = targetInterface
        self.linkType = linkType
        self.speedMbps = speedMbps
        self.status = status
        self.vlanId = vlanId
        self.duplex = duplex
        self.mtu = mtu
        self.vlanTrunkAllowed = vlanTrunkAllowed
        self.packetLossPct = packetLossPct
        self.currentUtilizationMbps = currentUtilizationMbps
    }
}

public struct TopologyGraph: Sendable, Codable, Equatable {
    public var nodes: [TopologyNode]
    public var links: [TopologyLink]

    public init(nodes: [TopologyNode] = [], links: [TopologyLink] = []) {
        self.nodes = nodes
        self.links = links
    }

    // MARK: - Graph Mutation Operations
    public mutating func addNode(_ node: TopologyNode) {
        if let idx = nodes.firstIndex(where: { $0.id == node.id }) {
            nodes[idx] = node
        } else {
            nodes.append(node)
        }
    }

    public mutating func removeNode(id: String) {
        nodes.removeAll(where: { $0.id == id })
        links.removeAll(where: { $0.sourceNodeId == id || $0.targetNodeId == id })
    }

    public mutating func addLink(_ link: TopologyLink) {
        if let idx = links.firstIndex(where: { $0.id == link.id }) {
            links[idx] = link
        } else {
            links.append(link)
        }
    }

    public mutating func removeLink(id: String) {
        links.removeAll(where: { $0.id == id })
    }

    // MARK: - Multi-Link & Curvature Indexing
    public func linksBetween(nodeA: String, nodeB: String) -> [TopologyLink] {
        links.filter {
            ($0.sourceNodeId == nodeA && $0.targetNodeId == nodeB) ||
            ($0.sourceNodeId == nodeB && $0.targetNodeId == nodeA)
        }
    }

    public func curvatureOffset(for link: TopologyLink) -> CGFloat {
        let parallelLinks = linksBetween(nodeA: link.sourceNodeId, nodeB: link.targetNodeId)
        guard parallelLinks.count > 1,
              let index = parallelLinks.firstIndex(where: { $0.id == link.id }) else {
            return 0.0
        }
        let spread: CGFloat = 28.0
        let count = CGFloat(parallelLinks.count)
        let normalizedIndex = CGFloat(index) - (count - 1.0) / 2.0
        return normalizedIndex * spread
    }

    // MARK: - Path Finding (BFS / Dijkstra Layer 2/3 Tracer)
    public func findShortestPath(from sourceNodeId: String, to targetNodeId: String) -> (nodeIds: [String], linkIds: [String])? {
        guard sourceNodeId != targetNodeId else { return ([sourceNodeId], []) }
        guard nodes.contains(where: { $0.id == sourceNodeId }),
              nodes.contains(where: { $0.id == targetNodeId }) else { return nil }

        var queue: [String] = [sourceNodeId]
        var visited: Set<String> = [sourceNodeId]
        var previous: [String: (nodeId: String, linkId: String)] = [:]

        while !queue.isEmpty {
            let current = queue.removeFirst()
            if current == targetNodeId {
                var pathNodes: [String] = [targetNodeId]
                var pathLinks: [String] = []
                var step = targetNodeId
                while let prev = previous[step] {
                    pathNodes.append(prev.nodeId)
                    pathLinks.append(prev.linkId)
                    step = prev.nodeId
                }
                return (pathNodes.reversed(), pathLinks.reversed())
            }

            for link in links {
                let neighbor: String?
                if link.sourceNodeId == current {
                    neighbor = link.targetNodeId
                } else if link.targetNodeId == current {
                    neighbor = link.sourceNodeId
                } else {
                    neighbor = nil
                }

                if let n = neighbor, !visited.contains(n) {
                    visited.insert(n)
                    previous[n] = (current, link.id)
                    queue.append(n)
                }
            }
        }
        return nil
    }

    // MARK: - VLAN Membership Filtering
    public func filterByVLAN(_ vlanId: Int) -> (matchingNodeIds: Set<String>, matchingLinkIds: Set<String>) {
        var matchingNodes = Set<String>()
        var matchingLinks = Set<String>()

        for node in nodes {
            if node.vlans.contains(vlanId) {
                matchingNodes.insert(node.id)
            }
        }

        for link in links {
            if link.vlanId == vlanId || link.vlanTrunkAllowed.contains(vlanId) {
                matchingLinks.insert(link.id)
                matchingNodes.insert(link.sourceNodeId)
                matchingNodes.insert(link.targetNodeId)
            }
        }

        return (matchingNodes, matchingLinks)
    }

    // MARK: - Auto-Layout Algorithms

    /// Arranges nodes into a clean 3-tier hierarchical structure:
    /// Core (top) -> Distribution (middle) -> Access / Endpoints (bottom)
    public mutating func applyHierarchicalLayout(bounds: CGSize) {
        guard !nodes.isEmpty else { return }

        let width = max(600, bounds.width)
        let height = max(400, bounds.height)

        // Group by tier level
        var tiers: [Int: [Int]] = [:] // Tier level -> indices in self.nodes
        for (idx, node) in nodes.enumerated() {
            tiers[node.tier.tierLevel, default: []].append(idx)
        }

        let sortedTierLevels = tiers.keys.sorted()
        let totalLevels = max(1, sortedTierLevels.count)
        let verticalSpacing = height / CGFloat(totalLevels + 1)

        for (tierIndex, tierLevel) in sortedTierLevels.enumerated() {
            guard let nodeIndices = tiers[tierLevel], !nodeIndices.isEmpty else { continue }
            let y = verticalSpacing * CGFloat(tierIndex + 1)
            let horizontalSpacing = width / CGFloat(nodeIndices.count + 1)

            for (colIndex, nodeIdx) in nodeIndices.enumerated() {
                let x = horizontalSpacing * CGFloat(colIndex + 1)
                self.nodes[nodeIdx].position = CGPoint(x: x, y: y)
            }
        }
    }

    /// Arranges nodes radially around a central hub or core node
    public mutating func applyRadialLayout(bounds: CGSize) {
        guard !nodes.isEmpty else { return }

        let width = max(600, bounds.width)
        let height = max(400, bounds.height)
        let center = CGPoint(x: width / 2.0, y: height / 2.0)
        let radius = min(width, height) * 0.38

        // If core node exists, place at center; otherwise distribute evenly
        let coreIndex = nodes.firstIndex(where: { $0.tier == .core })

        if let coreIdx = coreIndex {
            self.nodes[coreIdx].position = center
            let remaining = nodes.indices.filter { $0 != coreIdx }
            let count = max(1, remaining.count)
            for (i, idx) in remaining.enumerated() {
                let angle = (CGFloat(i) / CGFloat(count)) * (2.0 * .pi) - (.pi / 2.0)
                let x = center.x + radius * cos(angle)
                let y = center.y + radius * sin(angle)
                self.nodes[idx].position = CGPoint(x: x, y: y)
            }
        } else {
            let count = nodes.count
            for (i, idx) in nodes.indices.enumerated() {
                let angle = (CGFloat(i) / CGFloat(count)) * (2.0 * .pi) - (.pi / 2.0)
                let x = center.x + radius * cos(angle)
                let y = center.y + radius * sin(angle)
                self.nodes[idx].position = CGPoint(x: x, y: y)
            }
        }
    }

    // MARK: - Factory & Construction

    /// Enterprise Campus Network Reference Topology
    public static func buildEnterpriseDemo(bounds: CGSize = CGSize(width: 900, height: 600)) -> TopologyGraph {
        let nodes: [TopologyNode] = [
            // Core Tier
            TopologyNode(
                id: "core-rtr01",
                label: "core-rtr01.sfo",
                role: .router,
                vendor: .cisco,
                ipAddress: "10.0.0.1",
                macAddress: "00:1C:58:11:22:01",
                platform: "Cisco Catalyst 8300",
                status: .online,
                tier: .core,
                vlans: [10, 20, 30, 99],
                alarmsCount: 0
            ),
            TopologyNode(
                id: "edge-fw01",
                label: "edge-fw01.sfo",
                role: .firewall,
                vendor: .fortinet,
                ipAddress: "10.0.0.254",
                macAddress: "00:1C:58:33:44:01",
                platform: "FortiGate 100F",
                status: .online,
                tier: .edge,
                vlans: [1, 99],
                alarmsCount: 0
            ),

            // Distribution Tier
            TopologyNode(
                id: "dist-sw01",
                label: "dist-sw01.sfo",
                role: .switchRole,
                vendor: .cisco,
                ipAddress: "10.0.10.1",
                macAddress: "00:1C:58:55:66:01",
                platform: "Cisco Catalyst 9500",
                status: .online,
                tier: .distribution,
                vlans: [10, 20, 30, 40],
                alarmsCount: 0
            ),
            TopologyNode(
                id: "dist-sw02",
                label: "dist-sw02.sfo",
                role: .switchRole,
                vendor: .arista,
                ipAddress: "10.0.10.2",
                macAddress: "00:1C:58:55:66:02",
                platform: "Arista 7050SX3",
                status: .online,
                tier: .distribution,
                vlans: [10, 20, 30, 40],
                alarmsCount: 1
            ),

            // Access Tier
            TopologyNode(
                id: "acc-sw01",
                label: "acc-sw01.floor1",
                role: .switchRole,
                vendor: .cisco,
                ipAddress: "10.0.20.11",
                macAddress: "00:1C:58:77:88:01",
                platform: "Cisco Catalyst 9300-48P",
                status: .online,
                tier: .access,
                vlans: [10, 20],
                alarmsCount: 0
            ),
            TopologyNode(
                id: "acc-sw02",
                label: "acc-sw02.floor2",
                role: .switchRole,
                vendor: .cisco,
                ipAddress: "10.0.20.12",
                macAddress: "00:1C:58:77:88:02",
                platform: "Cisco Catalyst 9300-48P",
                status: .online,
                tier: .access,
                vlans: [10, 20],
                alarmsCount: 0
            ),
            TopologyNode(
                id: "ap-lobby",
                label: "ap-lobby-01",
                role: .accessPoint,
                vendor: .cisco,
                ipAddress: "10.0.30.50",
                macAddress: "00:1C:58:99:AA:01",
                platform: "Catalyst 9130AX",
                status: .online,
                tier: .endpoint,
                vlans: [30],
                alarmsCount: 0
            )
        ]

        let links: [TopologyLink] = [
            // Core <-> Firewall
            TopologyLink(sourceNodeId: "core-rtr01", targetNodeId: "edge-fw01", sourceInterface: "Te0/0/1", targetInterface: "port1", linkType: .fiber10G, speedMbps: 10_000),

            // Core <-> Distribution 1 & 2
            TopologyLink(sourceNodeId: "core-rtr01", targetNodeId: "dist-sw01", sourceInterface: "Te0/0/2", targetInterface: "Eth1/1", linkType: .fiber100G, speedMbps: 100_000),
            TopologyLink(sourceNodeId: "core-rtr01", targetNodeId: "dist-sw02", sourceInterface: "Te0/0/3", targetInterface: "Eth1/1", linkType: .fiber100G, speedMbps: 100_000),

            // Distribution Interlink (Port-Channel)
            TopologyLink(sourceNodeId: "dist-sw01", targetNodeId: "dist-sw02", sourceInterface: "Po1 (Eth1/47-48)", targetInterface: "Po1 (Eth1/47-48)", linkType: .portChannel, speedMbps: 200_000),

            // Distribution <-> Access
            TopologyLink(sourceNodeId: "dist-sw01", targetNodeId: "acc-sw01", sourceInterface: "Eth1/10", targetInterface: "Te1/1/1", linkType: .fiber10G, speedMbps: 10_000),
            TopologyLink(sourceNodeId: "dist-sw02", targetNodeId: "acc-sw01", sourceInterface: "Eth1/10", targetInterface: "Te1/1/2", linkType: .fiber10G, speedMbps: 10_000),
            TopologyLink(sourceNodeId: "dist-sw01", targetNodeId: "acc-sw02", sourceInterface: "Eth1/11", targetInterface: "Te1/1/1", linkType: .fiber10G, speedMbps: 10_000),
            TopologyLink(sourceNodeId: "dist-sw02", targetNodeId: "acc-sw02", sourceInterface: "Eth1/11", targetInterface: "Te1/1/2", linkType: .fiber10G, speedMbps: 10_000),

            // Access <-> AP
            TopologyLink(sourceNodeId: "acc-sw01", targetNodeId: "ap-lobby", sourceInterface: "Gi1/0/24", targetInterface: "Eth0", linkType: .ethernet, speedMbps: 2_500)
        ]

        var graph = TopologyGraph(nodes: nodes, links: links)
        graph.applyHierarchicalLayout(bounds: bounds)
        return graph
    }

    /// Data Center Spine-Leaf Reference Topology
    public static func buildDataCenterDemo(bounds: CGSize = CGSize(width: 900, height: 600)) -> TopologyGraph {
        let nodes: [TopologyNode] = [
            TopologyNode(id: "spine-01", label: "spine-01.dc1", role: .switchRole, vendor: .arista, ipAddress: "10.100.0.1", platform: "Arista 7060CX", tier: .core),
            TopologyNode(id: "spine-02", label: "spine-02.dc1", role: .switchRole, vendor: .arista, ipAddress: "10.100.0.2", platform: "Arista 7060CX", tier: .core),
            TopologyNode(id: "leaf-01", label: "leaf-01.rack1", role: .switchRole, vendor: .arista, ipAddress: "10.100.1.1", platform: "Arista 7050SX3", tier: .distribution),
            TopologyNode(id: "leaf-02", label: "leaf-02.rack1", role: .switchRole, vendor: .arista, ipAddress: "10.100.1.2", platform: "Arista 7050SX3", tier: .distribution),
            TopologyNode(id: "leaf-03", label: "leaf-03.rack2", role: .switchRole, vendor: .arista, ipAddress: "10.100.2.1", platform: "Arista 7050SX3", tier: .distribution),
            TopologyNode(id: "leaf-04", label: "leaf-04.rack2", role: .switchRole, vendor: .arista, ipAddress: "10.100.2.2", platform: "Arista 7050SX3", tier: .distribution),
            TopologyNode(id: "srv-compute01", label: "k8s-worker-01", role: .server, vendor: .linux, ipAddress: "10.100.10.101", platform: "Ubuntu Linux 24.04", tier: .endpoint),
            TopologyNode(id: "srv-compute02", label: "k8s-worker-02", role: .server, vendor: .linux, ipAddress: "10.100.10.102", platform: "Ubuntu Linux 24.04", tier: .endpoint)
        ]

        let links: [TopologyLink] = [
            TopologyLink(sourceNodeId: "spine-01", targetNodeId: "leaf-01", sourceInterface: "Eth1/1", targetInterface: "Eth49", linkType: .fiber100G, speedMbps: 100_000),
            TopologyLink(sourceNodeId: "spine-01", targetNodeId: "leaf-02", sourceInterface: "Eth1/2", targetInterface: "Eth49", linkType: .fiber100G, speedMbps: 100_000),
            TopologyLink(sourceNodeId: "spine-01", targetNodeId: "leaf-03", sourceInterface: "Eth1/3", targetInterface: "Eth49", linkType: .fiber100G, speedMbps: 100_000),
            TopologyLink(sourceNodeId: "spine-01", targetNodeId: "leaf-04", sourceInterface: "Eth1/4", targetInterface: "Eth49", linkType: .fiber100G, speedMbps: 100_000),

            TopologyLink(sourceNodeId: "spine-02", targetNodeId: "leaf-01", sourceInterface: "Eth1/1", targetInterface: "Eth50", linkType: .fiber100G, speedMbps: 100_000),
            TopologyLink(sourceNodeId: "spine-02", targetNodeId: "leaf-02", sourceInterface: "Eth1/2", targetInterface: "Eth50", linkType: .fiber100G, speedMbps: 100_000),
            TopologyLink(sourceNodeId: "spine-02", targetNodeId: "leaf-03", sourceInterface: "Eth1/3", targetInterface: "Eth50", linkType: .fiber100G, speedMbps: 100_000),
            TopologyLink(sourceNodeId: "spine-02", targetNodeId: "leaf-04", sourceInterface: "Eth1/4", targetInterface: "Eth50", linkType: .fiber100G, speedMbps: 100_000),

            TopologyLink(sourceNodeId: "leaf-01", targetNodeId: "srv-compute01", sourceInterface: "Eth1", targetInterface: "eth0", linkType: .fiber10G, speedMbps: 10_000),
            TopologyLink(sourceNodeId: "leaf-03", targetNodeId: "srv-compute02", sourceInterface: "Eth1", targetInterface: "eth0", linkType: .fiber10G, speedMbps: 10_000)
        ]

        var graph = TopologyGraph(nodes: nodes, links: links)
        graph.applyHierarchicalLayout(bounds: bounds)
        return graph
    }

    /// Automatically constructs a topology from local LAN discovered neighbors
    public static func buildFromDiscoveredLAN(
        neighbors: [DiscoveredNeighbor],
        gatewayIP: String = "192.168.10.1",
        bounds: CGSize = CGSize(width: 900, height: 600)
    ) -> TopologyGraph {
        var nodes: [TopologyNode] = []
        var links: [TopologyLink] = []

        // 1. Local Workstation Node
        let hostName = ProcessInfo.processInfo.hostName.components(separatedBy: ".").first ?? "Your Mac"
        let localNode = TopologyNode(
            id: "local-mac",
            label: hostName,
            role: .workstation,
            vendor: .apple,
            ipAddress: "Local Host",
            platform: "Apple Mac",
            status: .online,
            tier: .access
        )
        nodes.append(localNode)

        // 2. Gateway Node (Enriched from discovered neighbors if present)
        let gwNeighbor = neighbors.first(where: { $0.ipAddress == gatewayIP })
        let gwVendor = gwNeighbor?.vendor ?? .generic
        let gwPlatform = gwNeighbor?.ouiVendor ?? (gwVendor != .generic ? gwVendor.rawValue : "Default Gateway")
        let gwLabel: String
        if let h = gwNeighbor?.hostname, !h.isEmpty, h != gatewayIP {
            gwLabel = h
        } else if let v = gwNeighbor?.ouiVendor, !v.isEmpty {
            gwLabel = v
        } else {
            gwLabel = "Default Gateway"
        }

        let gwNode = TopologyNode(
            id: "gateway-router",
            label: gwLabel,
            role: .router,
            vendor: gwVendor == .generic ? .linksys : gwVendor,
            ipAddress: gatewayIP,
            ipv6Address: gwNeighbor?.ipv6Address,
            macAddress: gwNeighbor?.macAddress,
            platform: gwPlatform,
            status: .online,
            tier: .core
        )
        nodes.append(gwNode)

        // Uplink from local machine to gateway
        links.append(TopologyLink(
            sourceNodeId: "local-mac",
            targetNodeId: "gateway-router",
            sourceInterface: "en0",
            targetInterface: "LAN Port",
            linkType: .wireless,
            speedMbps: 1_200
        ))

        // Discovered Neighbors connected to Gateway (filters link-local IPv6, loopback, and deduplicates gateway)
        let otherNeighbors = neighbors.filter { n in
            let clean = n.ipAddress.components(separatedBy: "%").first?.lowercased() ?? n.ipAddress.lowercased()
            if clean == gatewayIP || clean == "127.0.0.1" || clean == "::1" { return false }
            if clean.hasPrefix("fe8") || clean.hasPrefix("fe9") || clean.hasPrefix("fea") || clean.hasPrefix("feb") { return false }
            return true
        }
        for (idx, n) in otherNeighbors.prefix(48).enumerated() {
            let role: DeviceRole
            let lowerVendor = (n.ouiVendor ?? "").lowercased()
            if lowerVendor.contains("cisco") || lowerVendor.contains("arista") || lowerVendor.contains("juniper") || lowerVendor.contains("switch") {
                role = .switchRole
            } else if lowerVendor.contains("apple") || lowerVendor.contains("dell") || lowerVendor.contains("lenovo") || lowerVendor.contains("asus") || lowerVendor.contains("samsung") || lowerVendor.contains("sony") {
                role = .workstation
            } else if lowerVendor.contains("router") || lowerVendor.contains("gateway") || lowerVendor.contains("linksys") || lowerVendor.contains("netgear") || lowerVendor.contains("tp-link") || lowerVendor.contains("fritz") || lowerVendor.contains("zyxel") {
                role = .router
            } else if lowerVendor.contains("vmware") || lowerVendor.contains("intel") || lowerVendor.contains("synology") || lowerVendor.contains("qnap") || lowerVendor.contains("super micro") {
                role = .server
            } else if lowerVendor.contains("access point") || lowerVendor.contains("unifi") || lowerVendor.contains("ubiquiti") {
                role = .accessPoint
            } else {
                role = .other
            }

            // Clean friendly label that NEVER duplicates the IP address
            let cleanLabel: String
            if let h = n.hostname, !h.isEmpty, h != n.ipAddress {
                cleanLabel = h
            } else if let v = n.ouiVendor, !v.isEmpty {
                if v == "Private MAC (Locally Administered)" {
                    cleanLabel = "Private Wi-Fi Device"
                } else {
                    cleanLabel = v
                }
            } else if n.vendor != .generic {
                cleanLabel = "\(n.vendor.rawValue) Device"
            } else if n.ipAddress.contains(":") {
                let lastHextet = n.ipAddress.components(separatedBy: ":").last(where: { !$0.isEmpty }) ?? "\(idx)"
                cleanLabel = "IPv6 Host :\(lastHextet)"
            } else {
                let lastOctet = n.ipAddress.components(separatedBy: ".").last ?? "\(idx)"
                cleanLabel = "Host .\(lastOctet)"
            }

            let nodeId = "neighbor-\(idx)"
            let node = TopologyNode(
                id: nodeId,
                label: cleanLabel,
                role: role,
                vendor: n.vendor,
                ipAddress: n.ipAddress,
                ipv6Address: n.ipv6Address,
                macAddress: n.macAddress.isEmpty ? nil : n.macAddress,
                platform: n.ouiVendor,
                status: .online,
                tier: .endpoint
            )
            nodes.append(node)

            links.append(TopologyLink(
                sourceNodeId: "gateway-router",
                targetNodeId: nodeId,
                sourceInterface: "SwitchPort",
                targetInterface: "eth0",
                linkType: .ethernet,
                speedMbps: 1_000
            ))
        }

        var graph = TopologyGraph(nodes: nodes, links: links)
        graph.applyHierarchicalLayout(bounds: bounds)
        return graph
    }

    /// Automatically constructs a topology from saved inventory devices
    public static func buildFromInventory(
        devices: [NetworkDevice],
        bounds: CGSize = CGSize(width: 900, height: 600)
    ) -> TopologyGraph {
        guard !devices.isEmpty else {
            return buildEnterpriseDemo(bounds: bounds)
        }

        var nodes: [TopologyNode] = []
        var links: [TopologyLink] = []

        for d in devices {
            let tier: TopologyTier
            switch d.role {
            case .router: tier = .core
            case .firewall: tier = .edge
            case .switchRole: tier = .distribution
            case .accessPoint: tier = .access
            case .server, .workstation, .other: tier = .endpoint
            }

            nodes.append(TopologyNode(
                id: d.id.uuidString,
                label: d.displayName,
                role: d.role,
                vendor: d.vendor,
                ipAddress: d.managementIP,
                platform: d.platform,
                status: d.status,
                tier: tier
            ))
        }

        // Generate logical interconnects between core/dist/access
        let coreNodes = nodes.filter { $0.tier == .core || $0.tier == .edge }
        let distNodes = nodes.filter { $0.tier == .distribution }
        let accessNodes = nodes.filter { $0.tier == .access || $0.tier == .endpoint }

        for c in coreNodes {
            for dist in distNodes {
                links.append(TopologyLink(
                    sourceNodeId: c.id,
                    targetNodeId: dist.id,
                    sourceInterface: "Uplink",
                    targetInterface: "Trunk",
                    linkType: .fiber10G
                ))
            }
        }

        for dist in distNodes {
            for acc in accessNodes {
                links.append(TopologyLink(
                    sourceNodeId: dist.id,
                    targetNodeId: acc.id,
                    sourceInterface: "Downlink",
                    targetInterface: "Uplink",
                    linkType: .ethernet
                ))
            }
        }

        var graph = TopologyGraph(nodes: nodes, links: links)
        graph.applyHierarchicalLayout(bounds: bounds)
        return graph
    }
}
