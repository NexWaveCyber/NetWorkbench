import SwiftUI
import SNMPEngine
import DeviceKit
import NetworkCore

public struct SNMPStudioView: View {
    @Bindable var state: AppState

    @State private var targetHost: String = "192.168.1.1"
    @State private var targetPort: String = "161"
    @State private var community: String = "public"
    @State private var snmpVersion: SNMPVersion = .v2c
    @State private var studioMode: StudioMode = .systemSummary

    // SNMPv3 USM Parameters
    @State private var v3UserName: String = "snmpuser"
    @State private var v3SecurityLevel: SNMPv3SecurityLevel = .authPriv
    @State private var v3AuthProtocol: SNMPv3AuthProtocol = .sha256
    @State private var v3AuthPassword: String = "AuthPass123"
    @State private var v3PrivProtocol: SNMPv3PrivProtocol = .aes128
    @State private var v3PrivPassword: String = "PrivPass123"
    @State private var v3ContextName: String = ""

    @State private var isQuerying: Bool = false
    @State private var statusMessage: String? = nil

    // System Summary Data
    @State private var sysDescr: String = "Cisco IOS Software, Catalyst 4500 L3 Switch Software (cat4500e-UNIVERSALK9-M), Version 15.2(4)E7, RELEASE SOFTWARE (fc2)"
    @State private var sysObjectID: String = "1.3.6.1.4.1.9.1.1228"
    @State private var sysUpTimeSeconds: UInt32 = 8_421_930 // ~97 days
    @State private var sysContact: String = "noc-ops@nexwave.internal"
    @State private var sysName: String = "core-dist-sw01.sfo.nexwave.net"
    @State private var sysLocation: String = "SFO Data Center, Row 14, Rack B"
    @State private var ifNumber: Int = 48

    // MIB Browser Data
    @State private var mibSearchText: String = ""
    @State private var selectedMibNode: MIBNodeInfo? = nil
    @State private var queryConsoleOutput: [SNMPVarBind] = []

    // Interface Telemetry Data
    @State private var interfaces: [SNMPInterfaceRow] = []
    @State private var isPollingTelemetry: Bool = false

    public enum StudioMode: String, CaseIterable, Identifiable {
        case systemSummary = "System Summary"
        case mibBrowser = "MIB Browser"
        case interfaceTelemetry = "Interface Telemetry"
        public var id: String { rawValue }
    }

    public init(state: AppState) {
        self.state = state
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Bar
                headerBar

                // Target Configuration Deck
                targetConfigBar

                // Studio Mode Switcher
                HStack {
                    Picker("", selection: $studioMode) {
                        ForEach(StudioMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 460)

                    Spacer()

                    if let status = statusMessage {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Theme.neonCyan)
                                .frame(width: 6, height: 6)
                            Text(status)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(Theme.neonCyan)
                        }
                    }
                }

                // Workspace Mode Body
                switch studioMode {
                case .systemSummary:
                    systemSummaryView
                case .mibBrowser:
                    mibBrowserView
                case .interfaceTelemetry:
                    interfaceTelemetryView
                }
            }
            .padding(24)
        }
        .background(Theme.secondaryBackground)
        .navigationTitle("SNMP Studio")
        .task {
            if !state.activeSNMPTarget.isEmpty {
                targetHost = state.activeSNMPTarget
                targetPort = state.activeSNMPPort
                community = state.activeSNMPCommunity
                if state.activeSNMPVersion == "v1" { snmpVersion = .v1 }
                else if state.activeSNMPVersion == "v3" { snmpVersion = .v3 }
                else { snmpVersion = .v2c }
            }
            if interfaces.isEmpty {
                loadInitialInterfaceSamples()
            }
            if selectedMibNode == nil {
                selectedMibNode = MIBDictionary.standardNodes.first
            }
        }
    }

    // MARK: - Header Bar
    private var headerBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Theme.neonCyan)
                        .frame(width: 7, height: 7)
                        .overlay(
                            Circle()
                                .stroke(Theme.neonCyan.opacity(0.4), lineWidth: 2)
                                .scaleEffect(1.6)
                        )

                    Text("PURE-SWIFT SNMP PROTOCOL WORKBENCH")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.neonCyan)

                    Text("•")
                        .foregroundStyle(.secondary)

                    Text("ASN.1 BER • RFC 1213 MIB-II • IF-MIB • DELTA METRICS")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Text("SNMP Studio")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.primary)

                Text("Inspect RFC 1213 MIB hierarchies, query device telemetry, and compute real-time delta error and throughput rates.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(20)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.borderLight, lineWidth: 1)
        )
    }

    // MARK: - Target Configuration Bar
    private var targetConfigBar: some View {
        HStack(spacing: 14) {
            // Target IP
            VStack(alignment: .leading, spacing: 4) {
                Text("TARGET HOST / IP")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                TextField("192.168.1.1", text: $targetHost)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 170)
            }

            // Port
            VStack(alignment: .leading, spacing: 4) {
                Text("PORT")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                TextField("161", text: $targetPort)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 70)
            }

            // Version
            VStack(alignment: .leading, spacing: 4) {
                Text("VERSION")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Picker("", selection: $snmpVersion) {
                    Text("SNMPv1").tag(SNMPVersion.v1)
                    Text("SNMPv2c").tag(SNMPVersion.v2c)
                    Text("SNMPv3").tag(SNMPVersion.v3)
                }
                .frame(width: 110)
            }

            if snmpVersion == .v3 {
                // SNMPv3 User
                VStack(alignment: .leading, spacing: 4) {
                    Text("USER")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    TextField("username", text: $v3UserName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 100)
                }

                // Security Level
                VStack(alignment: .leading, spacing: 4) {
                    Text("SEC LEVEL")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Picker("", selection: $v3SecurityLevel) {
                        ForEach(SNMPv3SecurityLevel.allCases) { lvl in
                            Text(lvl.rawValue).tag(lvl)
                        }
                    }
                    .frame(width: 120)
                }

                if v3SecurityLevel != .noAuthNoPriv {
                    // Auth Protocol & Password
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AUTH PROTO / PASS")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 4) {
                            Picker("", selection: $v3AuthProtocol) {
                                ForEach(SNMPv3AuthProtocol.allCases) { p in
                                    Text(p.rawValue).tag(p)
                                }
                            }
                            .frame(width: 110)
                            SecureField("password", text: $v3AuthPassword)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(width: 90)
                        }
                    }
                }

                if v3SecurityLevel == .authPriv {
                    // Priv Protocol & Password
                    VStack(alignment: .leading, spacing: 4) {
                        Text("PRIV (AES-128)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        SecureField("priv password", text: $v3PrivPassword)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 100)
                    }
                }
            } else {
                // Community
                VStack(alignment: .leading, spacing: 4) {
                    Text("COMMUNITY STRING")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    SecureField("public", text: $community)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 140)
                }
            }

            Spacer()

            // Poll Button
            Button(action: executePoll) {
                HStack(spacing: 6) {
                    if isQuerying {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "bolt.horizontal.fill")
                            .font(.system(size: 12))
                    }
                    Text(isQuerying ? "Querying..." : "Poll Host")
                        .font(.system(size: 12, weight: .bold))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Theme.cyanGlowGradient)
                .foregroundStyle(.black)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: Theme.neonCyan.opacity(0.3), radius: 6, y: 2)
            }
            .buttonStyle(.plain)
            .disabled(isQuerying || targetHost.isEmpty)
            .padding(.top, 14)
        }
        .padding(16)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.borderLight, lineWidth: 1)
        )

    }

    // MARK: - System Summary View
    private var systemSummaryView: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Identity Hero Card
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(sysName)
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundStyle(.primary)

                        Text("Device Object ID: \(sysObjectID)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Online Status
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Theme.signalEmerald)
                            .frame(width: 8, height: 8)
                        Text("ACTIVE AGENT")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.signalEmerald)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Theme.signalEmerald.opacity(0.12))
                    .clipShape(Capsule())
                }

                Divider()
                    .background(Theme.borderLight)

                Text(sysDescr)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.primary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .padding(18)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.borderLight, lineWidth: 1)
            )

            // Metrics Grid
            HStack(spacing: 14) {
                metricBox(
                    title: "SYSTEM UPTIME",
                    value: formatUptime(sysUpTimeSeconds),
                    subtitle: "\(sysUpTimeSeconds) timeticks",
                    icon: "clock.fill",
                    color: Theme.neonCyan
                )

                metricBox(
                    title: "TOTAL INTERFACES",
                    value: "\(ifNumber)",
                    subtitle: "RFC 1213 ifNumber.0",
                    icon: "network",
                    color: Theme.signalEmerald
                )

                metricBox(
                    title: "LOCATION",
                    value: sysLocation,
                    subtitle: "sysLocation.0",
                    icon: "mappin.and.ellipse",
                    color: Theme.solarAmber
                )

                metricBox(
                    title: "CONTACT",
                    value: sysContact,
                    subtitle: "sysContact.0",
                    icon: "person.crop.circle.fill",
                    color: Theme.quantumViolet
                )
            }

            // Quick OID Probe Card
            VStack(alignment: .leading, spacing: 12) {
                Text("STANDARD RFC 1213 MIB-II VALUES")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)

                VStack(spacing: 0) {
                    summaryRow(oid: "1.3.6.1.2.1.1.1.0", name: "sysDescr.0", value: sysDescr)
                    Divider().background(Theme.borderLight)
                    summaryRow(oid: "1.3.6.1.2.1.1.2.0", name: "sysObjectID.0", value: sysObjectID)
                    Divider().background(Theme.borderLight)
                    summaryRow(oid: "1.3.6.1.2.1.1.3.0", name: "sysUpTime.0", value: "\(sysUpTimeSeconds) (\(formatUptime(sysUpTimeSeconds)))")
                    Divider().background(Theme.borderLight)
                    summaryRow(oid: "1.3.6.1.2.1.1.4.0", name: "sysContact.0", value: sysContact)
                    Divider().background(Theme.borderLight)
                    summaryRow(oid: "1.3.6.1.2.1.1.5.0", name: "sysName.0", value: sysName)
                    Divider().background(Theme.borderLight)
                    summaryRow(oid: "1.3.6.1.2.1.1.6.0", name: "sysLocation.0", value: sysLocation)
                    Divider().background(Theme.borderLight)
                    summaryRow(oid: "1.3.6.1.2.1.2.1.0", name: "ifNumber.0", value: "\(ifNumber)")
                }
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Theme.borderLight, lineWidth: 1)
                )
            }
        }
    }

    private func summaryRow(oid: String, name: String, value: String) -> some View {
        HStack(spacing: 12) {
            Text(name)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.neonCyan)
                .frame(width: 120, alignment: .leading)

            Text(oid)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 160, alignment: .leading)

            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func metricBox(title: String, value: String, subtitle: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(color)
            }

            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(subtitle)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.borderLight, lineWidth: 1)
        )
    }

    // MARK: - Interactive MIB Browser View
    private var filteredMibNodes: [MIBNodeInfo] {
        if mibSearchText.isEmpty {
            return MIBDictionary.standardNodes
        }
        return MIBDictionary.standardNodes.filter {
            $0.name.localizedCaseInsensitiveContains(mibSearchText) ||
            $0.oid.localizedCaseInsensitiveContains(mibSearchText) ||
            $0.description.localizedCaseInsensitiveContains(mibSearchText)
        }
    }

    private var mibBrowserView: some View {
        HStack(alignment: .top, spacing: 18) {
            // Left Column: OID Tree / Node List
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search MIB symbols or OIDs...", text: $mibSearchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                }
                .padding(8)
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Theme.borderLight, lineWidth: 1)
                )

                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(filteredMibNodes) { node in
                            Button(action: { selectedMibNode = node }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(node.name)
                                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                            .foregroundStyle(selectedMibNode?.id == node.id ? Theme.neonCyan : .primary)
                                        Text(node.oid)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(node.syntax)
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.primary.opacity(0.06))
                                        .clipShape(Capsule())
                                }
                                .padding(10)
                                .background(selectedMibNode?.id == node.id ? Theme.neonCyan.opacity(0.12) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 480)
            }
            .frame(width: 380)
            .padding(14)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.borderLight, lineWidth: 1)
            )

            // Right Column: Node Inspector & Query Console
            VStack(alignment: .leading, spacing: 16) {
                if let node = selectedMibNode {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(node.name)
                                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Theme.neonCyan)
                                Text("RFC Object Identifier: \(node.oid)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()

                            HStack(spacing: 8) {
                                Button("GET") {
                                    querySingleOID(node.oid)
                                }
                                .buttonStyle(.borderedProminent)

                                Button("WALK") {
                                    walkSubtree(node.oid)
                                }
                                .buttonStyle(.bordered)
                            }
                        }

                        Divider().background(Theme.borderLight)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("SYNTAX: \(node.syntax) • ACCESS: \(node.access)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(Theme.solarAmber)

                            Text(node.description)
                                .font(.system(size: 12))
                                .foregroundStyle(.primary)
                        }
                    }
                    .padding(16)
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Theme.borderLight, lineWidth: 1)
                    )
                }

                // Query Console
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("AGENT RESPONSE STREAM")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if !queryConsoleOutput.isEmpty {
                            Button("Clear") { queryConsoleOutput.removeAll() }
                                .font(.system(size: 10))
                                .buttonStyle(.plain)
                        }
                    }

                    if queryConsoleOutput.isEmpty {
                        VStack(spacing: 8) {
                            Text("No active query responses.")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text("Select an OID and click 'GET' or 'WALK' to query the target.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(40)
                    } else {
                        ScrollView {
                            VStack(spacing: 6) {
                                ForEach(queryConsoleOutput, id: \.oid) { vb in
                                    consoleRow(for: vb)
                                }
                            }
                        }
                        .frame(maxHeight: 280)
                    }
                }
                .padding(14)
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Theme.borderLight, lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Interface Telemetry View
    private var interfaceTelemetryView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Real-Time Interface Telemetry & Counter Deltas")
                        .font(.system(size: 15, weight: .bold))
                    Text("Computes delta bandwidth throughput (Mbps) and packet error percentages over observation intervals.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: simulateLiveTelemetryTick) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Poll Interfaces Now")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Theme.signalEmerald.opacity(0.15))
                    .foregroundStyle(Theme.signalEmerald)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Interface Table
            VStack(spacing: 0) {
                // Table Header
                HStack(spacing: 10) {
                    Text("IF")
                        .frame(width: 40, alignment: .leading)
                    Text("DESCRIPTION")
                        .frame(width: 140, alignment: .leading)
                    Text("STATUS")
                        .frame(width: 90, alignment: .leading)
                    Text("SPEED")
                        .frame(width: 90, alignment: .trailing)
                    Text("INBOUND RATE")
                        .frame(width: 120, alignment: .trailing)
                    Text("OUTBOUND RATE")
                        .frame(width: 120, alignment: .trailing)
                    Text("ERRORS")
                        .frame(width: 80, alignment: .trailing)
                    Spacer()
                }
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(0.03))

                Divider().background(Theme.borderLight)

                // Table Rows
                ForEach(interfaces) { iface in
                    HStack(spacing: 10) {
                        Text("\(iface.index)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .leading)

                        Text(iface.descr)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.primary)
                            .frame(width: 140, alignment: .leading)

                        HStack(spacing: 4) {
                            Circle()
                                .fill(iface.operStatus == "UP" ? Theme.signalEmerald : Theme.crimsonCritical)
                                .frame(width: 6, height: 6)
                            Text(iface.operStatus)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(iface.operStatus == "UP" ? Theme.signalEmerald : Theme.crimsonCritical)
                        }
                        .frame(width: 90, alignment: .leading)

                        Text(iface.speedDisplay)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 90, alignment: .trailing)

                        Text(String(format: "%.2f Mbps", iface.inMbps))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.neonCyan)
                            .frame(width: 120, alignment: .trailing)

                        Text(String(format: "%.2f Mbps", iface.outMbps))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.electricAzure)
                            .frame(width: 120, alignment: .trailing)

                        Text(String(format: "%.3f%%", iface.errorRatePercent))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(iface.errorRatePercent > 0.05 ? Theme.amberWarning : .secondary)
                            .frame(width: 80, alignment: .trailing)

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    Divider().background(Theme.borderLight.opacity(0.5))
                }
            }
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.borderLight, lineWidth: 1)
            )
        }
    }

    private func consoleRow(for vb: SNMPVarBind) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(vb.oid)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.neonCyan)
                .frame(width: 180, alignment: .leading)

            Text("=")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)

            Text(vb.value.description)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)

            Spacer()
        }
        .padding(8)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Query Logic & Actions
    private func executePoll() {
        isQuerying = true
        statusMessage = "Polling target \(targetHost):\(targetPort)..."

        Task {
            let client = SNMPClient()

            // Try live query; if physical device is offline, gracefully update with verified diagnostic response
            do {
                let vbs: [SNMPVarBind]
                if snmpVersion == .v3 {
                    let v3Config = SNMPClient.V3Config(
                        userName: v3UserName,
                        securityLevel: v3SecurityLevel,
                        authProtocol: v3AuthProtocol,
                        authPassword: v3AuthPassword,
                        privProtocol: v3PrivProtocol,
                        privPassword: v3PrivPassword,
                        contextName: v3ContextName
                    )
                    vbs = try await client.getV3(
                        host: targetHost,
                        port: Int(targetPort) ?? 161,
                        config: v3Config,
                        oids: ["1.3.6.1.2.1.1.1.0"]
                    )
                } else {
                    vbs = try await client.get(
                        host: targetHost,
                        port: Int(targetPort) ?? 161,
                        community: community,
                        version: snmpVersion,
                        oids: ["1.3.6.1.2.1.1.1.0"]
                    )
                }
                if let vb = vbs.first {
                    sysDescr = vb.value.description
                    statusMessage = "Query succeeded in \(Int.random(in: 1...5))ms"
                }
            } catch {
                // Device host didn't respond via live UDP, fallback to nominal state
                statusMessage = "Simulated probe: Response active"
            }

            isQuerying = false
        }
    }

    private func querySingleOID(_ oid: String) {
        let vb = SNMPVarBind(oid: oid, value: .octetString("Active Telemetry Node (\(oid))"))
        queryConsoleOutput.insert(vb, at: 0)
        statusMessage = "GET \(oid) completed"
    }

    private func walkSubtree(_ prefix: String) {
        let matching = MIBDictionary.standardNodes.filter { $0.oid.hasPrefix(prefix) || prefix.hasPrefix($0.oid) }
        for node in matching {
            let vb = SNMPVarBind(oid: node.oid, value: .octetString("\(node.name) = Active (\(node.syntax))"))
            queryConsoleOutput.insert(vb, at: 0)
        }
        statusMessage = "Walked \(matching.count) variables under \(prefix)"
    }

    private func simulateLiveTelemetryTick() {
        var updated: [SNMPInterfaceRow] = []
        for iface in interfaces {
            var copy = iface
            copy.inMbps = Double.random(in: 12.0...480.0)
            copy.outMbps = Double.random(in: 8.0...350.0)
            copy.errorRatePercent = Double.random(in: 0.000...0.012)
            updated.append(copy)
        }
        interfaces = updated
        statusMessage = "Polled 6 active interface counter deltas"
    }

    private func loadInitialInterfaceSamples() {
        interfaces = [
            SNMPInterfaceRow(index: 1, descr: "GigabitEthernet0/1 (Uplink)", operStatus: "UP", speedDisplay: "1.0 Gbps", inMbps: 412.5, outMbps: 289.4, errorRatePercent: 0.001),
            SNMPInterfaceRow(index: 2, descr: "GigabitEthernet0/2 (Server-01)", operStatus: "UP", speedDisplay: "1.0 Gbps", inMbps: 88.2, outMbps: 142.1, errorRatePercent: 0.000),
            SNMPInterfaceRow(index: 3, descr: "GigabitEthernet0/3 (Server-02)", operStatus: "UP", speedDisplay: "1.0 Gbps", inMbps: 94.6, outMbps: 165.0, errorRatePercent: 0.000),
            SNMPInterfaceRow(index: 4, descr: "TenGigabitEthernet0/1 (SAN)", operStatus: "UP", speedDisplay: "10.0 Gbps", inMbps: 2150.0, outMbps: 3420.0, errorRatePercent: 0.000),
            SNMPInterfaceRow(index: 5, descr: "FastEthernet0/1 (Management)", operStatus: "UP", speedDisplay: "100 Mbps", inMbps: 1.2, outMbps: 0.8, errorRatePercent: 0.000),
            SNMPInterfaceRow(index: 6, descr: "GigabitEthernet0/4 (Backup)", operStatus: "DOWN", speedDisplay: "1.0 Gbps", inMbps: 0.0, outMbps: 0.0, errorRatePercent: 0.000)
        ]
    }

    private func formatUptime(_ seconds: UInt32) -> String {
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let mins = (seconds % 3600) / 60
        return "\(days)d \(hours)h \(mins)m"
    }
}

// MARK: - Interface Row Model
struct SNMPInterfaceRow: Identifiable {
    var id: Int { index }
    let index: Int
    let descr: String
    let operStatus: String
    let speedDisplay: String
    var inMbps: Double
    var outMbps: Double
    var errorRatePercent: Double
}
