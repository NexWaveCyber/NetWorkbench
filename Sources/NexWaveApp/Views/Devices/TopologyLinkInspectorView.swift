//
//  TopologyLinkInspectorView.swift
//  NexWaveApp
//
//  Dedicated Link & Cable Inspector Drawer for Topology Canvas
//

import SwiftUI
import DeviceKit
import NetworkCore

public struct TopologyLinkInspectorView: View {
    public let link: TopologyLink
    public let graph: TopologyGraph
    public let onClose: () -> Void
    public let onDisconnect: () -> Void

    @State private var pingLatency: Double? = nil
    @State private var isPinging: Bool = false

    public init(
        link: TopologyLink,
        graph: TopologyGraph,
        onClose: @escaping () -> Void,
        onDisconnect: @escaping () -> Void
    ) {
        self.link = link
        self.graph = graph
        self.onClose = onClose
        self.onDisconnect = onDisconnect
    }

    private var sourceNode: TopologyNode? {
        graph.nodes.first(where: { $0.id == link.sourceNodeId })
    }

    private var targetNode: TopologyNode? {
        graph.nodes.first(where: { $0.id == link.targetNodeId })
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                Circle()
                    .fill(Color(hex: link.linkType.badgeColorHex))
                    .frame(width: 12, height: 12)

                VStack(alignment: .leading, spacing: 1) {
                    Text("CABLE INTERCONNECT")
                        .font(Theme.monoText(10, weight: .bold))
                        .foregroundStyle(Color(hex: link.linkType.badgeColorHex))
                    Text(link.linkType.rawValue)
                        .font(Theme.monoText(13, weight: .bold))
                        .foregroundStyle(.primary)
                }

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider().overlay(Theme.borderLight)

            // Endpoint Connection Block
            HStack(spacing: 8) {
                endpointCard(
                    title: "SOURCE",
                    label: sourceNode?.label ?? link.sourceNodeId,
                    interface: link.sourceInterface,
                    ip: sourceNode?.ipAddress ?? "-"
                )

                Image(systemName: "arrow.left.and.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.cyanPulse)

                endpointCard(
                    title: "DESTINATION",
                    label: targetNode?.label ?? link.targetNodeId,
                    interface: link.targetInterface,
                    ip: targetNode?.ipAddress ?? "-"
                )
            }

            Divider().overlay(Theme.borderLight)

            // Telemetry & L2/L3 Specs
            VStack(spacing: 8) {
                specRow(label: "Link Speed", value: formattedSpeed(link.speedMbps))
                specRow(label: "Duplex Mode", value: link.duplex)
                specRow(label: "MTU Frame Size", value: "\(link.mtu) Bytes \(link.mtu >= 9000 ? "(Jumbo)" : "(Standard)")")
                specRow(label: "Physical Status", value: link.status.rawValue)
                specRow(label: "Packet Loss Rate", value: "\(String(format: "%.1f", link.packetLossPct))%")
                specRow(label: "Current Throughput", value: "\(String(format: "%.1f", link.currentUtilizationMbps)) Mbps")
                if let vlan = link.vlanId {
                    specRow(label: "Access VLAN", value: "VLAN \(vlan)")
                }
            }

            // Allowed Trunk VLANs
            if !link.vlanTrunkAllowed.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("ALLOWED TRUNK VLANS (\(link.vlanTrunkAllowed.count))")
                        .font(Theme.monoText(9, weight: .bold))
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 5) {
                            ForEach(link.vlanTrunkAllowed, id: \.self) { vlan in
                                Text("VLAN \(vlan)")
                                    .font(Theme.monoText(9, weight: .semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Theme.cyanPulse.opacity(0.18))
                                    .foregroundStyle(Theme.cyanPulse)
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(Theme.cyanPulse.opacity(0.4), lineWidth: 1))
                            }
                        }
                    }
                }
            }

            // Latency Probe Section
            HStack {
                if let lat = pingLatency {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .foregroundStyle(Theme.signalEmerald)
                        Text("RTT: \(String(format: "%.2f", lat)) ms")
                            .font(Theme.monoText(11, weight: .bold))
                            .foregroundStyle(Theme.signalEmerald)
                    }
                } else if isPinging {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Measuring RTT...")
                        .font(Theme.monoText(10))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: measureLinkLatency) {
                    Label(pingLatency != nil ? "Re-Test RTT" : "Test Link Latency", systemImage: "timer")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .tint(Theme.cyanPulse)
                .disabled(isPinging)
            }

            Divider().overlay(Theme.borderLight)

            // Disconnect Button
            Button(role: .destructive, action: onDisconnect) {
                Label("Disconnect / Cut Cable", systemImage: "scissors")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.crimsonCritical)
        }
        .padding(16)
        .frame(width: 330)
        .background(Theme.cardBackground.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.borderLight, lineWidth: 1))
        .shadow(radius: 14)
        .padding(16)
    }

    private func endpointCard(title: String, label: String, interface: String, ip: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Theme.monoText(8, weight: .bold))
                .foregroundStyle(.secondary)
            Text(label)
                .font(Theme.monoText(11, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(interface)
                .font(Theme.monoText(10, weight: .semibold))
                .foregroundStyle(Theme.cyanPulse)
            Text(ip)
                .font(Theme.monoText(9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Theme.surfaceBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func specRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(Theme.monoText(11, weight: .semibold))
                .foregroundStyle(.primary)
        }
    }

    private func formattedSpeed(_ mbps: Int) -> String {
        if mbps >= 100_000 {
            return "\(mbps / 1000) Gbps QSFP28"
        } else if mbps >= 10_000 {
            return "\(mbps / 1000) Gbps SFP+"
        } else {
            return "\(mbps) Mbps Ethernet"
        }
    }

    private func measureLinkLatency() {
        isPinging = true
        // Simulate real microsecond link latency probe between physical neighbors
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            let base = link.linkType == .fiber100G ? 0.08 : (link.linkType == .fiber10G ? 0.18 : 0.45)
            self.pingLatency = base + Double.random(in: 0.01...0.05)
            self.isPinging = false
        }
    }
}
