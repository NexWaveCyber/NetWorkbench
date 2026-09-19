import SwiftUI
import AppKit
import NetworkCore
import PersistenceKit
import DeviceKit

/// Scope and site profile management for network engineers, backed by SQLite persistence
public struct EnvironmentsWorkspaceView: View {
    @Bindable var state: AppState

    // Live gateway telemetry
    @State private var gatewayLatencies: [String: Double] = [:]
    @State private var isProbing: [String: Bool] = [:]
    @State private var isProbingAll: Bool = false

    // Modals & Sheets
    @State private var isShowingAddSheet: Bool = false
    @State private var editingEnvironment: EnvironmentRecord? = nil
    @State private var inspectEnvironment: EnvironmentRecord? = nil

    // New / Edit Environment Form State
    @State private var formName: String = ""
    @State private var formType: EnvironmentType = .campus
    @State private var formGateway: String = ""
    @State private var formSubnet: String = ""
    @State private var formPrimaryDNS: String = "1.1.1.1"
    @State private var formSecondaryDNS: String = "8.8.8.8"
    @State private var formVlanRange: String = "10 - 100"
    @State private var formRunbookNotes: String = ""

    // SOP Checklists state per environment
    @State private var runbookChecklists: [String: Set<String>] = [:]

    // Search filter
    @State private var searchQuery: String = ""

    public init(state: AppState) {
        self.state = state
    }

    public var filteredEnvironments: [EnvironmentRecord] {
        let list = state.siteEnvironments
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return list }
        return list.filter {
            $0.name.lowercased().contains(q) ||
            $0.gatewayIP.lowercased().contains(q) ||
            $0.subnetCIDR.lowercased().contains(q) ||
            $0.environmentType.lowercased().contains(q) ||
            $0.runbookNotes.lowercased().contains(q)
        }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Bar
                headerBar

                // Active Environment Banner
                if let active = state.activeSiteEnvironment ?? state.siteEnvironments.first(where: { $0.isActive }) {
                    activeEnvironmentBanner(active)
                }

                // Search & Probe Toolbar
                toolbarControls

                // Registered Environments Grid
                Text("REGISTERED SITE ENVIRONMENTS (\(filteredEnvironments.count))")
                    .font(Theme.monoText(10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                if filteredEnvironments.isEmpty {
                    emptyStateCard
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        ForEach(filteredEnvironments) { env in
                            environmentCard(env)
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(Theme.secondaryBackground)
        .navigationTitle("Environments & Sites")
        .sheet(isPresented: $isShowingAddSheet) {
            environmentEditSheet(isNew: true)
        }
        .sheet(item: $editingEnvironment) { env in
            environmentEditSheet(isNew: false)
        }
        .sheet(item: $inspectEnvironment) { env in
            environmentDetailInspector(env)
        }
        .onAppear {
            state.refreshEnvironments()
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Theme.quantumViolet.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: "network")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.quantumViolet)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("INFRASTRUCTURE SCOPES")
                        .font(Theme.monoText(10, weight: .bold))
                        .foregroundStyle(Theme.quantumViolet)
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text("SQLITE WAL PERSISTENCE")
                        .font(Theme.monoText(10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text("IPAM ALLOCATION ENGINE")
                        .font(Theme.monoText(10, weight: .semibold))
                        .foregroundStyle(Theme.signalEmerald)
                }

                Text("Environments & Site Runbooks")
                    .font(.system(size: 20, weight: .bold))

                Text("Manage site scopes, IPAM subnets, live gateway health gauges, and standard operating procedures (SOPs).")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Export All JSON
            Button(action: exportAllSitesJSON) {
                Label("Export JSON", systemImage: "arrow.up.doc")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered)

            // Import JSON
            Button(action: importSitesJSON) {
                Label("Import JSON", systemImage: "arrow.down.doc")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered)

            // Add Environment Button
            Button(action: {
                openAddForm()
            }) {
                Label("Add Environment", systemImage: "plus")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.quantumViolet)
        }
        .engineeringCard(padding: 16)
    }

    // MARK: - Active Environment Banner

    private func activeEnvironmentBanner(_ env: EnvironmentRecord) -> some View {
        let matchingDevices = getMatchingDevices(for: env)
        let ipam = IPAMCalculator.calculate(cidr: env.subnetCIDR, allocatedDeviceCount: matchingDevices.count)
        let envType = EnvironmentType(rawValue: env.environmentType) ?? .campus

        return HStack(spacing: 14) {
            Circle()
                .fill(Theme.signalEmerald)
                .frame(width: 8, height: 8)
                .overlay(Circle().stroke(Theme.signalEmerald.opacity(0.4), lineWidth: 3).scaleEffect(1.6))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("CURRENT ACTIVE SCOPE")
                        .font(Theme.monoText(9, weight: .bold))
                        .foregroundStyle(Theme.signalEmerald)
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text(envType.displayName.uppercased())
                        .font(Theme.monoText(9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Text(env.name)
                    .font(.system(size: 15, weight: .bold))
            }

            Spacer()

            HStack(spacing: 16) {
                metricPill(label: "GATEWAY", val: env.gatewayIP)
                metricPill(label: "SUBNET", val: env.subnetCIDR)
                metricPill(label: "HOST CAPACITY", val: ipam != nil ? "\(ipam!.totalCapacity)" : "N/A")
                metricPill(label: "ALLOCATED FLEET", val: "\(matchingDevices.count) Devices")

                if let lat = gatewayLatencies[env.id] {
                    metricPill(label: "GW LATENCY", val: String(format: "%.1f ms", lat), color: Theme.signalEmerald)
                }

                Button(action: {
                    probeEnvironmentGateway(env)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: isProbing[env.id] == true ? "arrow.triangle.2.circlepath" : "bolt.horizontal.circle.fill")
                        Text(isProbing[env.id] == true ? "Probing..." : "Probe RTT")
                    }
                    .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(Theme.signalEmerald)
            }
        }
        .padding(14)
        .background(Theme.signalEmerald.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.signalEmerald.opacity(0.3), lineWidth: 1))
    }

    private func metricPill(label: String, val: String, color: Color = Color.white) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(Theme.monoText(8, weight: .bold))
                .foregroundStyle(.secondary)
            Text(val)
                .font(Theme.monoText(11, weight: .bold))
                .foregroundStyle(color)
        }
    }

    // MARK: - Toolbar Controls

    private var toolbarControls: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search sites by name, subnet CIDR, gateway IP, or notes...", text: $searchQuery)
                    .textFieldStyle(.plain)
                if !searchQuery.isEmpty {
                    Button(action: { searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Spacer()

            Button(action: probeAllEnvironments) {
                HStack(spacing: 6) {
                    Image(systemName: isProbingAll ? "arrow.triangle.2.circlepath" : "antenna.radiowaves.left.and.right")
                    Text(isProbingAll ? "Probing All Sites..." : "Probe All Gateways")
                }
                .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .disabled(isProbingAll)
        }
    }

    // MARK: - Empty State Card

    private var emptyStateCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "network")
                .font(.system(size: 40))
                .foregroundStyle(Theme.quantumViolet.opacity(0.4))
            Text("No Matching Environments")
                .font(.system(size: 15, weight: .bold))
            Text("Add new site environments or adjust your search filter.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button("Add First Environment") {
                openAddForm()
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.quantumViolet)
        }
        .engineeringCard(padding: 40)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Environment Card

    private func environmentCard(_ env: EnvironmentRecord) -> some View {
        let envType = EnvironmentType(rawValue: env.environmentType) ?? .campus
        let matchingDevices = getMatchingDevices(for: env)
        let ipam = IPAMCalculator.calculate(cidr: env.subnetCIDR, allocatedDeviceCount: matchingDevices.count)

        return VStack(alignment: .leading, spacing: 12) {
            // Card Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: envType.iconName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(hex: envType.accentColorHex))

                    Text(env.name)
                        .font(.system(size: 14, weight: .bold))
                }

                Spacer()

                if env.isActive {
                    HUDStatusBadge(title: "ACTIVE SCOPE", color: Theme.signalEmerald)
                } else {
                    Button("Activate") {
                        state.activateEnvironment(id: env.id)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Menu {
                    Button("Inspect IPAM & Fleet Details") {
                        inspectEnvironment = env
                    }
                    Button("Edit Environment") {
                        openEditForm(env)
                    }
                    Button("Probe Gateway RTT") {
                        probeEnvironmentGateway(env)
                    }
                    Divider()
                    Button("Delete Environment", role: .destructive) {
                        state.deleteEnvironment(id: env.id)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
            }

            Divider().overlay(Theme.borderLight)

            // Properties Grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                propertyRow(label: "Gateway IP", value: env.gatewayIP)
                propertyRow(label: "Subnet CIDR", value: env.subnetCIDR)
                propertyRow(label: "Primary DNS", value: env.primaryDNS)
                propertyRow(label: "VLAN Scope", value: env.vlanRange)
            }

            // IPAM Telemetry Gauge Bar
            if let calc = ipam {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("IPAM ADDRESS UTILIZATION")
                            .font(Theme.monoText(8, weight: .bold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(calc.allocatedCount) / \(calc.totalCapacity) IPs (\(String(format: "%.1f", calc.utilizationPercentage))%)")
                            .font(Theme.monoText(9, weight: .bold))
                            .foregroundStyle(utilizationColor(calc.utilizationPercentage))
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.secondary.opacity(0.15))
                                .frame(height: 6)

                            RoundedRectangle(cornerRadius: 3)
                                .fill(utilizationColor(calc.utilizationPercentage))
                                .frame(width: max(4, geo.size.width * CGFloat(min(1.0, calc.utilizationPercentage / 100.0))), height: 6)
                        }
                    }
                    .frame(height: 6)
                }
                .padding(8)
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Live Latency Gauge Badge (if probed)
            HStack(spacing: 8) {
                if let lat = gatewayLatencies[env.id] {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Theme.signalEmerald)
                            .frame(width: 6, height: 6)
                        Text(String(format: "Live Gateway: %.1f ms RTT", lat))
                            .font(Theme.monoText(10, weight: .bold))
                            .foregroundStyle(Theme.signalEmerald)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.signalEmerald.opacity(0.12))
                    .clipShape(Capsule())
                } else if isProbing[env.id] == true {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("Probing Gateway...")
                            .font(Theme.monoText(10))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button(action: { probeEnvironmentGateway(env) }) {
                    Label("Probe RTT", systemImage: "bolt.horizontal.circle")
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderless)
            }

            // Runbook Notes Preview
            if !env.runbookNotes.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("SITE RUNBOOK NOTES")
                        .font(Theme.monoText(8, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text(env.runbookNotes)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            // Standard SOP Checklist for Active Scope
            if env.isActive {
                sopMaintenanceChecklist(env)
            }

            // Quick Actions & Fleet Counter
            HStack(spacing: 8) {
                Button(action: {
                    state.targetInput = env.gatewayIP
                    state.selectedWorkspace = .diagnose
                }) {
                    Label("Diagnose", systemImage: "stethoscope")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(action: {
                    state.terminalManager.openSSHSession(host: env.gatewayIP)
                    state.selectedWorkspace = .terminal
                }) {
                    Label("Console", systemImage: "terminal.fill")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(action: {
                    inspectEnvironment = env
                }) {
                    Label("Details", systemImage: "info.circle")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Text("\(matchingDevices.count) Devices")
                    .font(Theme.monoText(10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .engineeringCard(padding: 16)
    }

    private func propertyRow(label: String, value: String) -> some View {
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

    // MARK: - SOP Maintenance Checklist

    private func sopMaintenanceChecklist(_ env: EnvironmentRecord) -> some View {
        let defaultSOPs = [
            "Pre-Maintenance: Verify Dual Power Supplies & Fans",
            "Pre-Maintenance: Check BGP Session States & Route Flaps",
            "Execution: Backup Running Config to Local Flash",
            "Post-Verification: Verify Optical Transceiver DOM Levels"
        ]

        let checkedSet = runbookChecklists[env.id] ?? []

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("STANDARD OPERATING PROCEDURES (SOP)")
                    .font(Theme.monoText(8, weight: .bold))
                    .foregroundStyle(Theme.quantumViolet)
                Spacer()
                Text("\(checkedSet.count) of \(defaultSOPs.count) verified")
                    .font(Theme.monoText(8))
                    .foregroundStyle(.secondary)
            }

            ForEach(defaultSOPs, id: \.self) { sop in
                Button(action: {
                    toggleSOP(envId: env.id, sop: sop)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: checkedSet.contains(sop) ? "checkmark.square.fill" : "square")
                            .font(.system(size: 11))
                            .foregroundStyle(checkedSet.contains(sop) ? Theme.signalEmerald : .secondary)

                        Text(sop)
                            .font(.system(size: 11))
                            .foregroundStyle(checkedSet.contains(sop) ? .secondary : .primary)
                            .strikethrough(checkedSet.contains(sop))
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Theme.quantumViolet.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func toggleSOP(envId: String, sop: String) {
        var current = runbookChecklists[envId] ?? []
        if current.contains(sop) {
            current.remove(sop)
        } else {
            current.insert(sop)
        }
        runbookChecklists[envId] = current
    }

    // MARK: - Environment Detail Inspector

    private func environmentDetailInspector(_ env: EnvironmentRecord) -> some View {
        let matchingDevices = getMatchingDevices(for: env)
        let ipam = IPAMCalculator.calculate(cidr: env.subnetCIDR, allocatedDeviceCount: matchingDevices.count)
        let envType = EnvironmentType(rawValue: env.environmentType) ?? .campus

        return VStack(spacing: 16) {
            // Inspector Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: envType.iconName)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color(hex: envType.accentColorHex))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(env.name)
                            .font(.system(size: 16, weight: .bold))
                        Text("\(envType.displayName) • Subnet \(env.subnetCIDR)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button("Close") { inspectEnvironment = nil }
                    .buttonStyle(.plain)
            }

            Divider().overlay(Theme.borderLight)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Full IPAM Breakdown Card
                    if let calc = ipam {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("IPAM SUBNET ALLOCATION MATRIX")
                                .font(Theme.monoText(10, weight: .bold))
                                .foregroundStyle(Theme.cyanPulse)

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                propertyRow(label: "Network Address", value: calc.networkAddress)
                                propertyRow(label: "Broadcast Address", value: calc.broadcastAddress)
                                propertyRow(label: "Subnet Netmask", value: calc.netmask)
                                propertyRow(label: "Wildcard Mask", value: calc.wildcardMask)
                                propertyRow(label: "First Usable Host", value: calc.firstUsableHost)
                                propertyRow(label: "Last Usable Host", value: calc.lastUsableHost)
                                propertyRow(label: "Total Usable Capacity", value: "\(calc.totalCapacity) hosts")
                                propertyRow(label: "Allocated Devices", value: "\(calc.allocatedCount) devices")
                            }
                        }
                        .engineeringCard(padding: 14)
                    }

                    // Associated Devices Table
                    VStack(alignment: .leading, spacing: 8) {
                        Text("DEVICES ASSIGNED TO THIS SITE (\(matchingDevices.count))")
                            .font(Theme.monoText(10, weight: .bold))
                            .foregroundStyle(.secondary)

                        if matchingDevices.isEmpty {
                            Text("No devices in your inventory currently map to \(env.subnetCIDR).")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .padding(12)
                        } else {
                            VStack(spacing: 6) {
                                ForEach(matchingDevices) { dev in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(dev.name)
                                                .font(.system(size: 12, weight: .bold))
                                            Text(dev.hostname)
                                                .font(Theme.monoText(10))
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        Text(dev.managementIP)
                                            .font(Theme.monoText(11, weight: .semibold))
                                            .foregroundStyle(.primary)

                                        Text(dev.role.rawValue)
                                            .font(Theme.monoText(9, weight: .bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.secondary.opacity(0.15))
                                            .clipShape(Capsule())

                                        Button("Console") {
                                            state.terminalManager.openSSHSession(host: dev.managementIP)
                                            state.selectedWorkspace = .terminal
                                            inspectEnvironment = nil
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }
                                    .padding(8)
                                    .background(Theme.cardBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                            }
                        }
                    }
                    .engineeringCard(padding: 14)

                    // Runbook Notes Full Text
                    if !env.runbookNotes.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("FULL ENGINEERING RUNBOOK & SITE CONTACTS")
                                .font(Theme.monoText(10, weight: .bold))
                                .foregroundStyle(.secondary)

                            Text(env.runbookNotes)
                                .font(.system(size: 12))
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .engineeringCard(padding: 14)
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 620, height: 560)
        .background(Theme.secondaryBackground)
    }

    // MARK: - Edit / Add Environment Sheet

    private func environmentEditSheet(isNew: Bool) -> some View {
        VStack(spacing: 18) {
            HStack {
                Label(isNew ? "Add Site Environment" : "Edit Site Environment", systemImage: "network")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Button("Cancel") {
                    isShowingAddSheet = false
                    editingEnvironment = nil
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ENVIRONMENT NAME")
                            .font(Theme.monoText(10, weight: .bold))
                            .foregroundStyle(.secondary)
                        TextField("e.g. Austin Regional Branch", text: $formName)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("ENVIRONMENT TYPE")
                            .font(Theme.monoText(10, weight: .bold))
                            .foregroundStyle(.secondary)
                        Picker("", selection: $formType) {
                            ForEach(EnvironmentType.allCases) { t in
                                Text(t.displayName).tag(t)
                            }
                        }
                    }
                    .frame(width: 170)
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("GATEWAY IP")
                            .font(Theme.monoText(10, weight: .bold))
                            .foregroundStyle(.secondary)
                        TextField("192.168.1.1", text: $formGateway)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("SUBNET CIDR")
                            .font(Theme.monoText(10, weight: .bold))
                            .foregroundStyle(.secondary)
                        TextField("192.168.1.0/24", text: $formSubnet)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("PRIMARY DNS")
                            .font(Theme.monoText(10, weight: .bold))
                            .foregroundStyle(.secondary)
                        TextField("1.1.1.1", text: $formPrimaryDNS)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("SECONDARY DNS")
                            .font(Theme.monoText(10, weight: .bold))
                            .foregroundStyle(.secondary)
                        TextField("8.8.8.8", text: $formSecondaryDNS)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("VLAN RANGE")
                            .font(Theme.monoText(10, weight: .bold))
                            .foregroundStyle(.secondary)
                        TextField("10 - 100", text: $formVlanRange)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("ENGINEERING RUNBOOK & NOTES")
                        .font(Theme.monoText(10, weight: .bold))
                        .foregroundStyle(.secondary)
                    TextEditor(text: $formRunbookNotes)
                        .frame(height: 80)
                        .padding(4)
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.borderLight, lineWidth: 1))
                }
            }
            .padding(14)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Button(action: saveEnvironmentForm) {
                Text(isNew ? "Create Environment Profile" : "Save Changes")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.quantumViolet)
            .disabled(formName.isEmpty || formGateway.isEmpty || formSubnet.isEmpty)
        }
        .padding(24)
        .frame(width: 520)
        .background(Theme.secondaryBackground)
    }

    // MARK: - Actions & Telemetry

    private func openAddForm() {
        formName = ""
        formType = .campus
        formGateway = "192.168.1.1"
        formSubnet = "192.168.1.0/24"
        formPrimaryDNS = "1.1.1.1"
        formSecondaryDNS = "8.8.8.8"
        formVlanRange = "10 - 100"
        formRunbookNotes = ""
        isShowingAddSheet = true
    }

    private func openEditForm(_ env: EnvironmentRecord) {
        formName = env.name
        formType = EnvironmentType(rawValue: env.environmentType) ?? .campus
        formGateway = env.gatewayIP
        formSubnet = env.subnetCIDR
        formPrimaryDNS = env.primaryDNS
        formSecondaryDNS = env.secondaryDNS ?? "8.8.8.8"
        formVlanRange = env.vlanRange
        formRunbookNotes = env.runbookNotes
        editingEnvironment = env
    }

    private func saveEnvironmentForm() {
        let id = editingEnvironment?.id ?? UUID().uuidString
        let isAct = editingEnvironment?.isActive ?? (state.siteEnvironments.isEmpty)
        let record = EnvironmentRecord(
            id: id,
            name: formName,
            environmentType: formType.rawValue,
            gatewayIP: formGateway,
            subnetCIDR: formSubnet,
            primaryDNS: formPrimaryDNS,
            secondaryDNS: formSecondaryDNS.isEmpty ? nil : formSecondaryDNS,
            vlanRange: formVlanRange,
            runbookNotes: formRunbookNotes,
            isActive: isAct,
            updatedAt: Date().timeIntervalSince1970
        )
        state.saveEnvironment(record)
        isShowingAddSheet = false
        editingEnvironment = nil
    }

    private func probeEnvironmentGateway(_ env: EnvironmentRecord) {
        isProbing[env.id] = true
        Task {
            let latency = await MenuBarMonitorEngine.shared.pingHost(host: env.gatewayIP, timeoutMs: 800)
            await MainActor.run {
                if let lat = latency {
                    gatewayLatencies[env.id] = lat
                }
                isProbing[env.id] = false
            }
        }
    }

    private func probeAllEnvironments() {
        isProbingAll = true
        Task {
            for env in state.siteEnvironments {
                await MainActor.run { isProbing[env.id] = true }
                let latency = await MenuBarMonitorEngine.shared.pingHost(host: env.gatewayIP, timeoutMs: 800)
                await MainActor.run {
                    if let lat = latency {
                        gatewayLatencies[env.id] = lat
                    }
                    isProbing[env.id] = false
                }
            }
            await MainActor.run {
                isProbingAll = false
                state.toastMessage = "Probed all site gateways successfully."
            }
        }
    }

    private func getMatchingDevices(for env: EnvironmentRecord) -> [NetworkDevice] {
        guard let net = IPNetwork(env.subnetCIDR) else {
            return state.managedDevices.filter { $0.environmentId == env.id }
        }
        return state.managedDevices.filter { dev in
            if dev.environmentId == env.id { return true }
            if let ip = IPAddress(dev.managementIP) {
                return net.contains(ip)
            }
            return false
        }
    }

    private func utilizationColor(_ pct: Double) -> Color {
        if pct >= 90.0 {
            return Color.red
        } else if pct >= 75.0 {
            return Theme.solarAmber
        } else {
            return Theme.signalEmerald
        }
    }

    // MARK: - Export & Import JSON

    private func exportAllSitesJSON() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(state.siteEnvironments),
              let jsonStr = String(data: data, encoding: .utf8) else { return }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "NexWave_Site_Environments.json"
        panel.begin { resp in
            if resp == .OK, let url = panel.url {
                try? jsonStr.write(to: url, atomically: true, encoding: .utf8)
                state.toastMessage = "Exported site profiles to \(url.lastPathComponent)"
            }
        }
    }

    private func importSitesJSON() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.begin { resp in
            if resp == .OK, let url = panel.url,
               let data = try? Data(contentsOf: url),
               let records = try? JSONDecoder().decode([EnvironmentRecord].self, from: data) {
                for rec in records {
                    state.saveEnvironment(rec)
                }
                state.toastMessage = "Imported \(records.count) site environments."
            }
        }
    }
}

