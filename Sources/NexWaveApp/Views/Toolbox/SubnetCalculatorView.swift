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
                VStack(alignment: .leading, spacing: 12) {
                    Text("IP SUBNET & CIDR CALCULATOR")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.cyanPulse)

                    HStack(spacing: 12) {
                        Image(systemName: "number.square.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Theme.azurePro)

                        TextField("Enter subnet CIDR (e.g. 10.20.0.0/22, 172.16.1.0/24)...", text: $cidrInput)
                            .textFieldStyle(.plain)
                            .font(Theme.monoText(15))
                            .onChange(of: cidrInput) { _, newValue in
                                calculatedNetwork = IPNetwork(newValue.trimmingCharacters(in: .whitespaces))
                            }

                        if let net = calculatedNetwork {
                            Text(net.address.isPrivate ? "RFC 1918 Private" : (net.address.isCarrierGradeNAT ? "RFC 6598 CGNAT" : "Public IP"))
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Theme.azurePro.opacity(0.15))
                                .foregroundStyle(Theme.azurePro)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(12)
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderLight, lineWidth: 1))
                }
                .engineeringCard()

                if let net = calculatedNetwork {
                    // Binary View Card
                    binaryViewCard(net: net)

                    // Subnet Parameter Grid
                    subnetGrid(net: net)

                    // Subnet Splitting
                    subnetSplitterCard(net: net)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 24))
                            .foregroundStyle(Theme.amberWarning)
                        Text("Invalid CIDR format. Please enter an IP address followed by prefix (e.g. 192.168.1.0/24).")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .engineeringCard()
                }
            }
            .padding(24)
        }
        .background(Theme.secondaryBackground)
        .navigationTitle("IP Studio / Subnet Calculator")
    }

    private func binaryViewCard(net: IPNetwork) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("BINARY BITMASK BREAKDOWN")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)

            if case .v4(let v4) = net.networkAddress {
                let bits = String(v4.rawValue, radix: 2)
                let padded = String(repeating: "0", count: max(0, 32 - bits.count)) + bits

                HStack(spacing: 8) {
                    ForEach(0..<4) { byteIndex in
                        let start = padded.index(padded.startIndex, offsetBy: byteIndex * 8)
                        let end = padded.index(start, offsetBy: 8)
                        let octetBits = String(padded[start..<end])

                        HStack(spacing: 2) {
                            ForEach(0..<8) { bitIndex in
                                let globalIndex = byteIndex * 8 + bitIndex
                                let isNetworkBit = globalIndex < net.prefixLength
                                Text(String(octetBits[octetBits.index(octetBits.startIndex, offsetBy: bitIndex)]))
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(isNetworkBit ? Theme.cyanPulse : Color.primary.opacity(0.35))
                            }
                        }
                        .padding(6)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                        if byteIndex < 3 {
                            Text(".")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Circle().fill(Theme.cyanPulse).frame(width: 6, height: 6)
                            Text("Network (\(net.prefixLength)b)").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 4) {
                            Circle().fill(Color.primary.opacity(0.35)).frame(width: 6, height: 6)
                            Text("Host (\(32 - net.prefixLength)b)").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .engineeringCard()
    }

    private func subnetGrid(net: IPNetwork) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            paramCard(label: "Network Address", val: net.networkAddress.description, icon: "network")
            paramCard(label: "Broadcast Address", val: net.broadcastAddress?.description ?? "N/A (IPv6)", icon: "antenna.radiowaves.left.and.right")
            paramCard(label: "Subnet Mask", val: net.ipv4Netmask?.description ?? "N/A", icon: "shield")
            paramCard(label: "Wildcard Mask", val: net.ipv4WildcardMask?.description ?? "N/A", icon: "square.dashed")
            paramCard(label: "Usable Host Range", val: "\(net.firstUsableAddress?.description ?? "-") → \(net.lastUsableAddress?.description ?? "-")", icon: "arrow.left.and.right")
            paramCard(label: "Usable Hosts", val: "\(net.usableHostCount.formatted())", icon: "server.rack", highlightColor: Theme.emeraldHealthy)
        }
    }

    private func subnetSplitterCard(net: IPNetwork) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SUBNET SPLIT (/N+1)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Split into 2 equal subnets")
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
        .engineeringCard()
    }

    private func splitPill(net: IPNetwork) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(net.description)
                    .font(Theme.monoText(13, weight: .semibold))
                Text("\(net.usableHostCount) Usable Hosts (\(net.firstUsableAddress?.description ?? "") - \(net.lastUsableAddress?.description ?? ""))")
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
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 6))
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
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderLight, lineWidth: 1))
    }
}
