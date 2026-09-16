import SwiftUI
import NetworkCore
import DiagnosticsEngine
import InvestigationKit

public struct HomeDashboardView: View {
    @Bindable var state: AppState
    @State private var monitor = MenuBarMonitorEngine.shared
    @State private var hoveredStudio: String? = nil

    public init(state: AppState) {
        self.state = state
    }

    public var body: some View {
        ZStack {
            Theme.ambientMeshView

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    // Hero Command Center Deck
                    heroDiagnoseCard

                    // Local Network Interface Telemetry Bar
                    networkInterfaceBar

                    // Two Column Layout: Investigations & Diagnostic Feed
                    HStack(alignment: .top, spacing: 18) {
                        activeInvestigationsCard
                        recentDiagnosesCard
                    }

                    // Interactive Studio Launchers
                    toolboxStudiosGrid
                }
                .padding(24)
            }
        }
        .navigationTitle("Engineering Dashboard")
        .onAppear {
            monitor.startMonitoring()
        }
    }

    // MARK: - Hero Command Center Deck
    private var heroDiagnoseCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        PulsingBeacon(color: Theme.neonCyan, size: 7, isLive: true)

                        Text("GLOBAL TELEMETRY ENGINE")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.neonCyan)

                        Text("•")
                            .foregroundStyle(.secondary)

                        Text("MULTI-LAYER DETERMINISTIC DIAGNOSTICS")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Text("Network Diagnostic Command Center")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, Color.white.opacity(0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                Spacer()

                ZStack {
                    Circle()
                        .fill(Theme.neonCyan.opacity(0.12))
                        .frame(width: 52, height: 52)
                        .overlay(
                            Circle()
                                .stroke(Theme.neonCyan.opacity(0.3), lineWidth: 1.5)
                        )

                    Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                        .font(.system(size: 24))
                        .foregroundStyle(Theme.neonCyan)
                        .shadow(color: Theme.neonCyan.opacity(0.5), radius: 6, x: 0, y: 0)
                }
            }

            // Input Row
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.neonCyan)

                        TextField("Enter target host, IP, URL, or CIDR (e.g. google.com, 1.1.1.1, 10.20.0.0/24)...", text: $state.targetInput)
                            .textFieldStyle(.plain)
                            .font(Theme.monoText(15))
                            .onChange(of: state.targetInput) { _, newValue in
                                state.updateTargetClassification(newValue)
                            }
                            .onSubmit {
                                startDiagnosisFromHome()
                            }

                        if let target = state.classifiedTarget {
                            Text(target.targetType.rawValue)
                                .font(Theme.monoText(10, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Theme.azurePro.opacity(0.15))
                                .foregroundStyle(Theme.azurePro)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Theme.azurePro.opacity(0.3), lineWidth: 1)
                                )
                        }
                    }
                    .padding(12)
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Theme.cyanPulse.opacity(0.35), lineWidth: 1)
                    )

                    Button(action: startDiagnosisFromHome) {
                        HStack(spacing: 7) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 12))
                            Text("Diagnose Target")
                                .fontWeight(.semibold)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(state.classifiedTarget == nil ? AnyShapeStyle(Color.gray.opacity(0.3)) : AnyShapeStyle(Theme.cyanGlowGradient))
                        .foregroundStyle(state.classifiedTarget == nil ? Color.secondary : Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .shadow(color: state.classifiedTarget == nil ? .clear : Theme.neonCyan.opacity(0.3), radius: 6, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .disabled(state.classifiedTarget == nil)
                }

                // Quick Target Presets
                HStack(spacing: 8) {
                    Text("Quick Targets:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    ForEach(["google.com", "1.1.1.1", "api.github.com", monitor.defaultGateway], id: \.self) { sample in
                        Button(action: {
                            state.updateTargetClassification(sample)
                            startDiagnosisFromHome()
                        }) {
                            HStack(spacing: 4) {
                                Circle().fill(Theme.neonCyan.opacity(0.8)).frame(width: 4, height: 4)
                                Text(sample)
                                    .font(Theme.monoText(11))
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.borderLight, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .engineeringCard(padding: 20, hasHoverEffect: false, accentBorder: Theme.neonCyan.opacity(0.3))
    }

    private func startDiagnosisFromHome() {
        state.selectedWorkspace = .diagnose
        if let target = state.classifiedTarget {
            Task {
                await state.runDiagnosis(target: target)
            }
        }
    }

    // MARK: - Network Interface Bar
    private var networkInterfaceBar: some View {
        HStack(spacing: 14) {
            kpiCard(
                label: "PRIMARY LINK",
                val: primaryLinkDisplay,
                icon: monitor.wifiLink != nil ? "wifi" : "cable.connector",
                badge: "Active",
                badgeColor: Theme.signalEmerald
            )
            kpiCard(
                label: "LOCAL IPV4",
                val: monitor.localIP,
                icon: "laptopcomputer",
                badge: monitor.activeInterface,
                badgeColor: Theme.azurePro,
                copyValue: monitor.localIP
            )
            kpiCard(
                label: "DEFAULT GATEWAY",
                val: monitor.defaultGateway,
                icon: "network",
                badge: gatewayLatencyBadge,
                badgeColor: Theme.neonCyan,
                copyValue: monitor.defaultGateway
            )
            kpiCard(
                label: "SYSTEM RESOLVER",
                val: monitor.dnsServer,
                icon: "arrow.triangle.branch",
                badge: "Active DNS",
                badgeColor: Theme.signalEmerald,
                copyValue: monitor.dnsServer
            )
        }
    }

    private var primaryLinkDisplay: String {
        if let wifi = monitor.wifiLink {
            let ssidPart = (!wifi.ssid.isEmpty && wifi.ssid != "<redacted>") ? " • \(wifi.ssid)" : ""
            return "\(monitor.activeInterface)\(ssidPart) (\(wifi.phyMode.displayName))"
        }
        return "\(monitor.activeInterface) (GbE / Active)"
    }

    private var gatewayLatencyBadge: String {
        if let rtt = monitor.gatewayLatencyMs {
            return rtt < 1.0 ? "< 1ms" : String(format: "%.1f ms", rtt)
        }
        return "< 1ms"
    }

    private func kpiCard(
        label: String,
        val: String,
        icon: String,
        badge: String? = nil,
        badgeColor: Color? = nil,
        copyValue: String? = nil
    ) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.azurePro.opacity(0.12))
                    .frame(width: 32, height: 32)

                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.azurePro)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(label)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)

                    if let badge = badge, let badgeColor = badgeColor {
                        Text(badge)
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(badgeColor.opacity(0.15))
                            .foregroundStyle(badgeColor)
                            .clipShape(Capsule())
                    }
                }

                Text(val)
                    .font(Theme.monoText(12, weight: .semibold))
                    .lineLimit(1)
            }

            Spacer()

            if let copyValue = copyValue {
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(copyValue, forType: .string)
                    state.toastMessage = "Copied \(copyValue) to clipboard"
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Copy to clipboard")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .engineeringCard(padding: 0, cornerRadius: 10, hasHoverEffect: true)
    }

    // MARK: - Active Investigations Card
    private var activeInvestigationsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 7) {
                    Image(systemName: "briefcase.fill")
                        .foregroundStyle(Theme.azurePro)
                    Text("Active Investigations")
                        .font(.system(size: 14, weight: .bold))
                }

                Spacer()

                Button("View All →") {
                    state.selectedWorkspace = .investigations
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.neonCyan)
            }

            Divider()

            if state.investigations.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 26))
                        .foregroundStyle(.secondary.opacity(0.6))
                    Text("No active investigations")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Diagnose a target and click 'Create Investigation' to record timeline events & evidence.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                VStack(spacing: 8) {
                    ForEach(state.investigations.prefix(4)) { inv in
                        Button(action: {
                            state.selectedInvestigation = inv
                            state.selectedWorkspace = .investigations
                        }) {
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(severityColor(inv.severity))
                                    .frame(width: 3, height: 32)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(inv.title)
                                        .font(.system(size: 12, weight: .semibold))
                                        .lineLimit(1)
                                    Text(inv.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text(inv.status.rawValue)
                                    .font(Theme.monoText(10, weight: .bold))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Color.primary.opacity(0.06))
                                    .clipShape(Capsule())
                            }
                            .padding(10)
                            .background(Color.primary.opacity(0.02))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .engineeringCard(hasHoverEffect: false)
    }

    // MARK: - Recent Diagnoses Card
    private var recentDiagnosesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 7) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(Theme.neonCyan)
                    Text("Recent Diagnostics")
                        .font(.system(size: 14, weight: .bold))
                }

                Spacer()

                Button("Full History →") {
                    state.selectedWorkspace = .history
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.neonCyan)
            }

            Divider()

            if state.recentHistory.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "gauge.with.needle")
                        .font(.system(size: 26))
                        .foregroundStyle(.secondary.opacity(0.6))
                    Text("No diagnostic runs recorded")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Execute a target diagnostic above to automatically stream telemetry.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                VStack(spacing: 8) {
                    ForEach(state.recentHistory.prefix(4)) { item in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(item.tcpHealthy ? Theme.signalEmerald : Theme.pulseCrimson)
                                .frame(width: 8, height: 8)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.target)
                                    .font(Theme.monoText(12, weight: .bold))
                                Text(Date(timeIntervalSince1970: item.timestamp).formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if let lat = item.pingLatency {
                                HStack(spacing: 4) {
                                    Text("\(String(format: "%.1f", lat))")
                                        .font(Theme.monoText(12, weight: .bold))
                                    Text("ms")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Theme.neonCyan.opacity(0.1))
                                .foregroundStyle(Theme.neonCyan)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        }
                        .padding(10)
                        .background(Color.primary.opacity(0.02))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .engineeringCard(hasHoverEffect: false)
    }

    // MARK: - Interactive Studios Grid
    private var toolboxStudiosGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("INTERACTIVE ENGINEERING STUDIOS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Zero-Root Unprivileged Tools")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                studioCard(
                    id: "subnet",
                    title: "Subnet Calculator",
                    desc: "CIDR / VLSM / Binary Matrix",
                    icon: "number.square.fill",
                    tint: Theme.neonCyan,
                    workspace: .toolbox
                )
                studioCard(
                    id: "cmd",
                    title: "Command Library",
                    desc: "Multi-Vendor CLI Reference",
                    icon: "terminal.fill",
                    tint: Theme.electricAzure,
                    workspace: .commandLibrary
                )
                studioCard(
                    id: "snmp",
                    title: "SNMP Studio",
                    desc: "v1/v2c/v3 MIB Tree Browser",
                    icon: "chart.bar.xaxis",
                    tint: Theme.solarAmber,
                    workspace: .snmp
                )
                studioCard(
                    id: "config",
                    title: "Config Workbench",
                    desc: "Syntax Parser & Semantic Diff",
                    icon: "doc.text.magnifyingglass",
                    tint: Theme.quantumViolet,
                    workspace: .config
                )
            }
        }
    }

    private func studioCard(
        id: String,
        title: String,
        desc: String,
        icon: String,
        tint: Color,
        workspace: WorkspaceItem
    ) -> some View {
        Button(action: {
            state.selectedWorkspace = workspace
        }) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(tint.opacity(0.15))
                            .frame(width: 36, height: 36)

                        Image(systemName: icon)
                            .font(.system(size: 18))
                            .foregroundStyle(tint)
                    }

                    Spacer()

                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                    Text(desc)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .engineeringCard(padding: 0, cornerRadius: 10, hasHoverEffect: true)
        }
        .buttonStyle(.plain)
    }

    private func severityColor(_ s: InvestigationSeverity) -> Color {
        switch s {
        case .low: return Theme.electricAzure
        case .medium: return Theme.solarAmber
        case .high: return Theme.pulseCrimson
        case .critical: return Theme.quantumViolet
        }
    }
}
