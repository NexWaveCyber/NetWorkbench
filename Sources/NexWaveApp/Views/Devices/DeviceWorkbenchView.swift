import SwiftUI
import DeviceKit
import NetworkCore
import TerminalKit
import AppKit

public struct DeviceWorkbenchView: View {
    @Bindable var state: AppState
    @State private var selectedTab: DeviceTab = .managed
    @State private var searchText: String = ""
    @State private var selectedRoleFilter: DeviceRoleFilter = .all
    @State private var isShowingAddSheet: Bool = false
    @State private var neighborToEnrol: DiscoveredNeighbor? = nil
    @State private var selectedDeviceForBaseline: NetworkDevice? = nil
    @State private var selectedDeviceForAudit: NetworkDevice? = nil

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
        .sheet(item: $selectedDeviceForAudit) { device in
            DeviceAuditSheet(state: state, device: device, isPresented: Binding(
                get: { selectedDeviceForAudit != nil },
                set: { if !$0 { selectedDeviceForAudit = nil } }
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

                Menu {
                    Button(action: {
                        let csv = state.exportFleetToCSV()
                        exportStringToFile(content: csv, defaultName: "managed_fleet_\(Date().formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-")).csv", fileExtension: "csv")
                    }) {
                        Label("Export Fleet (CSV)...", systemImage: "doc.text")
                    }
                    Button(action: {
                        let json = state.exportFleetToJSON()
                        exportStringToFile(content: json, defaultName: "managed_fleet_\(Date().formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-")).json", fileExtension: "json")
                    }) {
                        Label("Export Fleet (JSON)...", systemImage: "curlybraces")
                    }
                    Divider()
                    Button(action: {
                        let csv = state.exportDiscoveredToCSV()
                        exportStringToFile(content: csv, defaultName: "discovered_lan_\(Date().formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-")).csv", fileExtension: "csv")
                    }) {
                        Label("Export LAN Neighbors (CSV)...", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    Button(action: {
                        let json = state.exportDiscoveredToJSON()
                        exportStringToFile(content: json, defaultName: "discovered_lan_\(Date().formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-")).json", fileExtension: "json")
                    }) {
                        Label("Export LAN Neighbors (JSON)...", systemImage: "curlybraces")
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Export")
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
                .menuStyle(.borderlessButton)

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
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 400, maximum: 540), spacing: 16)], spacing: 16) {
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

                            let displayVendor: String = {
                                if let mac = device.macAddress, let resolved = OUIResolver.resolve(mac: mac), !resolved.isEmpty {
                                    return resolved
                                }
                                return device.vendor.rawValue
                            }()

                            Text(displayVendor)
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(vendorColor(device.vendor).opacity(0.12))
                                .foregroundStyle(vendorColor(device.vendor))
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
                    HStack(spacing: 6) {
                        Text("MAC ADDRESS")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(mac)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.primary)

                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(mac, forType: .string)
                            state.toastMessage = "MAC copied: \(mac)"
                        }) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Copy MAC Address")

                        if OUIResolver.isLocallyAdministered(mac: mac) {
                            Text("Private Wi-Fi")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Theme.quantumViolet.opacity(0.15))
                                .foregroundStyle(Theme.quantumViolet)
                                .clipShape(Capsule())
                                .help("IEEE 802 Locally Administered / Private MAC")
                        } else if let vendor = OUIResolver.lookup(mac: mac) {
                            Text(vendor)
                                .font(.system(size: 9, weight: .medium))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.primary.opacity(0.06))
                                .foregroundStyle(.secondary)
                                .clipShape(Capsule())
                        }
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

            // Action Buttons Deck
            VStack(spacing: 8) {
                // Row 1: Telemetry & Diagnostics
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
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Theme.electricAzure.opacity(0.12))
                        .foregroundStyle(Theme.electricAzure)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help("Run diagnostic suite on \(device.ipAddress)")

                    Button(action: {
                        selectedDeviceForAudit = device
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "gauge.with.needle")
                                .font(.system(size: 11))
                            Text("Audit")
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Theme.signalEmerald.opacity(0.12))
                        .foregroundStyle(Theme.signalEmerald)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help("Audit live telemetry vs recorded performance baseline")

                    Button(action: {
                        state.addDeviceToTimeline(device: device)
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "waveform.path.ecg")
                                .font(.system(size: 11))
                            Text("Monitor")
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Theme.solarAmber.opacity(0.12))
                        .foregroundStyle(Theme.solarAmber)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help("Add device to Timeline Monitor for SLA tracking")

                    Spacer()
                }

                // Row 2: Management Tools & Baseline
                HStack(spacing: 8) {
                    Button(action: {
                        state.jumpToSNMPStudio(device: device)
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "chart.bar.xaxis")
                                .font(.system(size: 11))
                            Text("SNMP")
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Theme.neonCyan.opacity(0.12))
                        .foregroundStyle(Theme.neonCyan)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help("Open SNMP Studio pre-populated for this device")

                    Button(action: {
                        selectedDeviceForBaseline = device
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.system(size: 11))
                            Text("Baseline")
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.06))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help("View or capture performance baselines")

                    Button(action: {
                        state.terminalManager.openSSHSession(host: device.ipAddress)
                        state.selectedWorkspace = .terminal
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "terminal.fill")
                                .font(.system(size: 11))
                            Text("SSH")
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                                .fixedSize()
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
                        Text("IP ADDRESS (IPv4 / IPv6)")
                            .frame(width: 190, alignment: .leading)
                        Text("MAC ADDRESS")
                            .frame(width: 160, alignment: .leading)
                        Text("VENDOR / OUI")
                            .frame(width: 140, alignment: .leading)
                        Text("INTERFACE")
                            .frame(width: 80, alignment: .leading)
                        Text("SOURCE")
                            .frame(width: 90, alignment: .leading)
                        Spacer()
                        Text("ACTION")
                            .frame(width: 140, alignment: .trailing)
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
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Theme.signalEmerald)
                                        .frame(width: 6, height: 6)
                                    Text(neighbor.ip)
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(.primary)
                                }
                                if let v6 = neighbor.ipv6Address, v6 != neighbor.ip {
                                    HStack(spacing: 4) {
                                        Text(v6)
                                            .font(.system(size: 9.5, design: .monospaced))
                                            .foregroundStyle(Theme.neonCyan.opacity(0.9))
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                            .help("Unique IPv6: \(v6)")

                                        Button(action: {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(v6, forType: .string)
                                            state.toastMessage = "IPv6 copied: \(v6)"
                                        }) {
                                            Image(systemName: "doc.on.doc")
                                                .font(.system(size: 8))
                                                .foregroundStyle(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Copy Unique IPv6")
                                    }
                                }
                                if let host = neighbor.hostname, !host.isEmpty {
                                    Text(host)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(width: 190, alignment: .leading)

                            HStack(spacing: 4) {
                                Text(neighbor.mac)
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.secondary)

                                Button(action: {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(neighbor.mac, forType: .string)
                                    state.toastMessage = "MAC copied: \(neighbor.mac)"
                                }) {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Copy MAC Address")

                                if OUIResolver.isLocallyAdministered(mac: neighbor.mac) {
                                    Image(systemName: "lock.shield")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Theme.quantumViolet)
                                        .help("IEEE 802 Locally Administered / Private Wi-Fi MAC")
                                }
                            }
                            .frame(width: 160, alignment: .leading)

                            HStack(spacing: 4) {
                                let vendorName = neighbor.ouiVendor ?? neighbor.vendor.rawValue
                                Text(vendorName)
                                    .font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(vendorColor(neighbor.vendor).opacity(0.12))
                                    .foregroundStyle(vendorColor(neighbor.vendor))
                                    .clipShape(Capsule())
                                    .lineLimit(1)
                            }
                            .frame(width: 140, alignment: .leading)

                            Text(neighbor.interface)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 80, alignment: .leading)

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
                                .frame(width: 140, alignment: .trailing)
                            } else {
                                HStack(spacing: 6) {
                                    Button(action: {
                                        state.targetInput = neighbor.ip
                                        state.updateTargetClassification(neighbor.ip)
                                        state.selectedWorkspace = .diagnose
                                        if let target = state.classifiedTarget {
                                            Task { await state.runDiagnosis(target: target) }
                                        }
                                    }) {
                                        Image(systemName: "stethoscope")
                                            .font(.system(size: 10))
                                            .padding(5)
                                            .background(Theme.electricAzure.opacity(0.12))
                                            .foregroundStyle(Theme.electricAzure)
                                            .clipShape(Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .help("Quick Diagnose this IP")

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
                                }
                                .frame(width: 140, alignment: .trailing)
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
        case .linksys: return Color(red: 0.0, green: 0.55, blue: 0.95)
        case .netgear: return Theme.quantumViolet
        case .tpLink: return Theme.cyanPulse
        case .asus: return Theme.solarAmber
        case .synology: return Theme.signalEmerald
        case .dlink: return Color(red: 0.95, green: 0.45, blue: 0.15)
        case .paloAlto: return Theme.crimsonCritical
        case .huawei: return Theme.crimsonCritical
        case .dell: return Color(red: 0.0, green: 0.47, blue: 0.75)
        case .hpe: return Color(red: 0.0, green: 0.65, blue: 0.55)
        case .amazon: return Color(red: 1.0, green: 0.60, blue: 0.0)
        case .google: return Color(red: 0.26, green: 0.52, blue: 0.96)
        case .arris: return Color(red: 0.8, green: 0.2, blue: 0.2)
        case .avm: return Color(red: 0.9, green: 0.2, blue: 0.2)
        case .belkin: return Color(red: 0.3, green: 0.75, blue: 0.3)
        case .zyxel: return Color(red: 0.1, green: 0.5, blue: 0.8)
        case .linux: return Theme.solarAmber
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
                                HStack {
                                    Text("IP Address").font(.system(size: 11, weight: .medium))
                                    Spacer()
                                    Button(action: detectFromARP) {
                                        HStack(spacing: 3) {
                                            Image(systemName: "sparkles")
                                            Text("Detect ARP")
                                        }
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(Theme.neonCyan)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(ipAddress.trimmingCharacters(in: .whitespaces).isEmpty)
                                }
                                TextField("192.168.1.1", text: $ipAddress)
                                    .textFieldStyle(.roundedBorder)
                                    .onSubmit { detectFromARP() }
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("MAC Address (Optional)").font(.system(size: 11, weight: .medium))
                                TextField("00:11:22:33:44:55", text: $macAddress)
                                    .textFieldStyle(.roundedBorder)
                                    .onChange(of: macAddress) { _, newMac in
                                        if !newMac.isEmpty {
                                            let inferred = OUIResolver.inferVendor(mac: newMac)
                                            if inferred != .generic {
                                                selectedVendor = inferred
                                            }
                                        }
                                    }
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

    private func detectFromARP() {
        let cleanIP = ipAddress.trimmingCharacters(in: .whitespaces)
        guard !cleanIP.isEmpty else { return }
        if let resolved = LocalDiscoveryEngine.resolveLocalHost(ip: cleanIP) {
            macAddress = resolved.mac
            selectedVendor = resolved.vendor
            if name.trimmingCharacters(in: .whitespaces).isEmpty {
                if let vName = resolved.vendorName {
                    name = "\(vName) Router"
                }
            }
        }
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

        var resolvedMac = macAddress.isEmpty ? nil : macAddress.trimmingCharacters(in: .whitespaces)
        var finalVendor = selectedVendor
        let cleanIP = ipAddress.trimmingCharacters(in: .whitespaces)

        if (resolvedMac == nil || finalVendor == .generic) && !cleanIP.isEmpty {
            if let auto = LocalDiscoveryEngine.resolveLocalHost(ip: cleanIP) {
                if resolvedMac == nil { resolvedMac = auto.mac }
                if finalVendor == .generic { finalVendor = auto.vendor }
            }
        }

        let device = NetworkDevice(
            name: name.trimmingCharacters(in: .whitespaces),
            ipAddress: cleanIP,
            macAddress: resolvedMac,
            vendor: finalVendor,
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
            } else if neighbor.vendor == .linksys || neighbor.vendor == .netgear || neighbor.vendor == .asus || neighbor.vendor == .tpLink || neighbor.vendor == .dlink || neighbor.vendor == .avm {
                selectedRole = .router
            } else if neighbor.vendor == .fortinet || neighbor.vendor == .paloAlto {
                selectedRole = .firewall
            } else if neighbor.vendor == .apple {
                selectedRole = .workstation
            } else if neighbor.vendor == .synology {
                selectedRole = .server
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
    @State private var isProbingLive: Bool = false
    @State private var probeMessage: String = ""
    @State private var latencyInput: String = "1.8"
    @State private var portsInput: String = "22, 80, 443, 161"
    @State private var notesInput: String = ""
    @State private var lastLiveSample: DeviceBaselineSample? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("Performance Baselines: \(device.name)")
                            .font(.system(size: 16, weight: .bold))
                        Text(device.ipAddress)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.neonCyan)
                    }
                    Text("Automated live probes establish SLA reference metrics for latency, jitter, loss, and port surface.")
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
            .padding(18)
            .background(Theme.cardBackground)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Automated Live Active Probe Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("AUTOMATED ACTIVE TELEMETRY PROBE")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Theme.neonCyan)
                                Text("Executes Darwin non-root ICMP ping train (5 probes) and concurrent TCP scan across enterprise service ports.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()

                            Button(action: runLiveProbe) {
                                HStack(spacing: 6) {
                                    if isProbingLive {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Image(systemName: "bolt.fill")
                                            .font(.system(size: 11))
                                    }
                                    Text(isProbingLive ? "Probing..." : "Run Live Probe")
                                        .font(.system(size: 11, weight: .bold))
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(Theme.cyanGlowGradient)
                                .foregroundStyle(.black)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                            .disabled(isProbingLive)
                        }

                        if !probeMessage.isEmpty {
                            Text(probeMessage)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(Theme.neonCyan)
                        }

                        if let sample = lastLiveSample {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 16) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("AVG LATENCY").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
                                        Text(String(format: "%.2f ms", sample.avgLatencyMs)).font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundStyle(Theme.signalEmerald)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("JITTER").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
                                        Text(String(format: "%.2f ms", sample.jitterMs)).font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundStyle(.primary)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("PACKET LOSS").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
                                        Text(String(format: "%.1f%%", sample.packetLossPct)).font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundStyle(sample.packetLossPct > 0 ? Theme.amberWarning : Theme.signalEmerald)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("DISCOVERED PORTS").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
                                        Text(sample.openPorts.isEmpty ? "None" : sample.openPorts.map(String.init).joined(separator: ", ")).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(Theme.neonCyan)
                                    }
                                }
                                .padding(10)
                                .background(Theme.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 6))

                                Button(action: {
                                    saveLiveSample(sample)
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "checkmark.circle.fill")
                                        Text("Save Live Sample as Baseline Reference")
                                    }
                                    .font(.system(size: 11, weight: .bold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Theme.signalEmerald.opacity(0.15))
                                    .foregroundStyle(Theme.signalEmerald)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(14)
                    .background(Color.primary.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    // Manual Adjustment Section
                    VStack(alignment: .leading, spacing: 10) {
                        Text("MANUAL BASELINE SPECIFICATION")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Ping Latency (ms)").font(.system(size: 10))
                                TextField("1.8", text: $latencyInput)
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Open Ports (CSV)").font(.system(size: 10))
                                TextField("22, 80, 443, 161", text: $portsInput)
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Notes").font(.system(size: 10))
                                TextField("e.g. Core Switch Q3 Audit", text: $notesInput)
                                    .textFieldStyle(.roundedBorder)
                            }

                            Button(action: recordManualBaseline) {
                                Text("Record")
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
                    .background(Color.primary.opacity(0.02))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    // Historical Baselines List
                    Text("RECORDED BASELINES (\(baselines.count))")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)

                    if baselines.isEmpty {
                        Text("No recorded baselines yet for this device. Click 'Run Live Probe' above to generate one.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 10)
                    } else {
                        ForEach(baselines) { baseline in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 8) {
                                        Text(baseline.createdAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.system(size: 11, weight: .semibold))
                                        if !baseline.notes.isEmpty {
                                            Text("• \(baseline.notes)")
                                                .font(.system(size: 11))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Text("Latency: \(String(format: "%.2f ms", baseline.pingLatencyMs)) • Loss: \(String(format: "%.1f%%", baseline.packetLossPercent)) • Ports: \(baseline.openPorts.map(String.init).joined(separator: ", "))")
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
        .frame(width: 580, height: 520)
        .task {
            loadBaselines()
        }
    }

    private func loadBaselines() {
        baselines = (try? state.deviceManager.listBaselines(forDeviceId: device.id)) ?? []
    }

    private func runLiveProbe() {
        Task {
            isProbingLive = true
            probeMessage = "Probing \(device.ipAddress) with ICMP ping train & enterprise TCP scan..."
            let sample = await state.deviceAuditor.probeLiveBaseline(
                ipAddress: device.ipAddress,
                pingCount: 5,
                snmpConfig: device.snmpConfig
            )
            lastLiveSample = sample
            latencyInput = String(format: "%.2f", sample.avgLatencyMs)
            portsInput = sample.openPorts.map(String.init).joined(separator: ", ")
            isProbingLive = false
            probeMessage = "Live probe complete: \(String(format: "%.2f ms", sample.avgLatencyMs)) latency, \(sample.openPorts.count) open ports."
        }
    }

    private func saveLiveSample(_ sample: DeviceBaselineSample) {
        let baseline = DeviceBaseline(
            deviceId: device.id,
            createdAt: sample.measuredAt,
            avgLatencyMs: sample.avgLatencyMs,
            packetLossPct: sample.packetLossPct,
            openPorts: sample.openPorts,
            snmpSysDescr: sample.snmpSysDescr,
            notes: "Automated live telemetry capture"
        )
        try? state.deviceManager.saveBaseline(baseline)
        loadBaselines()
        state.toastMessage = "Recorded live baseline for \(device.displayName)"
    }

    private func recordManualBaseline() {
        let lat = Double(latencyInput) ?? 1.5
        let ports = portsInput.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        let baseline = DeviceBaseline(
            deviceId: device.id,
            createdAt: Date(),
            avgLatencyMs: lat,
            packetLossPct: 0.0,
            openPorts: ports,
            snmpSysDescr: device.snmpConfig != nil ? "SNMP Agent" : nil,
            notes: notesInput.isEmpty ? "Manual baseline entry" : notesInput
        )
        try? state.deviceManager.saveBaseline(baseline)
        loadBaselines()
        state.toastMessage = "Saved baseline for \(device.displayName)"
    }
}

// MARK: - Device Audit Sheet (Live Drift & Health Score)
struct DeviceAuditSheet: View {
    @Bindable var state: AppState
    let device: NetworkDevice
    @Binding var isPresented: Bool

    @State private var isAuditing: Bool = true
    @State private var baseline: DeviceBaseline? = nil
    @State private var latestSample: DeviceBaselineSample? = nil
    @State private var comparisonResult: BaselineComparisonResult? = nil
    @State private var statusMessage: String = "Initiating telemetry probe..."

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("Active Telemetry Audit: \(device.name)")
                            .font(.system(size: 16, weight: .bold))
                        Text(device.ipAddress)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.neonCyan)
                    }
                    Text("Real-time telemetry drift assessment comparing live performance against recorded baseline.")
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
            .padding(18)
            .background(Theme.cardBackground)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if isAuditing {
                        VStack(spacing: 16) {
                            ProgressView()
                                .controlSize(.large)
                            Text(statusMessage)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundStyle(Theme.neonCyan)
                            Text("Pinging target, calculating jitter/loss, and scanning enterprise port surface...")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(50)
                    } else if let comparison = comparisonResult, let base = baseline, let sample = latestSample {
                        // Top Health Score Card
                        HStack(spacing: 24) {
                            // Circular Gauge
                            ZStack {
                                Circle()
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 8)
                                Circle()
                                    .trim(from: 0, to: CGFloat(comparison.overallHealthScore) / 100.0)
                                    .stroke(scoreColor(comparison.overallHealthScore), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                                VStack(spacing: 2) {
                                    Text("\(comparison.overallHealthScore)%")
                                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                                        .foregroundStyle(scoreColor(comparison.overallHealthScore))
                                    Text(scoreTitle(comparison.overallHealthScore))
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 90, height: 90)

                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Text("HEALTH AUDIT RESULT")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundStyle(scoreColor(comparison.overallHealthScore))
                                    Text("•")
                                        .foregroundStyle(.secondary)
                                    Text("Baseline from \(base.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }

                                if comparison.overallHealthScore >= 90 {
                                    Text("Device telemetry is fully compliant with performance baseline.")
                                        .font(.system(size: 13, weight: .medium))
                                } else if comparison.overallHealthScore >= 70 {
                                    Text("Moderate performance drift detected. Latency or packet loss degraded.")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Theme.solarAmber)
                                } else {
                                    Text("Critical performance regression or unexpected port drift detected!")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(Theme.crimsonCritical)
                                }

                                HStack(spacing: 12) {
                                    Button("Adopt Current as New Baseline") {
                                        adoptNewBaseline(sample)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)

                                    Button("Re-Audit Now") {
                                        Task { await runAudit() }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        }
                        .padding(16)
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Theme.borderLight, lineWidth: 1)
                        )

                        // 3 Comparative Cards
                        HStack(spacing: 12) {
                            // Latency Delta Card
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("LATENCY DRIFT")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(comparison.isLatencyDegraded ? "DEGRADED" : "NOMINAL")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(comparison.isLatencyDegraded ? Theme.solarAmber : Theme.signalEmerald)
                                }

                                HStack(alignment: .lastTextBaseline, spacing: 6) {
                                    Text(String(format: "%+.2f ms", comparison.latencyDeltaMs))
                                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                                        .foregroundStyle(comparison.isLatencyDegraded ? Theme.solarAmber : Theme.signalEmerald)
                                }

                                Text("Base: \(String(format: "%.2f ms", base.avgLatencyMs)) → Live: \(String(format: "%.2f ms", sample.avgLatencyMs))")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                            // Packet Loss Delta Card
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("PACKET LOSS")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(comparison.isLossDegraded ? "LOSS DETECTED" : "ZERO LOSS")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(comparison.isLossDegraded ? Theme.crimsonCritical : Theme.signalEmerald)
                                }

                                HStack(alignment: .lastTextBaseline, spacing: 6) {
                                    Text(String(format: "%+.1f%%", comparison.lossDeltaPct))
                                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                                        .foregroundStyle(comparison.isLossDegraded ? Theme.crimsonCritical : Theme.signalEmerald)
                                }

                                Text("Base: \(String(format: "%.1f%%", base.packetLossPct)) → Live: \(String(format: "%.1f%%", sample.packetLossPct))")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                            // Jitter Card
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("JITTER")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("STABILITY")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(Theme.neonCyan)
                                }

                                Text(String(format: "%.2f ms", sample.jitterMs))
                                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.primary)

                                Text("Range: \(String(format: "%.1f-%.1f ms", sample.minLatencyMs, sample.maxLatencyMs))")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        // Port Surface Drift Card
                        VStack(alignment: .leading, spacing: 10) {
                            Text("PORT SURFACE INTEGRITY")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)

                            HStack(spacing: 8) {
                                Text("Baseline Ports:")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Text(base.openPorts.isEmpty ? "None" : base.openPorts.map(String.init).joined(separator: ", "))
                                    .font(.system(size: 11, design: .monospaced))
                            }

                            HStack(spacing: 8) {
                                Text("Live Open Ports:")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Text(sample.openPorts.isEmpty ? "None" : sample.openPorts.map(String.init).joined(separator: ", "))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Theme.signalEmerald)
                            }

                            if !comparison.missingPorts.isEmpty {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(Theme.crimsonCritical)
                                    Text("Missing Expected Ports: \(comparison.missingPorts.map(String.init).joined(separator: ", "))")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(Theme.crimsonCritical)
                                }
                            }

                            if !comparison.unexpectedPorts.isEmpty {
                                HStack(spacing: 8) {
                                    Image(systemName: "shield.slash.fill")
                                        .foregroundStyle(Theme.solarAmber)
                                    Text("Unexpected Newly Opened Ports: \(comparison.unexpectedPorts.map(String.init).joined(separator: ", "))")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(Theme.solarAmber)
                                }
                            }
                        }
                        .padding(14)
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    } else if let sample = latestSample {
                        // No baseline case
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(Theme.solarAmber)
                                    .font(.system(size: 20))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("No Historical Baseline Recorded")
                                        .font(.system(size: 14, weight: .bold))
                                    Text("A live active probe was performed. Save this sample as the baseline reference to enable drift auditing.")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                            }

                            HStack(spacing: 16) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("AVG LATENCY").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
                                    Text(String(format: "%.2f ms", sample.avgLatencyMs)).font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundStyle(Theme.signalEmerald)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("JITTER").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
                                    Text(String(format: "%.2f ms", sample.jitterMs)).font(.system(size: 14, weight: .bold, design: .monospaced))
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("PACKET LOSS").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
                                    Text(String(format: "%.1f%%", sample.packetLossPct)).font(.system(size: 14, weight: .bold, design: .monospaced))
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("OPEN PORTS").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
                                    Text(sample.openPorts.isEmpty ? "None" : sample.openPorts.map(String.init).joined(separator: ", ")).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(Theme.neonCyan)
                                }
                            }
                            .padding(12)
                            .background(Color.primary.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                            Button(action: {
                                adoptNewBaseline(sample)
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                    Text("Save as Initial Baseline Reference")
                                }
                                .font(.system(size: 12, weight: .bold))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Theme.cyanGlowGradient)
                                .foregroundStyle(.black)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(18)
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(20)
            }

            Divider()

            // Footer Actions
            HStack {
                Button("Close") { isPresented = false }
                    .buttonStyle(.plain)

                Spacer()

                Button(action: {
                    state.addDeviceToTimeline(device: device)
                    isPresented = false
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "waveform.path.ecg")
                        Text("Add to SLA Monitor")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Theme.solarAmber.opacity(0.15))
                    .foregroundStyle(Theme.solarAmber)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                Button(action: {
                    state.targetInput = device.ipAddress
                    state.updateTargetClassification(device.ipAddress)
                    state.selectedWorkspace = .diagnose
                    isPresented = false
                    if let target = state.classifiedTarget {
                        Task { await state.runDiagnosis(target: target) }
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "stethoscope")
                        Text("Full Diagnosis")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Theme.electricAzure.opacity(0.15))
                    .foregroundStyle(Theme.electricAzure)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(Theme.cardBackground)
        }
        .frame(width: 620, height: 560)
        .task {
            await runAudit()
        }
    }

    private func runAudit() async {
        isAuditing = true
        statusMessage = "Pinging \(device.ipAddress) & auditing telemetry drift..."
        let baselines = (try? state.deviceManager.listBaselines(forDeviceId: device.id)) ?? []
        baseline = baselines.first

        if let base = baseline {
            let (sample, comparison) = await state.deviceAuditor.auditDevice(
                device: device,
                baseline: base,
                manager: state.deviceManager
            )
            latestSample = sample
            comparisonResult = comparison
        } else {
            let sample = await state.deviceAuditor.probeLiveBaseline(
                ipAddress: device.ipAddress,
                pingCount: 5,
                snmpConfig: device.snmpConfig
            )
            latestSample = sample
            comparisonResult = nil
        }
        isAuditing = false
    }

    private func adoptNewBaseline(_ sample: DeviceBaselineSample) {
        let newBaseline = DeviceBaseline(
            deviceId: device.id,
            createdAt: sample.measuredAt,
            avgLatencyMs: sample.avgLatencyMs,
            packetLossPct: sample.packetLossPct,
            openPorts: sample.openPorts,
            snmpSysDescr: sample.snmpSysDescr,
            notes: "Adopted from live audit"
        )
        try? state.deviceManager.saveBaseline(newBaseline)
        Task { await runAudit() }
        state.toastMessage = "New baseline reference adopted for \(device.displayName)"
    }

    private func scoreColor(_ score: Int) -> Color {
        if score >= 90 { return Theme.signalEmerald }
        if score >= 70 { return Theme.solarAmber }
        return Theme.crimsonCritical
    }

    private func scoreTitle(_ score: Int) -> String {
        if score >= 90 { return "NOMINAL" }
        if score >= 70 { return "DRIFT" }
        return "DEGRADED"
    }
}

// MARK: - Save Panel Helper
@MainActor
private func exportStringToFile(content: String, defaultName: String, fileExtension: String) {
    let panel = NSSavePanel()
    panel.title = "Export \(defaultName)"
    panel.nameFieldStringValue = defaultName
    panel.canCreateDirectories = true
    if panel.runModal() == .OK, let url = panel.url {
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            print("Failed to save: \(error)")
        }
    }
}
