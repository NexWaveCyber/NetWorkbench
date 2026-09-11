import SwiftUI
import NetworkCore

public struct SubnetCalculatorView: View {
    @State private var cidrInput = "192.168.10.0/24"
    @State private var calculatedNetwork: IPNetwork? = IPNetwork("192.168.10.0/24")

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Input Card
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("IP SUBNET & CIDR CALCULATOR")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.neonCyan)
                        Spacer()
                        Text("VLSM / RFC 1918 / RFC 3021")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }

                    HStack(spacing: 12) {
                        Image(systemName: "number.square.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(Theme.neonCyan)

                        TextField("Enter subnet CIDR (e.g. 10.20.0.0/22, 172.16.1.0/24)...", text: $cidrInput)
                            .textFieldStyle(.plain)
                            .font(Theme.monoText(16))
                            .onChange(of: cidrInput) { _, newValue in
                                calculatedNetwork = IPNetwork(newValue.trimmingCharacters(in: .whitespaces))
                            }

                        if let net = calculatedNetwork {
                            Text(net.address.isPrivate ? "RFC 1918 Private" : (net.address.isCarrierGradeNAT ? "RFC 6598 CGNAT" : "Public IP"))
                                .font(Theme.monoText(10, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Theme.azurePro.opacity(0.15))
                                .foregroundStyle(Theme.azurePro)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(12)
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.cyanPulse.opacity(0.3), lineWidth: 1))

                    // Preset Prefix Chips
                    HStack(spacing: 6) {
                        Text("Quick Prefixes:")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        ForEach([8, 16, 24, 26, 28, 30], id: \.self) { prefix in
                            Button("/\(prefix)") {
                                if let base = calculatedNetwork?.networkAddress.description {
                                    let sanitizedBase = base.components(separatedBy: "/").first ?? base
                                    cidrInput = "\(sanitizedBase)/\(prefix)"
                                    calculatedNetwork = IPNetwork(cidrInput)
                                }
                            }
                            .buttonStyle(.plain)
                            .font(Theme.monoText(11, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(calculatedNetwork?.prefixLength == prefix ? Theme.neonCyan.opacity(0.18) : Color.primary.opacity(0.04))
                            .foregroundStyle(calculatedNetwork?.prefixLength == prefix ? Theme.neonCyan : Color.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(calculatedNetwork?.prefixLength == prefix ? Theme.neonCyan : Theme.borderLight, lineWidth: 1))
                        }
                    }
                }
                .engineeringCard(padding: 16)

                if let net = calculatedNetwork {
                    // Visual Allocation Bar
                    allocationBar(net: net)

                    // Binary View Card
                    binaryViewCard(net: net)

                    // Subnet Parameter Grid
                    subnetGrid(net: net)

                    // Subnet Splitting
                    subnetSplitterCard(net: net)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 28))
                            .foregroundStyle(Theme.solarAmber)
                        Text("Invalid CIDR format. Please enter an IP address followed by prefix (e.g. 192.168.1.0/24).")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 160)
                    .engineeringCard()
                }
            }
            .padding(24)
        }
        .background(Theme.secondaryBackground)
        .navigationTitle("IP Studio / Subnet Calculator")
    }

    private func allocationBar(net: IPNetwork) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ADDRESS SPACE ALLOCATION")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("Prefix: /\(net.prefixLength) (\(net.usableHostCount.formatted()) usable hosts)")
                    .font(Theme.monoText(10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                let w = geo.size.width
                let netFraction = CGFloat(net.prefixLength) / 32.0

                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.cyanGlowGradient)
                        .frame(width: max(4, w * netFraction))

                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: max(4, w * (1.0 - netFraction)))
                }
            }
            .frame(height: 10)
            .clipShape(Capsule())
        }
        .engineeringCard(padding: 14)
    }

    private func binaryViewCard(net: IPNetwork) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("32-BIT BINARY BITMASK BREAKDOWN")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 12) {
                    HStack(spacing: 5) {
                        Circle().fill(Theme.neonCyan).frame(width: 6, height: 6)
                        Text("Network (\(net.prefixLength) bits)").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 5) {
                        Circle().fill(Color.primary.opacity(0.25)).frame(width: 6, height: 6)
                        Text("Host (\(32 - net.prefixLength) bits)").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    }
                }
            }

            if case .v4(let v4) = net.networkAddress {
                let bits = String(v4.rawValue, radix: 2)
                let padded = String(repeating: "0", count: max(0, 32 - bits.count)) + bits

                HStack(spacing: 8) {
                    ForEach(0..<4) { byteIndex in
                        let start = padded.index(padded.startIndex, offsetBy: byteIndex * 8)
                        let end = padded.index(start, offsetBy: 8)
                        let octetBits = String(padded[start..<end])

                        HStack(spacing: 3) {
                            ForEach(0..<8) { bitIndex in
                                let globalIndex = byteIndex * 8 + bitIndex
                                let isNetworkBit = globalIndex < net.prefixLength
                                Text(String(octetBits[octetBits.index(octetBits.startIndex, offsetBy: bitIndex)]))
                                    .font(Theme.monoText(12, weight: .bold))
                                    .foregroundStyle(isNetworkBit ? Theme.neonCyan : Color.primary.opacity(0.28))
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.borderLight, lineWidth: 1))

                        if byteIndex < 3 {
                            Text(".")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.secondary.opacity(0.6))
                        }
                    }
                }
            }
        }
        .engineeringCard(padding: 14)
    }

    private func subnetGrid(net: IPNetwork) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            paramCard(label: "Network Address", val: net.networkAddress.description, icon: "network")
            paramCard(label: "Broadcast Address", val: net.broadcastAddress?.description ?? "N/A (IPv6)", icon: "antenna.radiowaves.left.and.right")
            paramCard(label: "Subnet Mask", val: net.ipv4Netmask?.description ?? "N/A", icon: "shield")
            paramCard(label: "Wildcard Mask", val: net.ipv4WildcardMask?.description ?? "N/A", icon: "square.dashed")
            paramCard(label: "Usable Host Range", val: "\(net.firstUsableAddress?.description ?? "-") → \(net.lastUsableAddress?.description ?? "-")", icon: "arrow.left.and.right")
            paramCard(label: "Total Usable Hosts", val: "\(net.usableHostCount.formatted())", icon: "server.rack", highlightColor: Theme.signalEmerald)
        }
    }

    private func subnetSplitterCard(net: IPNetwork) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SUBNET SPLIT (/N+1)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Split into 2 equal equal-sized child subnets")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if net.prefixLength < 32, case .v4(let v4) = net.networkAddress {
                let newPrefix = net.prefixLength + 1
                let halfHosts = UInt32(1) << (32 - newPrefix)
                let net1 = IPNetwork(address: .v4(v4), prefixLength: newPrefix)!
                let net2 = IPNetwork(address: .v4(IPAddress.IPv4(rawValue: v4.rawValue + halfHosts)), prefixLength: newPrefix)!

                HStack(spacing: 14) {
                    splitPill(net: net1)
                    splitPill(net: net2)
                }
            }
        }
        .engineeringCard(padding: 14)
    }

    private func splitPill(net: IPNetwork) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(net.description)
                    .font(Theme.monoText(13, weight: .bold))
                Text("\(net.usableHostCount) Usable Hosts (\(net.firstUsableAddress?.description ?? "") – \(net.lastUsableAddress?.description ?? ""))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(net.description, forType: .string)
            }) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.borderLight, lineWidth: 1))
    }

    private func paramCard(label: String, val: String, icon: String, highlightColor: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.azurePro)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Text(val)
                .font(Theme.monoText(13, weight: .bold))
                .foregroundStyle(highlightColor ?? Color.primary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.borderLight, lineWidth: 1))
    }
}
