//
//  AddCanvasDeviceSheet.swift
//  NexWaveApp
//
//  Add Custom Network Device to Topology Canvas
//

import SwiftUI
import DeviceKit
import NetworkCore

public struct AddCanvasDeviceSheet: View {
    @Binding public var isPresented: Bool
    public let onAddNode: (TopologyNode) -> Void

    @State private var label: String = ""
    @State private var ipAddress: String = ""
    @State private var macAddress: String = ""
    @State private var role: DeviceRole = .switchRole
    @State private var vendor: DeviceVendor = .cisco
    @State private var platform: String = ""
    @State private var tier: TopologyTier = .access
    @State private var vlansText: String = "10, 20"

    public init(isPresented: Binding<Bool>, onAddNode: @escaping (TopologyNode) -> Void) {
        self._isPresented = isPresented
        self.onAddNode = onAddNode
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.cyanPulse)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add Network Device to Canvas")
                        .font(Theme.monoText(14, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("Place a new router, switch, firewall, or server onto the canvas")
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

            // Form Fields
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("DEVICE LABEL / HOSTNAME")
                            .font(Theme.monoText(9, weight: .bold))
                            .foregroundStyle(.secondary)
                        TextField("e.g. dist-sw03.floor3", text: $label)
                            .textFieldStyle(.roundedBorder)
                            .font(Theme.monoText(12))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("IP ADDRESS")
                            .font(Theme.monoText(9, weight: .bold))
                            .foregroundStyle(.secondary)
                        TextField("e.g. 10.0.10.3", text: $ipAddress)
                            .textFieldStyle(.roundedBorder)
                            .font(Theme.monoText(12))
                    }
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("MAC ADDRESS (OPTIONAL)")
                            .font(Theme.monoText(9, weight: .bold))
                            .foregroundStyle(.secondary)
                        TextField("00:1C:58:AA:BB:CC", text: $macAddress)
                            .textFieldStyle(.roundedBorder)
                            .font(Theme.monoText(12))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("HARDWARE PLATFORM")
                            .font(Theme.monoText(9, weight: .bold))
                            .foregroundStyle(.secondary)
                        TextField("e.g. Catalyst 9300-48UXM", text: $platform)
                            .textFieldStyle(.roundedBorder)
                            .font(Theme.monoText(12))
                    }
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ROLE")
                            .font(Theme.monoText(9, weight: .bold))
                            .foregroundStyle(.secondary)
                        Picker("Role", selection: $role) {
                            ForEach(DeviceRole.allCases, id: \.self) { r in
                                Text(r.rawValue).tag(r)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("ARCHITECTURAL TIER")
                            .font(Theme.monoText(9, weight: .bold))
                            .foregroundStyle(.secondary)
                        Picker("Tier", selection: $tier) {
                            ForEach(TopologyTier.allCases, id: \.self) { t in
                                Text(t.rawValue).tag(t)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("VENDOR")
                            .font(Theme.monoText(9, weight: .bold))
                            .foregroundStyle(.secondary)
                        Picker("Vendor", selection: $vendor) {
                            ForEach(DeviceVendor.allCases, id: \.self) { v in
                                Text(v.rawValue).tag(v)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("ACTIVE VLANS (COMMA SEPARATED)")
                        .font(Theme.monoText(9, weight: .bold))
                        .foregroundStyle(.secondary)
                    TextField("10, 20, 30", text: $vlansText)
                        .textFieldStyle(.roundedBorder)
                        .font(Theme.monoText(12))
                }
            }

            Divider().overlay(Theme.borderLight)

            // Action Buttons
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Add to Canvas") {
                    let cleanedLabel = label.trimmingCharacters(in: .whitespaces)
                    let cleanedIP = ipAddress.trimmingCharacters(in: .whitespaces)
                    let vlans = vlansText
                        .split(separator: ",")
                        .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }

                    let node = TopologyNode(
                        id: "custom-\(UUID().uuidString.prefix(8).lowercased())",
                        label: cleanedLabel.isEmpty ? "new-node" : cleanedLabel,
                        role: role,
                        vendor: vendor,
                        ipAddress: cleanedIP.isEmpty ? "192.168.1.100" : cleanedIP,
                        macAddress: macAddress.isEmpty ? nil : macAddress,
                        platform: platform.isEmpty ? nil : platform,
                        status: .online,
                        tier: tier,
                        position: CGPoint(x: 450, y: 250),
                        vlans: vlans.isEmpty ? [1] : vlans
                    )
                    onAddNode(node)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.cyanPulse)
            }
        }
        .padding(20)
        .frame(width: 480)
        .background(Theme.surfaceBackground)
    }
}
