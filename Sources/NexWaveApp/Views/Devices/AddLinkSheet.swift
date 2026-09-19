//
//  AddLinkSheet.swift
//  NexWaveApp
//
//  Interactive Cable Patching Modal for Topology Canvas
//

import SwiftUI
import DeviceKit
import NetworkCore

public struct AddLinkSheet: View {
    @Binding public var isPresented: Bool
    public let sourceNode: TopologyNode
    public let targetNode: TopologyNode
    public let onAddLink: (TopologyLink) -> Void

    @State private var sourceInterface: String = "Eth1/1"
    @State private var targetInterface: String = "Eth1/1"
    @State private var linkType: TopologyLinkType = .fiber10G
    @State private var speedMbps: Int = 10_000
    @State private var vlanIdText: String = ""
    @State private var vlanTrunkText: String = "10, 20, 30"
    @State private var mtu: Int = 1500

    public init(
        isPresented: Binding<Bool>,
        sourceNode: TopologyNode,
        targetNode: TopologyNode,
        onAddLink: @escaping (TopologyLink) -> Void
    ) {
        self._isPresented = isPresented
        self.sourceNode = sourceNode
        self.targetNode = targetNode
        self.onAddLink = onAddLink
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "cable.connector")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.cyanPulse)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Patch New Cable Connection")
                        .font(Theme.monoText(14, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("\(sourceNode.label)  ⟶  \(targetNode.label)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider().overlay(Theme.borderLight)

            // Cable Media Type Picker
            VStack(alignment: .leading, spacing: 6) {
                Text("CABLE MEDIA / LINK TYPE")
                    .font(Theme.monoText(10, weight: .bold))
                    .foregroundStyle(.secondary)

                Picker("Link Type", selection: $linkType) {
                    ForEach(TopologyLinkType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: linkType) { _, newType in
                    switch newType {
                    case .ethernet: speedMbps = 1_000
                    case .fiber10G: speedMbps = 10_000
                    case .fiber100G: speedMbps = 100_000
                    case .portChannel: speedMbps = 20_000
                    case .wireless: speedMbps = 1_200
                    case .vpnTunnel: speedMbps = 1_000
                    }
                }
            }

            // Interface Port Pair
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SOURCE PORT (\(sourceNode.label))")
                        .font(Theme.monoText(9, weight: .bold))
                        .foregroundStyle(.secondary)
                    TextField("e.g. Eth1/1", text: $sourceInterface)
                        .textFieldStyle(.roundedBorder)
                        .font(Theme.monoText(12))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("TARGET PORT (\(targetNode.label))")
                        .font(Theme.monoText(9, weight: .bold))
                        .foregroundStyle(.secondary)
                    TextField("e.g. Te1/1/2", text: $targetInterface)
                        .textFieldStyle(.roundedBorder)
                        .font(Theme.monoText(12))
                }
            }

            // Layer 2 / VLAN Settings
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ACCESS VLAN (OPTIONAL)")
                        .font(Theme.monoText(9, weight: .bold))
                        .foregroundStyle(.secondary)
                    TextField("e.g. 10", text: $vlanIdText)
                        .textFieldStyle(.roundedBorder)
                        .font(Theme.monoText(12))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("ALLOWED TRUNK VLANS")
                        .font(Theme.monoText(9, weight: .bold))
                        .foregroundStyle(.secondary)
                    TextField("e.g. 10, 20, 30", text: $vlanTrunkText)
                        .textFieldStyle(.roundedBorder)
                        .font(Theme.monoText(12))
                }
            }

            // MTU Frame Size
            HStack {
                Text("FRAME MTU:")
                    .font(Theme.monoText(10, weight: .bold))
                    .foregroundStyle(.secondary)
                Picker("MTU", selection: $mtu) {
                    Text("1500 Standard").tag(1500)
                    Text("9000 Jumbo Frame").tag(9000)
                    Text("9216 Data Center").tag(9216)
                }
                .pickerStyle(.menu)
                .frame(width: 180)
            }

            Divider().overlay(Theme.borderLight)

            // Action Buttons
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Patch Cable") {
                    let vlan = Int(vlanIdText.trimmingCharacters(in: .whitespaces))
                    let trunkVlans = vlanTrunkText
                        .split(separator: ",")
                        .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }

                    let link = TopologyLink(
                        sourceNodeId: sourceNode.id,
                        targetNodeId: targetNode.id,
                        sourceInterface: sourceInterface.isEmpty ? "Eth1/1" : sourceInterface,
                        targetInterface: targetInterface.isEmpty ? "Eth1/1" : targetInterface,
                        linkType: linkType,
                        speedMbps: speedMbps,
                        status: .online,
                        vlanId: vlan,
                        duplex: "Full",
                        mtu: mtu,
                        vlanTrunkAllowed: trunkVlans
                    )
                    onAddLink(link)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.cyanPulse)
            }
        }
        .padding(20)
        .frame(width: 460)
        .background(Theme.surfaceBackground)
    }
}
