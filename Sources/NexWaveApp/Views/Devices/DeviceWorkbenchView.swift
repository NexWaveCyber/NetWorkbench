import SwiftUI
import DeviceKit
import NetworkCore
import TerminalKit

public struct DeviceWorkbenchView: View {
    @Bindable var state: AppState
    @State private var selectedTab: DeviceTab = .managed
    @State private var searchText: String = ""
    @State private var selectedRoleFilter: DeviceRoleFilter = .all
    @State private var isShowingAddSheet: Bool = false
    @State private var neighborToEnrol: DiscoveredNeighbor? = nil
    @State private var selectedDeviceForBaseline: NetworkDevice? = nil

    public enum DeviceTab: String, CaseIterable, Identifiable {
        case managed = "Managed Fleet"
        case discovered = "Discovered LAN Neighbors"
        case topology = "Topology Canvas"
        public var id: String { rawValue }
    }

    public enum DeviceRoleFilter: String, CaseIterable, Identifiable {
        case all = "All Roles"
        case router = "Routers"
        case switchDevice = "Switches"
        case firewall = "Firewalls"
        case accessPoint = "Access Points"
        case server = "Servers"
        case gateway = "Gateways"
        case host = "Hosts"

        public var id: String { rawValue }

        public func matches(_ role: DeviceRole) -> Bool {
            switch self {
            case .all: return true
            case .router: return role == .router
            case .switchDevice: return role == .switchDevice
            case .firewall: return role == .firewall
            case .accessPoint: return role == .accessPoint
            case .server: return role == .server
            case .gateway: return role == .gateway
            case .host: return role == .host || role == .workstation || role == .other
            }
        }
    }

    public init(state: AppState) {
        self.state = state
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Deck
                headerBar

                // KPI Metric Cards
                kpiMetricDeck

                // Tab Switcher and Filter Toolbar
                HStack(spacing: 16) {
                    Picker("", selection: $selectedTab) {
                        Text("Managed Fleet (\(state.managedDevices.count))").tag(DeviceTab.managed)
                        Text("Discovered LAN (\(state.discoveredNeighbors.count))").tag(DeviceTab.discovered)
                        Text("Topology Canvas").tag(DeviceTab.topology)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 520)

                    Spacer()

                    if selectedTab == .managed {
                        // Role Filter
                        Picker("Role", selection: $selectedRoleFilter) {
                            ForEach(DeviceRoleFilter.allCases) { filter in
                                Text(filter.rawValue).tag(filter)
                            }
                        }
                        .frame(width: 140)

                        // Search
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            TextField("Search devices, IPs, MACs...", text: $searchText)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12))
                            if !searchText.isEmpty {
                                Button(action: { searchText = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Theme.borderLight, lineWidth: 1)
                        )
                        .frame(maxWidth: 240)
                    }
                }

                // Main Content
                switch selectedTab {
                case .managed:
                    managedFleetSection
                case .discovered:
                    discoveredNeighborsSection
                case .topology:
                    TopologyCanvasView(state: state)
                        .frame(minHeight: 700)
                }
            }
            .padding(24)
        }
        .background(Theme.secondaryBackground)
        .navigationTitle("Device Workbench")
        .task {
            state.refreshManagedDevices()
            if state.discoveredNeighbors.isEmpty {
                await state.runLocalDiscovery()
            }
        }
        .sheet(isPresented: $isShowingAddSheet) {
            AddDeviceSheet(state: state, isPresented: $isShowingAddSheet)
        }
        .sheet(item: $neighborToEnrol) { neighbor in
            EnrolNeighborSheet(state: state, neighbor: neighbor, isPresented: Binding(
                get: { neighborToEnrol != nil },
                set: { if !$0 { neighborToEnrol = nil } }
            ))
        }
        .sheet(item: $selectedDeviceForBaseline) { device in
            DeviceBaselineSheet(state: state, device: device, isPresented: Binding(
                get: { selectedDeviceForBaseline != nil },
                set: { if !$0 { selectedDeviceForBaseline = nil } }
            ))
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

                    Text("INFRASTRUCTURE FLEET ENGINE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.neonCyan)

                    Text("•")
                        .foregroundStyle(.secondary)

                    Text("ZERO-ROOT LOCAL DISCOVERY & MIB PROFILES")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Text("Device Workbench")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.primary)

                Text("Manage enterprise switches, routers, and firewalls with baseline telemetry and kernel neighbor resolution.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 12) {
                Button(action: {
                    Task {
                        await state.runLocalDiscovery()
                    }
                }) {
                    HStack(spacing: 6) {
                        if state.isDiscoveringNeighbors {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        Text(state.isDiscoveringNeighbors ? "Scanning..." : "Scan LAN")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Theme.borderLight, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(state.isDiscoveringNeighbors)

                Button(action: { isShowingAddSheet = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text("Enrol Device")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Theme.cyanGlowGradient)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: Theme.neonCyan.opacity(0.3), radius: 6, y: 2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.borderLight, lineWidth: 1)
        )
    }

    // MARK: - KPI Metric Cards
    private var kpiMetricDeck: some View {
        HStack(spacing: 14) {
            kpiCard(
                title: "MANAGED FLEET",
                value: "\(state.managedDevices.count)",
                subtitle: "Enrolled Devices",
                icon: "server.rack",
                accentColor: Theme.electricAzure
            )

            let onlineCount = state.managedDevices.filter { $0.status == .online }.count
            kpiCard(
                title: "ONLINE & ACTIVE",
                value: "\(onlineCount)",
                subtitle: "\(state.managedDevices.isEmpty ? 0 : Int(Double(onlineCount) / Double(state.managedDevices.count) * 100))% Availability",
                icon: "checkmark.circle.fill",
                accentColor: Theme.signalEmerald
            )

            let attentionCount = state.managedDevices.filter { $0.status == .warning || $0.status == .offline }.count
            kpiCard(
                title: "ATTENTION NEEDED",
                value: "\(attentionCount)",
                subtitle: attentionCount == 0 ? "Fleet Nominal" : "Warning or Offline",
                icon: "exclamationmark.triangle.fill",
                accentColor: attentionCount > 0 ? Theme.amberWarning : Theme.signalEmerald
            )

            kpiCard(
                title: "LAN NEIGHBORS",
                value: "\(state.discoveredNeighbors.count)",
                subtitle: state.lastNeighborDiscoveryTime != nil ? "Last scan \(state.lastNeighborDiscoveryTime!.formatted(date: .omitted, time: .shortened))" : "Ready to scan",
                icon: "antenna.radiowaves.left.and.right",
                accentColor: Theme.neonCyan
            )
        }
    }

    private func kpiCard(title: String, value: String, subtitle: String, icon: String, accentColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(accentColor)
            }

            Text(value)
                .font(.system(size: 26, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
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

    // MARK: - Managed Fleet Section
    private var filteredDevices: [NetworkDevice] {
        state.managedDevices.filter { dev in
            let matchesSearch = searchText.isEmpty ||
                dev.name.localizedCaseInsensitiveContains(searchText) ||
                dev.ipAddress.localizedCaseInsensitiveContains(searchText) ||
                (dev.macAddress?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                dev.vendor.rawValue.localizedCaseInsensitiveContains(searchText)
            let matchesRole = selectedRoleFilter.matches(dev.role)
            return matchesSearch && matchesRole
        }
    }

    @ViewBuilder
    private var managedFleetSection: some View {
        if state.managedDevices.isEmpty {
            emptyFleetView
        } else if filteredDevices.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text("No devices match your search or filter")
                    .font(.system(size: 15, weight: .medium))
                Button("Clear Filters") {
                    searchText = ""
                    selectedRoleFilter = .all
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            .padding(60)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 380, maximum: 520), spacing: 16)], spacing: 16) {
                ForEach(filteredDevices) { device in
                    deviceCard(device)
                }
            }
        }
    }

    private func deviceCard(_ device: NetworkDevice) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Top Row: Role, Name, Status Badge
            HStack(alignment: .top) {
                HStack(spacing: 10) {
                    Image(systemName: device.role.iconName)
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.neonCyan)
                        .frame(width: 36, height: 36)
                        .background(Theme.neonCyan.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.name)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.primary)

                        HStack(spacing: 6) {
                            Text(device.role.rawValue)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.secondary)

                            Text("•")
                                .foregroundStyle(.secondary)

                            Text(device.vendor.rawValue)
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Color.primary.opacity(0.06))
                                .clipShape(Capsule())
                        }
                    }
                }

                Spacer()

                // Status Pill
                HStack(spacing: 5) {
                    Circle()
                        .fill(device.status.color)
                        .frame(width: 6, height: 6)
                    Text(device.status.rawValue)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(device.status.color)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(device.status.color.opacity(0.12))
                .clipShape(Capsule())
            }

            Divider()
                .background(Theme.borderLight)

            // IP, MAC & Location Metadata
            VStack(spacing: 6) {
                HStack {
                    Text("IP ADDRESS")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(device.ipAddress)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                }

                if let mac = device.macAddress {
                    HStack {
                        Text("MAC ADDRESS")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(mac)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                if let loc = device.location {
                    HStack {
                        Text("LOCATION")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(loc)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                if let snmp = device.snmpConfig {
                    HStack {
                        Text("SNMP TARGET")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(snmp.version.description) :\(snmp.port)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.neonCyan)
                    }
                }
            }

            // Tags
            if !device.tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(device.tags, id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }

            Divider()
                .background(Theme.borderLight)

            // Action Buttons
            HStack(spacing: 8) {
                Button(action: {
                    state.targetInput = device.ipAddress
                    state.updateTargetClassification(device.ipAddress)
                    state.selectedWorkspace = .diagnose
                    if let target = state.classifiedTarget {
                        Task {
                            await state.runDiagnosis(target: target)
                        }
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "stethoscope")
                            .font(.system(size: 11))
                        Text("Diagnose")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.electricAzure.opacity(0.12))
                    .foregroundStyle(Theme.electricAzure)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                Button(action: {
                    state.selectedWorkspace = .snmp
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 11))
                        Text("SNMP")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.neonCyan.opacity(0.12))
                    .foregroundStyle(Theme.neonCyan)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                Button(action: {
                    selectedDeviceForBaseline = device
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 11))
                        Text("Baseline")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                Button(action: {
                    state.terminalManager.openSSHSession(host: device.ipAddress)
                    state.selectedWorkspace = .terminal
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "terminal.fill")
                            .font(.system(size: 11))
                        Text("Terminal")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.quantumViolet.opacity(0.12))
                    .foregroundStyle(Theme.quantumViolet)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Open Direct SSH Terminal Session")

                Spacer()

                Button(action: {
                    state.deleteDevice(id: device.id)
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Delete Device from Inventory")
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

    private var emptyFleetView: some View {
        VStack(spacing: 18) {
            Image(systemName: "server.rack")
                .font(.system(size: 48))
                .foregroundStyle(Theme.neonCyan.opacity(0.7))

            VStack(spacing: 6) {
                Text("No Managed Devices Enrolled")
                    .font(.system(size: 18, weight: .bold))
                Text("Enrol core switches, branch routers, or local gateways to monitor performance and baseline telemetry.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }

            HStack(spacing: 12) {
                Button(action: { isShowingAddSheet = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                        Text("Enrol Device Manually")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Theme.cyanGlowGradient)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                Button(action: { selectedTab = .discovered }) {
                    HStack(spacing: 6) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                        Text("View Discovered LAN Neighbors")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(60)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.borderLight, lineWidth: 1)
        )
    }

    // MARK: - Discovered Neighbors Section
    @ViewBuilder
    private var discoveredNeighborsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Explanatory Banner
            HStack(spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(Theme.neonCyan)
                    .font(.system(size: 16))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Zero-Root Kernel Neighbor Cache Resolution")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("Live IPv4 ARP and IPv6 NDP neighbor tables parsed unprivileged via Darwin kernel sockets with IEEE OUI vendor resolution.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(12)
            .background(Theme.neonCyan.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Theme.neonCyan.opacity(0.2), lineWidth: 1)
            )

            if state.discoveredNeighbors.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("No LAN Neighbors in Active Kernel Cache")
                        .font(.system(size: 15, weight: .medium))
                    Text("Click 'Scan LAN' to poll active ARP and NDP neighbor tables.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Button("Scan LAN Now") {
                        Task { await state.runLocalDiscovery() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
                .padding(50)
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                // Table of Discovered Neighbors
                VStack(spacing: 0) {
                    // Table Header
                    HStack(spacing: 12) {
                        Text("IP ADDRESS")
                            .frame(width: 140, alignment: .leading)
                        Text("MAC ADDRESS")
                            .frame(width: 150, alignment: .leading)
                        Text("VENDOR / OUI")
                            .frame(width: 130, alignment: .leading)
                        Text("INTERFACE")
                            .frame(width: 90, alignment: .leading)
                        Text("SOURCE")
                            .frame(width: 90, alignment: .leading)
                        Spacer()
                        Text("ACTION")
                            .frame(width: 120, alignment: .trailing)
                    }
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.primary.opacity(0.03))

                    Divider()
                        .background(Theme.borderLight)

                    // Table Rows
                    ForEach(state.discoveredNeighbors) { neighbor in
                        HStack(spacing: 12) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Theme.signalEmerald)
                                    .frame(width: 6, height: 6)
                                Text(neighbor.ip)
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.primary)
                            }
                            .frame(width: 140, alignment: .leading)

                            Text(neighbor.mac)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 150, alignment: .leading)

                            HStack(spacing: 4) {
                                Text(neighbor.vendor.rawValue)
                                    .font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(vendorColor(neighbor.vendor).opacity(0.12))
                                    .foregroundStyle(vendorColor(neighbor.vendor))
                                    .clipShape(Capsule())
                            }
                            .frame(width: 130, alignment: .leading)

                            Text(neighbor.interface)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 90, alignment: .leading)

                            Text(neighbor.source.rawValue)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 90, alignment: .leading)

                            Spacer()

                            let isAlreadyEnrolled = state.managedDevices.contains { $0.ipAddress == neighbor.ip || $0.macAddress == neighbor.mac }
                            if isAlreadyEnrolled {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark")
                                    Text("Enrolled")
                                }
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.signalEmerald)
                                .frame(width: 120, alignment: .trailing)
                            } else {
                                Button(action: {
                                    neighborToEnrol = neighbor
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "plus.circle.fill")
                                        Text("Enrol")
                                    }
                                    .font(.system(size: 11, weight: .semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Theme.neonCyan.opacity(0.15))
                                    .foregroundStyle(Theme.neonCyan)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                .frame(width: 120, alignment: .trailing)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)

                        Divider()
                            .background(Theme.borderLight.opacity(0.5))
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
    }

    private func vendorColor(_ vendor: DeviceVendor) -> Color {
        switch vendor {
        case .apple: return Theme.neonCyan
        case .cisco: return Theme.electricAzure
        case .arista: return Theme.signalEmerald
        case .juniper: return Theme.quantumViolet
        case .ubiquiti: return Theme.cyanPulse
        case .fortinet: return Theme.crimsonCritical
        case .mikrotik: return Theme.solarAmber
        case .vmware: return Theme.electricAzure
        case .raspberryPi: return Theme.pulseCrimson
        case .intel: return Theme.electricAzure
        default: return .secondary
        }
    }
}

// MARK: - Add Device Sheet
struct AddDeviceSheet: View {
    @Bindable var state: AppState
    @Binding var isPresented: Bool

    @State private var name: String = ""
    @State private var ipAddress: String = ""
    @State private var macAddress: String = ""
    @State private var selectedRole: DeviceRole = .switchDevice
    @State private var selectedVendor: DeviceVendor = .cisco
    @State private var location: String = ""
    @State private var tagsString: String = "datacenter, core"
    @State private var enableSNMP: Bool = true
    @State private var snmpCommunity: String = "public"
    @State private var snmpPort: String = "161"

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enrol Managed Device")
                        .font(.system(size: 17, weight: .bold))
                    Text("Add an infrastructure device to your active monitoring inventory.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .background(Theme.cardBackground)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("DEVICE IDENTITY")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)

                        TextField("Device Name (e.g. Core-SW-01)", text: $name)
                            .textFieldStyle(.roundedBorder)

                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("IP Address").font(.system(size: 11, weight: .medium))
                                TextField("192.168.1.1", text: $ipAddress)
                                    .textFieldStyle(.roundedBorder)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("MAC Address (Optional)").font(.system(size: 11, weight: .medium))
                                TextField("00:11:22:33:44:55", text: $macAddress)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("CLASSIFICATION")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 16) {
                            Picker("Role", selection: $selectedRole) {
                                ForEach(DeviceRole.allCases, id: \.self) { role in
                                    Text(role.rawValue).tag(role)
                                }
                            }
                            .frame(maxWidth: .infinity)

                            Picker("Vendor", selection: $selectedVendor) {
                                ForEach(DeviceVendor.allCases, id: \.self) { vendor in
                                    Text(vendor.rawValue).tag(vendor)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("METADATA")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)

                        TextField("Physical Location / Rack (e.g. Rack A-04)", text: $location)
                            .textFieldStyle(.roundedBorder)

                        TextField("Tags (comma separated)", text: $tagsString)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Configure SNMP Studio Target", isOn: $enableSNMP)
                            .font(.system(size: 12, weight: .semibold))

                        if enableSNMP {
                            HStack(spacing: 12) {
                                TextField("Community (e.g. public)", text: $snmpCommunity)
                                    .textFieldStyle(.roundedBorder)
                                TextField("Port", text: $snmpPort)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 80)
                            }
                        }
                    }
                }
                .padding(20)
            }

            Divider()

            // Footer
            HStack {
                Button("Cancel") { isPresented = false }
                    .buttonStyle(.plain)

                Spacer()

                Button(action: saveDevice) {
                    Text("Save Device")
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(Theme.cyanGlowGradient)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || ipAddress.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(16)
            .background(Theme.cardBackground)
        }
        .frame(width: 480, height: 500)
    }

    private func saveDevice() {
        let tags = tagsString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var snmpConfig: SNMPDeviceConfig? = nil
        if enableSNMP {
            snmpConfig = SNMPDeviceConfig(
                community: snmpCommunity.isEmpty ? "public" : snmpCommunity,
                port: Int(snmpPort) ?? 161,
                version: "v2c"
            )
        }

        let device = NetworkDevice(
            name: name.trimmingCharacters(in: .whitespaces),
            ipAddress: ipAddress.trimmingCharacters(in: .whitespaces),
            macAddress: macAddress.isEmpty ? nil : macAddress.trimmingCharacters(in: .whitespaces),
            vendor: selectedVendor,
            role: selectedRole,
            status: .online,
            location: location.isEmpty ? nil : location,
            tags: tags,
            snmpConfig: snmpConfig
        )

        state.addManualDevice(device)
        isPresented = false
    }
}

// MARK: - Enrol Neighbor Sheet
struct EnrolNeighborSheet: View {
    @Bindable var state: AppState
    let neighbor: DiscoveredNeighbor
    @Binding var isPresented: Bool

    @State private var deviceName: String = ""
    @State private var selectedRole: DeviceRole = .host

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enrol Discovered Neighbor")
                        .font(.system(size: 16, weight: .bold))
                    Text("Promote discovered LAN host into permanent managed inventory.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(Theme.cardBackground)

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("IP Address:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 90, alignment: .leading)
                    Text(neighbor.ip)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                }

                HStack {
                    Text("MAC Address:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 90, alignment: .leading)
                    Text(neighbor.mac)
                        .font(.system(size: 12, design: .monospaced))
                }

                HStack {
                    Text("Resolved Vendor:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 90, alignment: .leading)
                    Text(neighbor.vendor.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Device Name").font(.system(size: 11, weight: .medium))
                    TextField("Enter name", text: $deviceName)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Assigned Role").font(.system(size: 11, weight: .medium))
                    Picker("Role", selection: $selectedRole) {
                        ForEach(DeviceRole.allCases, id: \.self) { role in
                            Text(role.rawValue).tag(role)
                        }
                    }
                }
            }
            .padding(20)

            Divider()

            HStack {
                Button("Cancel") { isPresented = false }
                    .buttonStyle(.plain)
                Spacer()
                Button(action: {
                    state.addDiscoveredNeighborToInventory(neighbor, role: selectedRole, name: deviceName)
                    isPresented = false
                }) {
                    Text("Enrol Device")
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Theme.cyanGlowGradient)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(Theme.cardBackground)
        }
        .frame(width: 420, height: 340)
        .onAppear {
            deviceName = neighbor.hostname ?? "\(neighbor.vendor.rawValue)-\(neighbor.ip.split(separator: ".").last ?? "node")"
            if neighbor.vendor == .cisco || neighbor.vendor == .arista || neighbor.vendor == .juniper {
                selectedRole = .switchDevice
            } else if neighbor.vendor == .fortinet {
                selectedRole = .firewall
            } else if neighbor.vendor == .apple {
                selectedRole = .workstation
            } else {
                selectedRole = .host
            }
        }
    }
}

// MARK: - Device Baseline Sheet
struct DeviceBaselineSheet: View {
    @Bindable var state: AppState
    let device: NetworkDevice
    @Binding var isPresented: Bool

    @State private var baselines: [DeviceBaseline] = []
    @State private var isCreatingBaseline: Bool = false
    @State private var latencyInput: String = "1.8"
    @State private var portsInput: String = "22, 80, 443, 161"

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Performance Baselines: \(device.name)")
                        .font(.system(size: 16, weight: .bold))
                    Text("Track historical telemetry baselines to detect degradation and regressions.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(Theme.cardBackground)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Create Baseline Form
                    VStack(alignment: .leading, spacing: 10) {
                        Text("CAPTURE NEW TELEMETRY BASELINE")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.neonCyan)

                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Ping Latency (ms)").font(.system(size: 10))
                                TextField("1.8", text: $latencyInput)
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Open Ports").font(.system(size: 10))
                                TextField("22, 80, 443", text: $portsInput)
                                    .textFieldStyle(.roundedBorder)
                            }

                            Button(action: recordBaseline) {
                                Text("Capture")
                                    .font(.system(size: 11, weight: .semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Theme.neonCyan.opacity(0.15))
                                    .foregroundStyle(Theme.neonCyan)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 14)
                        }
                    }
                    .padding(14)
                    .background(Color.primary.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    // Historical Baselines List
                    Text("RECORDED BASELINES (\(baselines.count))")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)

                    if baselines.isEmpty {
                        Text("No recorded baselines yet for this device.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 10)
                    } else {
                        ForEach(baselines) { baseline in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(baseline.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: 11, weight: .semibold))
                                    Text("Latency: \(String(format: "%.2f ms", baseline.pingLatencyMs)) • Ports: \(baseline.openPorts.map(String.init).joined(separator: ", "))")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "checkmark.shield.fill")
                                    .foregroundStyle(Theme.signalEmerald)
                            }
                            .padding(10)
                            .background(Theme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                .padding(20)
            }

            Divider()

            HStack {
                Spacer()
                Button("Done") { isPresented = false }
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
            .background(Theme.cardBackground)
        }
        .frame(width: 520, height: 420)
        .task {
            loadBaselines()
        }
    }

    private func loadBaselines() {
        baselines = (try? state.deviceManager.listBaselines(forDeviceId: device.id)) ?? []
    }

    private func recordBaseline() {
        let lat = Double(latencyInput) ?? 1.5
        let ports = portsInput.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        let baseline = DeviceBaseline(
            deviceId: device.id,
            pingLatencyMs: lat,
            jitterMs: 0.2,
            packetLossPercent: 0.0,
            openPorts: ports
        )
        try? state.deviceManager.saveBaseline(baseline)
        loadBaselines()
    }
}
