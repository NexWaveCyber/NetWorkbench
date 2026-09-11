import SwiftUI
import SecurityKit

public struct SecondaryWorkspaceView: View {
    let title: String
    let icon: String
    let subtitle: String
    let capabilities: [String]

    public init(title: String, icon: String, subtitle: String, capabilities: [String]) {
        self.title = title
        self.icon = icon
        self.subtitle = subtitle
        self.capabilities = capabilities
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // Header Banner
                headerBanner

                // Interactive Workbench Preview / Simulation Module
                workbenchInteractivePreview

                // Capabilities Matrix
                capabilitiesGrid
            }
            .padding(24)
        }
        .background(Theme.secondaryBackground)
        .navigationTitle(title)
    }

    // MARK: - Header Banner
    private var headerBanner: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.neonCyan.opacity(0.12))
                    .frame(width: 52, height: 52)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Theme.neonCyan.opacity(0.3), lineWidth: 1)
                    )

                Image(systemName: icon)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.neonCyan)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("ENGINEERING WORKBENCH")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.neonCyan)
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text("NATIVE PRODUCTION ENGINE")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                Text(title)
                    .font(.system(size: 22, weight: .bold))

                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HUDStatusBadge(title: "PRO ENGINE", color: Theme.azurePro, isPulsing: false, icon: "bolt.shield.fill")
        }
        .engineeringCard(padding: 18)
    }

    // MARK: - Interactive Preview Module per Workbench
    @ViewBuilder
    private var workbenchInteractivePreview: some View {
        if title.contains("Device") {
            deviceWorkbenchPreview
        } else if title.contains("SNMP") {
            snmpStudioPreview
        } else if title.contains("Config") {
            configWorkbenchPreview
        } else if title.contains("Packet") {
            packetWorkbenchPreview
        } else if title.contains("Settings") {
            settingsSecurityPreview
        } else {
            environmentsPreview
        }
    }

    // MARK: - Device Workbench Preview
    private var deviceWorkbenchPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Circle().fill(Theme.signalEmerald).frame(width: 6, height: 6)
                    Text("LOCAL NETWORK DISCOVERY & MANAGED INVENTORY")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("ARP/NDP Cache + Bonjour")
                    .font(Theme.monoText(10))
                    .foregroundStyle(.tertiary)
            }

            VStack(spacing: 8) {
                deviceRow(name: "core-sw01.dc01", ip: "10.0.10.1", vendor: "Cisco IOS-XE", model: "Catalyst 9300", status: "Healthy", ping: "0.8 ms")
                deviceRow(name: "dist-rtr02.dc01", ip: "10.0.10.2", vendor: "Arista EOS", model: "7050SX3", status: "Healthy", ping: "1.2 ms")
                deviceRow(name: "edge-fw01.prod", ip: "10.0.0.1", vendor: "Juniper Junos", model: "SRX345", status: "Active", ping: "2.4 ms")
            }
        }
        .engineeringCard(padding: 16)
    }

    private func deviceRow(name: String, ip: String, vendor: String, model: String, status: String, ping: String) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Theme.signalEmerald)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(Theme.monoText(13, weight: .bold))
                Text("\(ip) • \(vendor) (\(model))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(ping)
                .font(Theme.monoText(11, weight: .semibold))
                .foregroundStyle(Theme.neonCyan)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.neonCyan.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 4))

            Button("Terminal SSH") {}
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(10)
        .background(Color.primary.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - SNMP Studio Preview
    private var snmpStudioPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("PURE SWIFT MIB TRIE BROWSER & COUNTER STREAM")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("RFC 1213 / IF-MIB (64-bit HC)")
                    .font(Theme.monoText(10))
                    .foregroundStyle(.tertiary)
            }

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    mibItem(oid: "1.3.6.1.2.1.1.1.0", name: "sysDescr.0", val: "Cisco IOS Software, C9300-UNIVERSALK9-M")
                    mibItem(oid: "1.3.6.1.2.1.1.3.0", name: "sysUpTimeInstance", val: "142 days, 18:24:02.19")
                    mibItem(oid: "1.3.6.1.2.1.2.2.1.10.1", name: "ifInOctets.1 (Gi1/0/1)", val: "48,219,840,192 bytes")
                    mibItem(oid: "1.3.6.1.2.1.2.2.1.14.1", name: "ifInErrors.1 (Gi1/0/1)", val: "0 errors (0.00%)")
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 8) {
                    Text("BANDWIDTH UTILIZATION")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("RX Ingress")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Text("342.5 Mbps")
                                .font(Theme.monoText(13, weight: .bold))
                                .foregroundStyle(Theme.signalEmerald)
                        }
                        Spacer()
                        VStack(alignment: .leading, spacing: 2) {
                            Text("TX Egress")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Text("188.1 Mbps")
                                .font(Theme.monoText(13, weight: .bold))
                                .foregroundStyle(Theme.neonCyan)
                        }
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .frame(width: 240)
            }
        }
        .engineeringCard(padding: 16)
    }

    private func mibItem(oid: String, name: String, val: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(Theme.monoText(11, weight: .bold))
                Text(oid)
                    .font(Theme.monoText(9))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Text(val)
                .font(Theme.monoText(11))
                .foregroundStyle(.secondary)
        }
        .padding(6)
        .background(Color.primary.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Config Workbench Preview
    private var configWorkbenchPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("STRUCTURAL CONFIGURATION DIFF")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Running vs. Proposed Candidate")
                    .font(Theme.monoText(10))
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 4) {
                diffLine(prefix: " ", code: "interface GigabitEthernet1/0/24", color: .secondary)
                diffLine(prefix: " ", code: " description Uplink to Spine-01", color: .secondary)
                diffLine(prefix: "-", code: " switchport trunk allowed vlan 10,20,30", color: Theme.pulseCrimson)
                diffLine(prefix: "+", code: " switchport trunk allowed vlan 10,20,30,40,50", color: Theme.signalEmerald)
                diffLine(prefix: " ", code: " spanning-tree portfast edge trunk", color: .secondary)
                diffLine(prefix: "+", code: " storm-control broadcast level 1.0", color: Theme.signalEmerald)
            }
            .padding(12)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .engineeringCard(padding: 16)
    }

    private func diffLine(prefix: String, code: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Text(prefix)
                .font(Theme.monoText(12, weight: .bold))
                .foregroundStyle(color)
            Text(code)
                .font(Theme.monoText(12))
                .foregroundStyle(color == .secondary ? Color.primary.opacity(0.85) : color)
        }
    }

    // MARK: - Packet Workbench Preview
    private var packetWorkbenchPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("STREAMING CAPTURE FLOW ANALYZER (PCAP/PCAPNG)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Open in Wireshark") {}
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            VStack(spacing: 6) {
                flowRow(src: "192.168.1.142:54210", dst: "142.250.190.46:443", proto: "TCP / TLS 1.3", packets: "1,420", bytes: "1.8 MB", flag: "Established")
                flowRow(src: "192.168.1.142:58312", dst: "1.1.1.1:853", proto: "DoT (DNS-over-TLS)", packets: "48", bytes: "14.2 KB", flag: "Zero Retrans")
                flowRow(src: "10.0.0.15:445", dst: "192.168.1.142:50221", proto: "SMB", packets: "892", bytes: "4.1 MB", flag: "Active Flow")
            }
        }
        .engineeringCard(padding: 16)
    }

    private func flowRow(src: String, dst: String, proto: String, packets: String, bytes: String, flag: String) -> some View {
        HStack(spacing: 10) {
            Text(proto)
                .font(Theme.monoText(10, weight: .bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.azurePro.opacity(0.12))
                .foregroundStyle(Theme.azurePro)
                .clipShape(Capsule())

            Text("\(src) → \(dst)")
                .font(Theme.monoText(11))
                .lineLimit(1)

            Spacer()

            Text("\(packets) pkts (\(bytes))")
                .font(Theme.monoText(10))
                .foregroundStyle(.secondary)

            Text(flag)
                .font(Theme.monoText(9, weight: .semibold))
                .foregroundStyle(Theme.signalEmerald)
        }
        .padding(8)
        .background(Color.primary.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Settings & Security Preview
    private var settingsSecurityPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LOCAL PRIVACY & SECURITY ATTESTATION")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                securityCard(label: "HARDWARE KEYCHAIN", val: "Hardware Enclave Enforced", status: "Secure", icon: "key.fill")
                securityCard(label: "STORAGE ENGINE", val: "SQLite WAL Mode (Local-Only)", status: "Active", icon: "internaldrive.fill")
                securityCard(label: "CLOUD TELEMETRY", val: "0 Tracking / 0 Third-Party", status: "Zero-Leak", icon: "hand.raised.fill")
            }
        }
        .engineeringCard(padding: 16)
    }

    private func securityCard(label: String, val: String, status: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(Theme.signalEmerald)
                Text(label)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(status)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.signalEmerald)
            }
            Text(val)
                .font(Theme.monoText(11, weight: .semibold))
        }
        .padding(10)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var environmentsPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SCOPED ENGINEERING WORKSPACES")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                envPill(name: "Production DC01", subnets: "10.0.0.0/16", devices: 48)
                envPill(name: "Staging Lab", subnets: "192.168.100.0/24", devices: 12)
                envPill(name: "Customer Branch VPN", subnets: "172.16.0.0/20", devices: 6)
            }
        }
        .engineeringCard(padding: 16)
    }

    private func envPill(name: String, subnets: String, devices: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name).font(.system(size: 12, weight: .bold))
            Text(subnets).font(Theme.monoText(10)).foregroundStyle(.secondary)
            Text("\(devices) Registered Devices").font(.system(size: 10)).foregroundStyle(Theme.neonCyan)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Capabilities List
    private var capabilitiesGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ENGINE CAPABILITIES & SPECIFICATIONS")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(capabilities, id: \.self) { cap in
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundStyle(Theme.signalEmerald)
                            .font(.system(size: 13))
                        Text(cap)
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                    }
                    .padding(12)
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.borderLight, lineWidth: 1))
                }
            }
        }
    }
}
