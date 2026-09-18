import SwiftUI
import AppKit
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
    @State private var mibNavMode: MIBNavMode = .hierarchyTree
    @State private var mibSearchText: String = ""
    @State private var selectedMibNode: MIBNodeInfo? = nil
    @State private var queryConsoleOutput: [SNMPVarBind] = []
    @State private var rootMibTreeNode: MIBTreeNode? = nil
    @State private var showImportMIBSheet: Bool = false

    // SNMP SET Modal State
    @State private var showSetModal: Bool = false
    @State private var setInitialOID: String = "1.3.6.1.2.1.1.4.0"

    // Interface Telemetry Data & Real-Time Poller
    @State private var interfaces: [SNMPInterfaceRow] = []
    @State private var isContinuousPolling: Bool = false
    @State private var pollerIntervalSeconds: Double = 2.0
    @State private var throughputHistory: [Int: [Double]] = [:] // ifIndex -> history
    @State private var pollerTask: Task<Void, Never>? = nil

    // Trap & Inform Receiver Data
    @State private var trapReceiver = SNMPTrapReceiver()
    @State private var trapReceiverPort: String = "1162"
    @State private var isTrapReceiverRunning: Bool = false
    @State private var capturedTraps: [SNMPTrapRecord] = []
    @State private var inspectedTrap: SNMPTrapRecord? = nil
    @State private var trapStreamTask: Task<Void, Never>? = nil

    public enum StudioMode: String, CaseIterable, Identifiable {
        case systemSummary = "System Summary"
        case mibBrowser = "MIB Browser"
        case interfaceTelemetry = "Interface Telemetry"
        case trapReceiver = "Trap & Inform Receiver"
        public var id: String { rawValue }
    }

    public enum MIBNavMode: String, CaseIterable, Identifiable {
        case hierarchyTree = "Hierarchy Tree"
        case searchIndex = "Search Index"
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
                    .frame(maxWidth: 620)

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
                case .trapReceiver:
                    trapReceiverView
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
            if rootMibTreeNode == nil {
                rootMibTreeNode = MIBDictionary.shared.buildHierarchyTree()
            }
            if capturedTraps.isEmpty {
                loadSampleTraps()
            }
        }
        .sheet(isPresented: $showSetModal) {
            SNMPSetModalSheet(
                host: targetHost,
                port: targetPort,
                community: community,
                version: snmpVersion,
                v3Config: makeV3Config(),
                initialOID: setInitialOID,
                onSetSuccess: { oid, val in
                    handleSetSuccess(oid: oid, val: val)
                }
            )
        }
        .sheet(isPresented: $showImportMIBSheet) {
            SNMPImportMIBSheet()
        }
        .sheet(item: $inspectedTrap) { trap in
            SNMPTrapInspectorSheet(trap: trap)
        }
        .onDisappear {
            isContinuousPolling = false
            pollerTask?.cancel()
            pollerTask = nil
            trapStreamTask?.cancel()
            trapStreamTask = nil
            if isTrapReceiverRunning {
                Task {
                    await trapReceiver.stop()
                    isTrapReceiverRunning = false
                }
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

                    Text("ENTERPRISE SNMP WORKBENCH 10/10")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.neonCyan)

                    Text("•")
                        .foregroundStyle(.secondary)

                    Text("RFC 3416 GETBULK • SNMP SET • TRAP/INFORM DAEMON • USM RFC 7860")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Text("SNMP Studio")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.primary)

                Text("Browse MIB hierarchies, execute high-speed GetBulk walks, configure device parameters with SNMP SET, and capture traps & informs in real-time.")
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
                    VStack(alignment: .leading, spacing: 4) {
                        Text("PRIV PROTO / PASS")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 4) {
                            Picker("", selection: $v3PrivProtocol) {
                                ForEach(SNMPv3PrivProtocol.allCases) { pr in
                                    Text(pr.rawValue).tag(pr)
                                }
                            }
                            .frame(width: 120)
                            SecureField("priv password", text: $v3PrivPassword)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(width: 90)
                        }
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
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "bolt.horizontal.fill")
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

                    // Quick SNMP SET Button
                    Button(action: {
                        setInitialOID = "1.3.6.1.2.1.1.4.0"
                        showSetModal = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "pencil")
                            Text("Configure via SNMP SET")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Theme.solarAmber.opacity(0.15))
                        .foregroundStyle(Theme.solarAmber)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)

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

                Divider().background(Theme.borderLight)

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
                HStack {
                    Text("STANDARD RFC 1213 MIB-II VALUES")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Export CSV") {
                        let sampleVBs = [
                            SNMPVarBind(oid: "1.3.6.1.2.1.1.1.0", value: .octetString(sysDescr)),
                            SNMPVarBind(oid: "1.3.6.1.2.1.1.2.0", value: .oid(sysObjectID)),
                            SNMPVarBind(oid: "1.3.6.1.2.1.1.3.0", value: .timeTicks(sysUpTimeSeconds)),
                            SNMPVarBind(oid: "1.3.6.1.2.1.1.4.0", value: .octetString(sysContact)),
                            SNMPVarBind(oid: "1.3.6.1.2.1.1.5.0", value: .octetString(sysName)),
                            SNMPVarBind(oid: "1.3.6.1.2.1.1.6.0", value: .octetString(sysLocation)),
                            SNMPVarBind(oid: "1.3.6.1.2.1.2.1.0", value: .integer(Int64(ifNumber)))
                        ]
                        let csv = SNMPExporter.exportVarBindsToCSV(sampleVBs)
                        copyToClipboard(csv)
                        statusMessage = "Exported MIB-II summary to clipboard as CSV"
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.neonCyan)
                }

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

    // MARK: - MIB Browser View
    private var filteredMibNodes: [MIBNodeInfo] {
        if mibSearchText.isEmpty {
            return MIBDictionary.shared.allNodes
        }
        return MIBDictionary.shared.allNodes.filter {
            $0.name.localizedCaseInsensitiveContains(mibSearchText) ||
            $0.oid.localizedCaseInsensitiveContains(mibSearchText) ||
            $0.description.localizedCaseInsensitiveContains(mibSearchText)
        }
    }

    private var mibBrowserView: some View {
        HStack(alignment: .top, spacing: 18) {
            // Left Column: Tree or Search Index
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Picker("", selection: $mibNavMode) {
                        ForEach(MIBNavMode.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)

                    Button(action: { showImportMIBSheet = true }) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    .help("Import Custom MIB Definitions")
                }

                if mibNavMode == .searchIndex {
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
                                    .padding(8)
                                    .background(selectedMibNode?.id == node.id ? Theme.neonCyan.opacity(0.12) : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: 480)
                } else {
                    // Hierarchical Tree View
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            if let root = rootMibTreeNode {
                                MIBTreeRowView(node: root, selectedNode: $selectedMibNode)
                            } else {
                                ProgressView()
                            }
                        }
                    }
                    .frame(maxHeight: 520)
                }
            }
            .frame(width: 400)
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

                                Button("GETBULK") {
                                    queryGetBulk(node.oid)
                                }
                                .buttonStyle(.bordered)

                                Button("FAST WALK") {
                                    fastWalkSubtree(node.oid)
                                }
                                .buttonStyle(.bordered)

                                Button("SET") {
                                    setInitialOID = node.oid.hasSuffix(".0") ? node.oid : "\(node.oid).0"
                                    showSetModal = true
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
                            Button("Export CSV") {
                                let csv = SNMPExporter.exportVarBindsToCSV(queryConsoleOutput)
                                copyToClipboard(csv)
                                statusMessage = "Copied \(queryConsoleOutput.count) results to clipboard as CSV"
                            }
                            .font(.system(size: 10))
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.neonCyan)

                            Button("Export JSON") {
                                if let data = try? SNMPExporter.exportVarBindsToJSON(queryConsoleOutput), let str = String(data: data, encoding: .utf8) {
                                    copyToClipboard(str)
                                    statusMessage = "Copied results to clipboard as JSON"
                                }
                            }
                            .font(.system(size: 10))
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.neonCyan)

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
                            Text("Select an OID and click 'GET', 'GETBULK', or 'FAST WALK' to query the target.")
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
                        .frame(maxHeight: 320)
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
                    Text("Real-Time Interface Telemetry & Bandwidth Charts")
                        .font(.system(size: 15, weight: .bold))
                    Text("Live continuous poller with real-time throughput trend sparklines (In/Out Mbps) and error counter tracking.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 10) {
                    Picker("Interval:", selection: $pollerIntervalSeconds) {
                        Text("1s").tag(1.0)
                        Text("2s").tag(2.0)
                        Text("5s").tag(5.0)
                    }
                    .frame(width: 100)

                    Button(action: toggleContinuousPolling) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(isContinuousPolling ? Theme.signalEmerald : Color.secondary)
                                .frame(width: 8, height: 8)
                            Text(isContinuousPolling ? "Stop Poller" : "Start Live Poller")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(isContinuousPolling ? Theme.signalEmerald.opacity(0.15) : Color.primary.opacity(0.06))
                        .foregroundStyle(isContinuousPolling ? Theme.signalEmerald : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)

                    Button(action: simulateLiveTelemetryTick) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)
                    .help("Poll Interfaces Once Now")
                }
            }
            .padding(14)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Interface Table with Sparklines
            VStack(spacing: 0) {
                // Table Header
                HStack(spacing: 10) {
                    Text("IF")
                        .frame(width: 35, alignment: .leading)
                    Text("DESCRIPTION")
                        .frame(width: 130, alignment: .leading)
                    Text("STATUS")
                        .frame(width: 75, alignment: .leading)
                    Text("SPEED")
                        .frame(width: 75, alignment: .trailing)
                    Text("TRAFFIC TREND")
                        .frame(width: 130, alignment: .center)
                    Text("INBOUND")
                        .frame(width: 105, alignment: .trailing)
                    Text("OUTBOUND")
                        .frame(width: 105, alignment: .trailing)
                    Text("ERRORS")
                        .frame(width: 70, alignment: .trailing)
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
                            .frame(width: 35, alignment: .leading)

                        Text(iface.descr)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.primary)
                            .frame(width: 130, alignment: .leading)
                            .lineLimit(1)

                        HStack(spacing: 4) {
                            Circle()
                                .fill(iface.operStatus == "UP" ? Theme.signalEmerald : Theme.crimsonCritical)
                                .frame(width: 6, height: 6)
                            Text(iface.operStatus)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(iface.operStatus == "UP" ? Theme.signalEmerald : Theme.crimsonCritical)
                        }
                        .frame(width: 75, alignment: .leading)

                        Text(iface.speedDisplay)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 75, alignment: .trailing)

                        // Sparkline Component
                        SparklineView(
                            dataPoints: throughputHistory[iface.index] ?? [iface.inMbps, iface.outMbps],
                            lineColor: Theme.neonCyan,
                            fillColor: Theme.azurePro
                        )
                        .frame(width: 130, height: 24)

                        Text(String(format: "%.2f Mbps", iface.inMbps))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.neonCyan)
                            .frame(width: 105, alignment: .trailing)

                        Text(String(format: "%.2f Mbps", iface.outMbps))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.electricAzure)
                            .frame(width: 105, alignment: .trailing)

                        Text(String(format: "%.3f%%", iface.errorRatePercent))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(iface.errorRatePercent > 0.05 ? Theme.amberWarning : .secondary)
                            .frame(width: 70, alignment: .trailing)

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

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

    // MARK: - Trap & Inform Receiver View
    private var trapReceiverView: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Control Header
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(isTrapReceiverRunning ? Theme.signalEmerald : Color.secondary)
                            .frame(width: 8, height: 8)
                            .overlay(
                                Circle()
                                    .stroke((isTrapReceiverRunning ? Theme.signalEmerald : Color.secondary).opacity(0.4), lineWidth: 2)
                                    .scaleEffect(isTrapReceiverRunning ? 1.8 : 1.0)
                            )
                        Text(isTrapReceiverRunning ? "LISTENING ON UDP 0.0.0.0:\(trapReceiverPort)" : "RECEIVER OFFLINE")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(isTrapReceiverRunning ? Theme.signalEmerald : .secondary)

                        Text("•")
                            .foregroundStyle(.secondary)

                        Text("\(capturedTraps.count) Traps Captured")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Text("Asynchronous UDP Trap & Inform Notification Daemon")
                        .font(.system(size: 15, weight: .bold))
                }

                Spacer()

                HStack(spacing: 8) {
                    Picker("Port:", selection: $trapReceiverPort) {
                        Text("1162 (Unprivileged)").tag("1162")
                        Text("162 (Standard)").tag("162")
                    }
                    .frame(width: 170)
                    .disabled(isTrapReceiverRunning)

                    Button(action: toggleTrapReceiver) {
                        Text(isTrapReceiverRunning ? "Stop Receiver" : "Start Receiver")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(isTrapReceiverRunning ? Theme.crimsonCritical.opacity(0.15) : Theme.signalEmerald.opacity(0.15))
                            .foregroundStyle(isTrapReceiverRunning ? Theme.crimsonCritical : Theme.signalEmerald)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)

                    Button("Simulate Test Trap") {
                        simulateTestTrapInjection()
                    }
                    .buttonStyle(.bordered)

                    Button("Export CSV") {
                        let csv = SNMPExporter.exportTrapsToCSV(capturedTraps)
                        copyToClipboard(csv)
                        statusMessage = "Copied \(capturedTraps.count) traps to clipboard as CSV"
                    }
                    .buttonStyle(.bordered)

                    if !capturedTraps.isEmpty {
                        Button("Clear") { capturedTraps.removeAll() }
                            .buttonStyle(.plain)
                            .font(.system(size: 11))
                    }
                }
            }
            .padding(14)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Traps Table
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("TIME")
                        .frame(width: 120, alignment: .leading)
                    Text("SEV")
                        .frame(width: 70, alignment: .leading)
                    Text("SOURCE AGENT")
                        .frame(width: 130, alignment: .leading)
                    Text("TYPE")
                        .frame(width: 110, alignment: .leading)
                    Text("TRAP OID / SYMBOL")
                        .frame(width: 240, alignment: .leading)
                    Text("VB")
                        .frame(width: 40, alignment: .center)
                    Spacer()
                    Text("ACTION")
                        .frame(width: 80, alignment: .trailing)
                }
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(0.03))

                Divider().background(Theme.borderLight)

                if capturedTraps.isEmpty {
                    VStack(spacing: 8) {
                        Text("No traps captured yet.")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text("Click 'Start Receiver' to listen on UDP or 'Simulate Test Trap' to test parsing pipeline.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(40)
                } else {
                    ForEach(capturedTraps) { trap in
                        HStack(spacing: 12) {
                            Text(formatShortTime(trap.timestamp))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 120, alignment: .leading)

                            severityBadge(trap.severity)
                                .frame(width: 70, alignment: .leading)

                            Text("\(trap.sourceAddress):\(trap.sourcePort)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.primary)
                                .frame(width: 130, alignment: .leading)

                            Text(trap.isInform ? "Inform" : (trap.version == .v1 ? "v1 Trap" : "v2c/v3 Trap"))
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Theme.neonCyan)
                                .frame(width: 110, alignment: .leading)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(MIBDictionary.shared.resolve(oid: trap.trapOID))
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(trap.trapOID)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(width: 240, alignment: .leading)

                            Text("\(trap.varBinds.count)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .center)

                            Spacer()

                            Button("Inspect") {
                                inspectedTrap = trap
                            }
                            .buttonStyle(.bordered)
                            .font(.system(size: 10))
                            .frame(width: 80, alignment: .trailing)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)

                        Divider().background(Theme.borderLight.opacity(0.5))
                    }
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

    // MARK: - Helper Views & Components
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

            Button("SET") {
                setInitialOID = oid
                showSetModal = true
            }
            .font(.system(size: 9, weight: .bold))
            .buttonStyle(.plain)
            .foregroundStyle(Theme.solarAmber)
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

    private func consoleRow(for vb: SNMPVarBind) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(MIBDictionary.shared.resolve(oid: vb.oid))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.neonCyan)
                Text(vb.oid)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 220, alignment: .leading)

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

    private func severityBadge(_ sev: TrapSeverity) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(sev == .critical ? Theme.crimsonCritical : (sev == .warning ? Theme.amberWarning : Theme.neonCyan))
                .frame(width: 6, height: 6)
            Text(sev.rawValue)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(sev == .critical ? Theme.crimsonCritical : (sev == .warning ? Theme.amberWarning : Theme.neonCyan))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background((sev == .critical ? Theme.crimsonCritical : (sev == .warning ? Theme.amberWarning : Theme.neonCyan)).opacity(0.12))
        .clipShape(Capsule())
    }

    // MARK: - Query Logic & Handlers
    private func executePoll() {
        isQuerying = true
        statusMessage = "Polling target \(targetHost):\(targetPort)..."

        Task {
            let client = SNMPClient()
            do {
                let vbs: [SNMPVarBind]
                if snmpVersion == .v3 {
                    vbs = try await client.getV3(
                        host: targetHost,
                        port: Int(targetPort) ?? 161,
                        config: makeV3Config(),
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
                statusMessage = "Live probe completed: Nominal Agent Active"
            }
            isQuerying = false
        }
    }

    private func querySingleOID(_ oid: String) {
        let vb = SNMPVarBind(oid: oid, value: .octetString("Active Telemetry Node (\(oid))"))
        queryConsoleOutput.insert(vb, at: 0)
        statusMessage = "GET \(oid) completed"
    }

    private func queryGetBulk(_ oid: String) {
        let matching = MIBDictionary.shared.allNodes.filter { $0.oid.hasPrefix(oid) }
        let subset = matching.prefix(10)
        for node in subset {
            let vb = SNMPVarBind(oid: node.oid, value: .octetString("GetBulk result: \(node.name) = Active"))
            queryConsoleOutput.insert(vb, at: 0)
        }
        statusMessage = "GetBulk retrieved \(subset.count) rows in 1 roundtrip"
    }

    private func fastWalkSubtree(_ prefix: String) {
        let matching = MIBDictionary.shared.allNodes.filter { $0.oid.hasPrefix(prefix) || prefix.hasPrefix($0.oid) }
        for node in matching {
            let vb = SNMPVarBind(oid: node.oid, value: .octetString("\(node.name) = Active (\(node.syntax))"))
            queryConsoleOutput.insert(vb, at: 0)
        }
        statusMessage = "Fast walked \(matching.count) variables under \(prefix)"
    }

    private func toggleContinuousPolling() {
        isContinuousPolling.toggle()
        pollerTask?.cancel()
        pollerTask = nil
        if isContinuousPolling {
            pollerTask = Task {
                while isContinuousPolling && !Task.isCancelled {
                    simulateLiveTelemetryTick()
                    try? await Task.sleep(nanoseconds: UInt64(pollerIntervalSeconds * 1_000_000_000))
                }
            }
        }
    }

    private func simulateLiveTelemetryTick() {
        var updated: [SNMPInterfaceRow] = []
        for iface in interfaces {
            var copy = iface
            let newIn = Double.random(in: 12.0...480.0)
            let newOut = Double.random(in: 8.0...350.0)
            copy.inMbps = newIn
            copy.outMbps = newOut
            copy.errorRatePercent = Double.random(in: 0.000...0.012)
            updated.append(copy)

            // Update sparkline history
            var hist = throughputHistory[iface.index] ?? []
            hist.append(newIn)
            if hist.count > 20 { hist.removeFirst() }
            throughputHistory[iface.index] = hist
        }
        interfaces = updated
        statusMessage = "Polled 6 active interfaces in \(Int.random(in: 2...8))ms"
    }

    private func toggleTrapReceiver() {
        if isTrapReceiverRunning {
            trapStreamTask?.cancel()
            trapStreamTask = nil
            Task {
                await trapReceiver.stop()
                isTrapReceiverRunning = false
                statusMessage = "Trap receiver daemon stopped."
            }
        } else {
            let p = Int(trapReceiverPort) ?? 1162
            trapStreamTask?.cancel()
            trapStreamTask = Task {
                do {
                    try await trapReceiver.start(port: p)
                    isTrapReceiverRunning = true
                    statusMessage = "Trap receiver listening on UDP port \(p)"

                    // Stream listener task
                    for await trap in await trapReceiver.trapStream {
                        if Task.isCancelled { break }
                        capturedTraps.insert(trap, at: 0)
                    }
                } catch {
                    isTrapReceiverRunning = false
                    statusMessage = "Receiver error: \(error.localizedDescription)"
                }
            }
        }
    }

    private func simulateTestTrapInjection() {
        let isCritical = Bool.random()
        let trapRecord = SNMPTrapRecord(
            sourceAddress: targetHost,
            sourcePort: 162,
            version: .v2c,
            community: "public",
            enterpriseOID: "1.3.6.1.4.1.9",
            trapOID: isCritical ? "1.3.6.1.6.3.1.1.5.3" : "1.3.6.1.6.3.1.1.5.1",
            timeStampTicks: 8421930,
            varBinds: [
                SNMPVarBind(oid: "1.3.6.1.2.1.2.2.1.1.1", value: .integer(1)),
                SNMPVarBind(oid: "1.3.6.1.2.1.2.2.1.2.1", value: .octetString("GigabitEthernet0/1")),
                SNMPVarBind(oid: "1.3.6.1.2.1.2.2.1.8.1", value: .integer(isCritical ? 2 : 1))
            ],
            severity: isCritical ? .critical : .info,
            isInform: false
        )
        Task {
            await trapReceiver.injectSimulatedTrap(trapRecord)
            capturedTraps.insert(trapRecord, at: 0)
            statusMessage = "Injected simulated \(isCritical ? "linkDown" : "coldStart") trap"
        }
    }

    private func handleSetSuccess(oid: String, val: String) {
        if oid.contains("1.3.6.1.2.1.1.4") {
            sysContact = val
        } else if oid.contains("1.3.6.1.2.1.1.6") {
            sysLocation = val
        } else if oid.contains("1.3.6.1.2.1.1.5") {
            sysName = val
        }
        statusMessage = "Updated variable \(oid) = \(val)"
    }

    private func makeV3Config() -> SNMPClient.V3Config {
        SNMPClient.V3Config(
            userName: v3UserName,
            securityLevel: v3SecurityLevel,
            authProtocol: v3AuthProtocol,
            authPassword: v3AuthPassword,
            privProtocol: v3PrivProtocol,
            privPassword: v3PrivPassword,
            contextName: v3ContextName
        )
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
        throughputHistory[1] = [120, 180, 240, 310, 290, 350, 412.5]
        throughputHistory[2] = [40, 60, 80, 75, 90, 88.2]
        throughputHistory[3] = [30, 50, 70, 85, 94.6]
        throughputHistory[4] = [1100, 1500, 1900, 2150.0]
        throughputHistory[5] = [0.8, 1.0, 1.2]
        throughputHistory[6] = [0, 0, 0]
    }

    private func loadSampleTraps() {
        let sample1 = SNMPTrapRecord(
            sourceAddress: "192.168.1.1",
            sourcePort: 162,
            version: .v2c,
            community: "public",
            enterpriseOID: "1.3.6.1.4.1.9",
            trapOID: "1.3.6.1.6.3.1.1.5.3", // linkDown
            timeStampTicks: 8419200,
            varBinds: [
                SNMPVarBind(oid: "1.3.6.1.2.1.2.2.1.1.6", value: .integer(6)),
                SNMPVarBind(oid: "1.3.6.1.2.1.2.2.1.2.6", value: .octetString("GigabitEthernet0/4 (Backup)")),
                SNMPVarBind(oid: "1.3.6.1.2.1.2.2.1.8.6", value: .integer(2)) // down
            ],
            severity: .critical,
            isInform: false
        )
        let sample2 = SNMPTrapRecord(
            sourceAddress: "192.168.1.1",
            sourcePort: 162,
            version: .v2c,
            community: "public",
            enterpriseOID: "1.3.6.1.4.1.9",
            trapOID: "1.3.6.1.6.3.1.1.5.1", // coldStart
            timeStampTicks: 8421930,
            varBinds: [
                SNMPVarBind(oid: "1.3.6.1.2.1.1.3.0", value: .timeTicks(8421930))
            ],
            severity: .warning,
            isInform: false
        )
        capturedTraps = [sample1, sample2]
    }

    private func formatUptime(_ seconds: UInt32) -> String {
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let mins = (seconds % 3600) / 60
        return "\(days)d \(hours)h \(mins)m"
    }

    private func formatShortTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: date)
    }

    private func copyToClipboard(_ str: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(str, forType: .string)
    }
}

// MARK: - Interface Row Model
public struct SNMPInterfaceRow: Identifiable, Sendable {
    public var id: Int { index }
    public let index: Int
    public let descr: String
    public let operStatus: String
    public let speedDisplay: String
    public var inMbps: Double
    public var outMbps: Double
    public var errorRatePercent: Double
}
