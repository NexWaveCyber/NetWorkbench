import Foundation
import Observation

/// Physical switch neighbor discovered passively over Ethernet
public struct DiscoveredSwitchNeighbor: Identifiable, Sendable, Hashable {
    public var id: String { "\(systemName):\(portName)" }
    public let sourceProtocol: String // "LLDP" or "CDP"
    public let systemName: String
    public let portName: String
    public let platform: String
    public let managementIP: String?
    public let vlan: Int?
    public let duplex: String
    public let lastSeen: Date

    public init(
        sourceProtocol: String,
        systemName: String,
        portName: String,
        platform: String = "",
        managementIP: String? = nil,
        vlan: Int? = nil,
        duplex: String = "Full",
        lastSeen: Date = Date()
    ) {
        self.sourceProtocol = sourceProtocol
        self.systemName = systemName
        self.portName = portName
        self.platform = platform
        self.managementIP = managementIP
        self.vlan = vlan
        self.duplex = duplex
        self.lastSeen = lastSeen
    }

    public var displayTitle: String {
        var str = "\(systemName) (\(portName))"
        if !platform.isEmpty {
            str += " [\(platform)]"
        }
        if let v = vlan {
            str += " • VLAN \(v)"
        }
        if let ip = managementIP {
            str += " • Mgmt: \(ip)"
        }
        return str
    }
}

/// Passively detects connected switches and access ports by sniffing incoming Layer 2 discovery multicasts
@Observable
public final class PassiveNeighborDiscoveryEngine: @unchecked Sendable {
    public static let shared = PassiveNeighborDiscoveryEngine()

    public var discoveredNeighbors: [DiscoveredSwitchNeighbor] = []
    public var activeLinkNeighbor: DiscoveredSwitchNeighbor? {
        discoveredNeighbors.sorted(by: { $0.lastSeen > $1.lastSeen }).first
    }

    public init() {}

    /// Ingest and analyze a raw Ethernet frame for LLDP or CDP announcements
    @discardableResult
    public func processFrame(packetData: Data) -> DiscoveredSwitchNeighbor? {
        guard packetData.count >= 14 else { return nil }

        let dstMAC = packetData.subdata(in: 0..<6).map { String(format: "%02X", $0) }.joined(separator: ":")
        var etherType = UInt16(packetData[12]) << 8 | UInt16(packetData[13])
        var offset = 14

        // 802.1Q VLAN tag check
        if etherType == 0x8100 && packetData.count >= 18 {
            etherType = UInt16(packetData[16]) << 8 | UInt16(packetData[17])
            offset = 18
        }

        // 1. Check for IEEE 802.1AB LLDP (EtherType 0x88CC or multicast MAC 01:80:C2:00:00:0E)
        if etherType == 0x88CC || dstMAC == "01:80:C2:00:00:0E" {
            let (info, _, _) = LLDPDissector.dissect(data: packetData, offset: offset)
            let neighbor = DiscoveredSwitchNeighbor(
                sourceProtocol: "LLDP",
                systemName: info.systemName.isEmpty ? "LLDP Switch" : info.systemName,
                portName: info.portID.isEmpty ? "Unknown Port" : info.portID,
                platform: info.systemDescription,
                managementIP: info.managementAddress,
                vlan: info.vlanID,
                lastSeen: Date()
            )
            recordNeighbor(neighbor)
            return neighbor
        }

        // 2. Check for Cisco CDP (Destination MAC 01:00:0C:CC:CC:CC or SNAP protocol 0x2000)
        if dstMAC == "01:00:0C:CC:CC:CC" || (packetData.count > offset + 8 && packetData[offset] == 0xAA && packetData[offset + 1] == 0xAA) {
            // Skip 8-byte LLC/SNAP header (AA AA 03 00 00 0C 20 00)
            let cdpOffset = (packetData.count >= offset + 8 && packetData[offset] == 0xAA) ? offset + 8 : offset
            let (info, _, _) = CDPDissector.dissect(data: packetData, offset: cdpOffset)
            let neighbor = DiscoveredSwitchNeighbor(
                sourceProtocol: "CDP",
                systemName: info.deviceID.isEmpty ? "Cisco Device" : info.deviceID,
                portName: info.portID.isEmpty ? "Unknown Port" : info.portID,
                platform: info.platform,
                managementIP: info.managementAddress,
                vlan: info.nativeVLAN,
                duplex: info.duplex,
                lastSeen: Date()
            )
            recordNeighbor(neighbor)
            return neighbor
        }

        return nil
    }

    private func recordNeighbor(_ neighbor: DiscoveredSwitchNeighbor) {
        if let idx = discoveredNeighbors.firstIndex(where: { $0.systemName == neighbor.systemName && $0.portName == neighbor.portName }) {
            discoveredNeighbors[idx] = neighbor
        } else {
            discoveredNeighbors.append(neighbor)
        }
    }

    /// Clear cached neighbor links
    public func clear() {
        discoveredNeighbors.removeAll()
    }
}
