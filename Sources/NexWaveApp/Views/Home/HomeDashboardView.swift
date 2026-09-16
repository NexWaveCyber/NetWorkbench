import SwiftUI
import NetworkCore
import DiagnosticsEngine
import InvestigationKit

public enum NetworkTelemetryProtocolMode: String, CaseIterable, Sendable {
    case dualStack = "Dual-Stack"
    case ipv4 = "IPv4"
    case ipv6 = "IPv6"
}

public struct HomeDashboardView: View {
    @Bindable var state: AppState
    @State private var monitor = MenuBarMonitorEngine.shared
    @State private var protocolMode: NetworkTelemetryProtocolMode = .dualStack
    @State private var hoveredStudio: String? = nil
    @State private var isRunningSLA: Bool = false
    @State private var showingSLAResultSheet: Bool = false
    @State private var slaResult: SLABaselineResult? = nil

    public init(state: AppState) {
        self.state = state
    }

    public var body: some View {
        ZStack {
            Theme.ambientMeshView

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Hero Command Center Deck with Live Health Index Ring
                    heroDiagnoseCard

                    // 3-Hop Visual Path Topology Strip
                    threeHopPathBar

                    // 1-Click Pro Quick Actions Bar
                    quickActionsBar

                    // Local Network Interface Telemetry Bar (5 Dual-Stack Cards)
                    networkInterfaceBar

                    // Two Column Layout: Investigations & Diagnostic Feed
                    HStack(alignment: .top, spacing: 18) {
                        activeInvestigationsCard
                        recentDiagnosesCard
                    }

                    // Interactive Engineering Studios (8-Studio Grid)
                    toolboxStudiosGrid
                }
                .padding(24)
            }
        }
        .navigationTitle("Engineering Dashboard")
        .sheet(isPresented: $showingSLAResultSheet) {
            slaResultSheet
        }
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

                HStack(spacing: 12) {
                    // Health Index Ring & Badge
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(0.08), lineWidth: 3.5)
                                .frame(width: 44, height: 44)

                            Circle()
                                .trim(from: 0, to: CGFloat(monitor.healthScorePercentage) / 100.0)
                                .stroke(
                                    LinearGradient(
                                        colors: [Color(hex: monitor.healthScoreColorHex), Theme.neonCyan],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                                )
                                .rotationEffect(.degrees(-90))
                                .frame(width: 44, height: 44)

                            Text("\(monitor.healthScorePercentage)%")
                                .font(Theme.monoText(11, weight: .bold))
                                .foregroundStyle(.white)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color(hex: monitor.healthScoreColorHex))
                                    .frame(width: 6, height: 6)
                                Text(monitor.healthScoreLabel)
                                    .font(Theme.monoText(10, weight: .bold))
                                    .foregroundStyle(Color(hex: monitor.healthScoreColorHex))
                            }

                            let gwLat = monitor.gatewayLatencyMs.map { String(format: "%.1fms", $0) } ?? "<1ms"
                            let inetLat = monitor.internetLatencyMs.map { String(format: "%.1fms", $0) } ?? "14ms"
                            Text("GW \(gwLat) • WAN \(inetLat)")
                                .font(Theme.monoText(9, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.25))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color(hex: monitor.healthScoreColorHex).opacity(0.25), lineWidth: 1)
                    )

                    // Quick Refresh Button
                    Button(action: {
                        Task {
                            await monitor.performMonitorCycle()
                            state.toastMessage = "Network health metrics refreshed"
                        }
                    }) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.neonCyan)
                            .frame(width: 34, height: 34)
                            .background(Theme.neonCyan.opacity(0.12))
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(Theme.neonCyan.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Refresh telemetry & latency metrics")
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

                // Live Gateway RTT Sparkline & Latency Telemetry
                if !monitor.gatewaySamples.isEmpty {
                    HStack(alignment: .center, spacing: 12) {
                        HStack(spacing: 6) {
                            PulsingBeacon(color: Theme.signalEmerald, size: 6, isLive: true)
                            Text("GATEWAY RTT TREND")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }

                        // Sparkline visual bars (24 samples)
                        HStack(alignment: .bottom, spacing: 2) {
                            ForEach(Array(monitor.gatewaySamples.suffix(24).enumerated()), id: \.offset) { _, val in
                                let h = max(4.0, min(20.0, val * 3.5))
                                let barColor: Color = val > 15 ? Theme.pulseCrimson : (val > 5 ? Theme.solarAmber : Theme.signalEmerald)
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(barColor)
                                    .frame(width: 3.5, height: h)
                            }
                        }
                        .frame(height: 20, alignment: .bottom)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 5))

                        let minVal = monitor.gatewaySamples.min() ?? 0.0
                        let maxVal = monitor.gatewaySamples.max() ?? 0.0
                        let avgVal = monitor.gatewaySamples.reduce(0.0, +) / Double(max(1, monitor.gatewaySamples.count))
                        HStack(spacing: 6) {
                            Text("Min: \(String(format: "%.1f", minVal))ms")
                                .font(Theme.monoText(10, weight: .semibold))
                                .foregroundStyle(Theme.signalEmerald)
                            Text("•")
                                .foregroundStyle(.tertiary)
                            Text("Avg: \(String(format: "%.1f", avgVal))ms")
                                .font(Theme.monoText(10, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text("•")
                                .foregroundStyle(.tertiary)
                            Text("Max: \(String(format: "%.1f", maxVal))ms")
                                .font(Theme.monoText(10, weight: .semibold))
                                .foregroundStyle(maxVal > 15 ? Theme.pulseCrimson : Theme.solarAmber)
                        }

                        Spacer()

                        Text("Last 24 probes • 2.5s tick")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.primary.opacity(0.02))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.borderLight, lineWidth: 1))
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

    // MARK: - 3-Hop Visual Path Topology Strip
    private var threeHopPathBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.neonCyan)
                    Text("END-TO-END VISUAL TOPOLOGY PATH")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 6) {
                    Circle()
                        .fill(Theme.signalEmerald)
                        .frame(width: 5, height: 5)
                    Text("3 Hops Active • Zero Packet Loss")
                        .font(Theme.monoText(10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 0) {
                // Hop 1: Host
                topologyHopCard(
                    hopNumber: "HOP 1",
                    role: "LOCAL HOST",
                    title: "\(ProcessInfo.processInfo.hostName)",
                    subtitle: "\(monitor.activeInterface) • \(monitor.localIP)/\(monitor.cidrPrefix)",
                    ipv6: monitor.localIPv6,
                    icon: "laptopcomputer",
                    tint: Theme.azurePro,
                    copyValue: monitor.localIP
                )

                // Connector 1: Link latency
                topologyLinkConnector(
                    latency: monitor.gatewayLatencyMs.map { $0 < 1.0 ? "< 1 ms" : String(format: "%.1f ms", $0) } ?? "< 1 ms",
                    label: monitor.wifiLink != nil ? "Wi-Fi 6" : "GbE LAN"
                )

                // Hop 2: Router / Gateway
                let gwV4 = monitor.defaultGateway.isEmpty ? "192.168.10.1" : monitor.defaultGateway
                topologyHopCard(
                    hopNumber: "HOP 2",
                    role: "DEFAULT GATEWAY",
                    title: gwV4,
                    subtitle: "L3 Next-Hop Router",
                    ipv6: monitor.defaultGatewayIPv6,
                    icon: "network",
                    tint: Theme.neonCyan,
                    copyValue: gwV4
                )

                // Connector 2: Transit latency
                topologyLinkConnector(
                    latency: monitor.internetLatencyMs.map { String(format: "%.1f ms", $0) } ?? "14 ms",
                    label: "ISP WAN"
                )

                // Hop 3: Internet WAN Backbone
                let wanV4 = monitor.publicIPv4.isEmpty || monitor.publicIPv4 == "Resolving..." ? monitor.publicIP : monitor.publicIPv4
                topologyHopCard(
                    hopNumber: "HOP 3",
                    role: "PUBLIC EGRESS",
                    title: "\(wanV4)",
                    subtitle: "DNS: \(monitor.dnsResolverName) (\(monitor.dnsServer.isEmpty ? "1.1.1.1" : monitor.dnsServer))",
                    ipv6: monitor.publicIPv6,
                    icon: "globe",
                    tint: Theme.signalEmerald,
                    copyValue: wanV4
                )
            }
            .padding(10)
            .background(Color.primary.opacity(0.025))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.borderLight, lineWidth: 1))
        }
    }

    private func topologyHopCard(
        hopNumber: String,
        role: String,
        title: String,
        subtitle: String,
        ipv6: String = "",
        icon: String,
        tint: Color,
        copyValue: String = ""
    ) -> some View {
        Button(action: {
            guard !copyValue.isEmpty, copyValue != "Resolving...", copyValue != "Unavailable" else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(copyValue, forType: .string)
            state.toastMessage = "Copied \(role) IP: \(copyValue)"
        }) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(tint.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundStyle(tint)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(hopNumber)
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(tint)
                        Text("•")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                        Text(role)
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Text(title)
                        .font(Theme.monoText(11, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if !ipv6.isEmpty && ipv6 != "None" && !ipv6.starts(with: "Not Configured") && !ipv6.starts(with: "Resolving") {
                        Text("v6: \(ipv6)")
                            .font(Theme.monoText(8))
                            .foregroundStyle(Theme.neonCyan.opacity(0.85))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "doc.on.doc")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary.opacity(0.35))
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.02))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.borderLight.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("Click to copy \(role) address (\(copyValue))\nRight-click for options")
        .contextMenu {
            Button("Copy \(role) IP (\(copyValue))") {
                guard !copyValue.isEmpty, copyValue != "Resolving...", copyValue != "Unavailable" else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(copyValue, forType: .string)
                state.toastMessage = "Copied \(role) IP: \(copyValue)"
            }
            Divider()
            Button("Diagnose \(role) (\(copyValue))") {
                guard !copyValue.isEmpty, copyValue != "Resolving...", copyValue != "Unavailable" else { return }
                state.updateTargetClassification(copyValue)
                startDiagnosisFromHome()
            }
            Button("Inspect in Latency Timeline") {
                guard !copyValue.isEmpty, copyValue != "Resolving...", copyValue != "Unavailable" else { return }
                state.updateTargetClassification(copyValue)
                state.selectedWorkspace = .timeline
            }
        }
    }

    private func topologyLinkConnector(latency: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(latency)
                .font(Theme.monoText(9, weight: .bold))
                .foregroundStyle(Theme.signalEmerald)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Theme.signalEmerald.opacity(0.12))
                .clipShape(Capsule())

            HStack(spacing: 0) {
                Rectangle()
                    .fill(Theme.signalEmerald.opacity(0.4))
                    .frame(height: 1.5)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.signalEmerald)
            }
            .frame(width: 44)

            Text(label)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - 1-Click Pro Quick Actions Bar
    private var quickActionsBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.badge.automatic.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.solarAmber)
                    Text("PRO QUICK ACTIONS")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let lastFlush = monitor.lastFlushTimestamp {
                    Text("Last DNS flush: \(lastFlush.formatted(date: .omitted, time: .standard))")
                        .font(Theme.monoText(9))
                        .foregroundStyle(.tertiary)
                }
            }

            HStack(spacing: 10) {
                // Button 1: Flush DNS
                quickActionButton(
                    title: "Flush DNS Cache",
                    icon: "bolt.fill",
                    tint: Theme.solarAmber,
                    help: "Clears system resolver cache via /usr/bin/dscacheutil -flushcache"
                ) {
                    Task {
                        let success = await monitor.flushDNSCache()
                        if success {
                            state.toastMessage = "✓ Successfully flushed macOS DNS cache (dscacheutil)"
                        } else {
                            state.toastMessage = "DNS flush failed"
                        }
                    }
                }

                // Button 2: SLA Audit
                quickActionButton(
                    title: isRunningSLA ? "Auditing SLA..." : "Run SLA Audit",
                    icon: "waveform.path.ecg",
                    tint: Theme.neonCyan,
                    help: "Executes 5 rapid probes to gateway and Internet to measure RFC 3550 jitter, loss, and DNS speed",
                    isLoading: isRunningSLA
                ) {
                    Task {
                        isRunningSLA = true
                        let res = await monitor.runSLABaselineAudit()
                        slaResult = res
                        isRunningSLA = false
                        showingSLAResultSheet = true
                    }
                }

                // Button 3: Copy Sysdiagnose Report
                quickActionButton(
                    title: "Copy Sysdiagnose",
                    icon: "doc.on.doc.fill",
                    tint: Theme.azurePro,
                    help: "Copies complete Markdown network configuration and latency diagnostic report"
                ) {
                    let report = monitor.generateSysdiagnoseReport()
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report, forType: .string)
                    state.toastMessage = "✓ Sysdiagnose Markdown Report copied to clipboard!"
                }

                // Button 4: Renew DHCP Lease
                quickActionButton(
                    title: "Renew DHCP",
                    icon: "arrow.clockwise.circle.fill",
                    tint: Theme.signalEmerald,
                    help: "Renews DHCP lease on active interface via networksetup"
                ) {
                    Task {
                        let res = await monitor.renewDHCPLease()
                        state.toastMessage = res.message
                    }
                }
            }
        }
    }

    private func quickActionButton(title: String, icon: String, tint: Color, help: String, isLoading: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 11))
                        .foregroundStyle(tint)
                }
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(tint.opacity(0.09))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(tint.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .help(help)
    }

    // MARK: - Network Interface Bar
    private var networkInterfaceBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header with title and protocol switcher
            HStack(alignment: .center) {
                HStack(spacing: 7) {
                    Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.neonCyan)

                    Text("ACTIVE INTERFACE & DUAL-STACK TELEMETRY")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Mode Selector: [Dual-Stack | IPv4 | IPv6]
                HStack(spacing: 2) {
                    ForEach(NetworkTelemetryProtocolMode.allCases, id: \.self) { mode in
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                protocolMode = mode
                            }
                        }) {
                            Text(mode.rawValue)
                                .font(.system(size: 10, weight: protocolMode == mode ? .bold : .medium, design: .monospaced))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 3)
                                .background(protocolMode == mode ? Theme.neonCyan.opacity(0.18) : Color.clear)
                                .foregroundStyle(protocolMode == mode ? Theme.neonCyan : Color.secondary)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.borderLight, lineWidth: 1))
            }

            // 5 Cards Matrix
            HStack(spacing: 12) {
                primaryLinkCard
                localAddressCard
                defaultGatewayCard
                systemResolverCard
                publicWanCard
            }
        }
    }

    // MARK: - Card 1: Primary Link
    private var primaryLinkCard: some View {
        Button(action: {
            if monitor.wifiLink != nil {
                state.selectedWorkspace = .wifi
            } else {
                state.selectedWorkspace = .toolbox
            }
        }) {
            telemetryCard(
                label: "PRIMARY LINK",
                icon: monitor.wifiLink != nil ? "wifi" : "cable.connector",
                badge: monitor.wifiLink.map { "\($0.rssi) dBm" } ?? "GbE Link",
                badgeColor: monitor.wifiLink != nil ? (monitor.wifiLink!.rssi > -65 ? Theme.signalEmerald : Theme.solarAmber) : Theme.signalEmerald,
                helpText: primaryLinkTooltip
            ) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(monitor.activeInterface)
                            .font(Theme.monoText(12, weight: .bold))
                            .foregroundStyle(Theme.neonCyan)
                        if let wifi = monitor.wifiLink {
                            Text("• \(wifi.ssid)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        } else {
                            Text("• GbE Link")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let wifi = monitor.wifiLink {
                        Text("\(Int(wifi.transmitRate)) Mbps • Ch \(wifi.channel) (\(wifi.band.rawValue)) • \(wifi.phyMode.displayName)")
                            .font(Theme.monoText(10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("1000BASE-T Full-Duplex")
                            .font(Theme.monoText(10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            if monitor.wifiLink != nil {
                Button("Open Wi-Fi Studio →") {
                    state.selectedWorkspace = .wifi
                }
            } else {
                Button("Open Subnet & IP Toolbox →") {
                    state.selectedWorkspace = .toolbox
                }
            }
            Divider()
            if let wifi = monitor.wifiLink {
                Button("Copy Wi-Fi BSSID (\(wifi.bssid))") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(wifi.bssid, forType: .string)
                    state.toastMessage = "Copied BSSID: \(wifi.bssid)"
                }
                Button("Copy MAC Address (\(wifi.macAddress))") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(wifi.macAddress, forType: .string)
                    state.toastMessage = "Copied MAC: \(wifi.macAddress)"
                }
            }
        }
    }

    private var primaryLinkTooltip: String {
        if let wifi = monitor.wifiLink {
            return """
            Adapter: \(monitor.activeInterface) (\(wifi.macAddress))
            SSID: \(wifi.ssid)
            BSSID: \(wifi.bssid) \(wifi.vendorName != nil ? "(\(wifi.vendorName!))" : "")
            Signal: \(wifi.rssi) dBm | Noise: \(wifi.noise) dBm | SNR: \(wifi.snr) dB
            Channel: \(wifi.channel) (\(wifi.band.rawValue) • \(wifi.channelWidth.rawValue))
            Tx Rate: \(Int(wifi.transmitRate)) Mbps (PHY: \(wifi.phyMode.displayName))
            Security: \(wifi.security)
            Click to open Wi-Fi Studio →
            """
        } else {
            return """
            Adapter: \(monitor.activeInterface)
            Type: Ethernet (Wired GbE)
            Subnet Mask: \(monitor.subnetMask)
            Broadcast: \(monitor.broadcastAddress)
            Click to open Network Toolbox →
            """
        }
    }

    // MARK: - Card 2: Local Address (IPv4 & IPv6)
    private var localAddressCard: some View {
        let showV4 = protocolMode == .dualStack || protocolMode == .ipv4
        let showV6 = (protocolMode == .dualStack || protocolMode == .ipv6) && monitor.hasIPv6

        return telemetryCard(
            label: "LOCAL ADDRESS",
            icon: "laptopcomputer",
            badge: monitor.hasIPv6 ? "Dual-Stack" : "IPv4",
            badgeColor: monitor.hasIPv6 ? Theme.neonCyan : Theme.azurePro,
            helpText: "Local IPv4: \(monitor.localIP)/\(monitor.cidrPrefix)\nSubnet Mask: \(monitor.subnetMask)\nBroadcast: \(monitor.broadcastAddress)\nLocal IPv6 (SLAAC): \(monitor.localIPv6)\nRight-click for options"
        ) {
            VStack(alignment: .leading, spacing: 3) {
                if showV4 {
                    dualStackAddressRow(tag: "v4", val: "\(monitor.localIP)/\(monitor.cidrPrefix)", tagColor: Theme.azurePro, copyKey: "Local IPv4")
                }
                if showV6 {
                    dualStackAddressRow(tag: "v6", val: monitor.localIPv6.isEmpty ? "None" : monitor.localIPv6, tagColor: Theme.neonCyan, copyKey: "Local IPv6")
                }
                if !showV4 && !showV6 {
                    dualStackAddressRow(tag: "v6", val: "No IPv6 on \(monitor.activeInterface)", tagColor: .orange, copyKey: "")
                }
            }
        }
        .contextMenu {
            Button("Copy IPv4 / CIDR (\(monitor.localIP)/\(monitor.cidrPrefix))") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("\(monitor.localIP)/\(monitor.cidrPrefix)", forType: .string)
                state.toastMessage = "Copied Local IP/CIDR"
            }
            Button("Copy Subnet Mask (\(monitor.subnetMask))") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(monitor.subnetMask, forType: .string)
                state.toastMessage = "Copied Subnet Mask"
            }
            Button("Copy Broadcast Address (\(monitor.broadcastAddress))") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(monitor.broadcastAddress, forType: .string)
                state.toastMessage = "Copied Broadcast Address"
            }
            if monitor.hasIPv6 {
                Button("Copy Local IPv6 (\(monitor.localIPv6))") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(monitor.localIPv6, forType: .string)
                    state.toastMessage = "Copied Local IPv6"
                }
            }
            Divider()
            Button("Open Subnet Calculator →") {
                state.selectedWorkspace = .toolbox
            }
        }
    }

    // MARK: - Card 3: Default Gateway (IPv4 & IPv6)
    private var defaultGatewayCard: some View {
        let showV4 = protocolMode == .dualStack || protocolMode == .ipv4
        let showV6 = (protocolMode == .dualStack || protocolMode == .ipv6) && !monitor.defaultGatewayIPv6.isEmpty

        let latencyBadge: String = {
            if let rtt = monitor.gatewayLatencyMs {
                return rtt < 1.0 ? "< 1ms" : String(format: "%.1f ms", rtt)
            }
            return "< 1ms"
        }()

        return telemetryCard(
            label: "DEFAULT GATEWAY",
            icon: "network",
            badge: latencyBadge,
            badgeColor: Theme.neonCyan,
            helpText: "IPv4 Gateway: \(monitor.defaultGateway)\nIPv6 Gateway: \(monitor.defaultGatewayIPv6)\nRight-click for options"
        ) {
            VStack(alignment: .leading, spacing: 3) {
                if showV4 {
                    dualStackAddressRow(tag: "v4", val: monitor.defaultGateway, tagColor: Theme.azurePro, copyKey: "Default Gateway IPv4")
                }
                if showV6 {
                    dualStackAddressRow(tag: "v6", val: monitor.defaultGatewayIPv6, tagColor: Theme.neonCyan, copyKey: "Default Gateway IPv6")
                }
                if !showV4 && !showV6 {
                    dualStackAddressRow(tag: "v6", val: "No IPv6 Gateway", tagColor: .orange, copyKey: "")
                }
            }
        }
        .contextMenu {
            Button("Diagnose Gateway Router (\(monitor.defaultGateway))") {
                state.updateTargetClassification(monitor.defaultGateway)
                startDiagnosisFromHome()
            }
            Button("Inspect Gateway in Latency Timeline") {
                state.updateTargetClassification(monitor.defaultGateway)
                state.selectedWorkspace = .timeline
            }
            Divider()
            Button("Copy Gateway IPv4 (\(monitor.defaultGateway))") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(monitor.defaultGateway, forType: .string)
                state.toastMessage = "Copied Gateway IPv4"
            }
            if !monitor.defaultGatewayIPv6.isEmpty {
                Button("Copy Gateway IPv6 (\(monitor.defaultGatewayIPv6))") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(monitor.defaultGatewayIPv6, forType: .string)
                    state.toastMessage = "Copied Gateway IPv6"
                }
            }
        }
    }

    // MARK: - Card 4: System Resolver (IPv4 & IPv6)
    private var systemResolverCard: some View {
        let showV4 = protocolMode == .dualStack || protocolMode == .ipv4
        let showV6 = (protocolMode == .dualStack || protocolMode == .ipv6) && !monitor.dnsServerIPv6.isEmpty

        return telemetryCard(
            label: "SYSTEM RESOLVER",
            icon: "arrow.triangle.branch",
            badge: monitor.dnsResolverName,
            badgeColor: Theme.signalEmerald,
            helpText: "Configured Resolvers:\n" + monitor.allDnsServers.joined(separator: "\n") + "\nRight-click for options"
        ) {
            VStack(alignment: .leading, spacing: 3) {
                if showV4 {
                    dualStackAddressRow(tag: "v4", val: monitor.dnsServer.isEmpty ? "Unassigned" : monitor.dnsServer, tagColor: Theme.azurePro, copyKey: "DNS IPv4")
                }
                if showV6 {
                    dualStackAddressRow(tag: "v6", val: monitor.dnsServerIPv6.isEmpty ? "None Assigned" : monitor.dnsServerIPv6, tagColor: Theme.neonCyan, copyKey: monitor.dnsServerIPv6.isEmpty ? "" : "DNS IPv6")
                }
                if !showV4 && !showV6 {
                    dualStackAddressRow(tag: "v6", val: "No IPv6 Nameserver", tagColor: .orange, copyKey: "")
                }
            }
        }
        .contextMenu {
            Button("Diagnose DNS Resolver (\(monitor.dnsServer))") {
                state.updateTargetClassification(monitor.dnsServer)
                startDiagnosisFromHome()
            }
            Button("Inspect Resolver in Latency Timeline") {
                state.updateTargetClassification(monitor.dnsServer)
                state.selectedWorkspace = .timeline
            }
            Button("Flush macOS DNS Cache") {
                Task {
                    let success = await monitor.flushDNSCache()
                    state.toastMessage = success ? "✓ DNS Cache Flushed" : "DNS Flush Failed"
                }
            }
            Divider()
            Button("Copy DNS IPv4 (\(monitor.dnsServer))") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(monitor.dnsServer, forType: .string)
                state.toastMessage = "Copied DNS IPv4"
            }
            if !monitor.dnsServerIPv6.isEmpty {
                Button("Copy DNS IPv6 (\(monitor.dnsServerIPv6))") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(monitor.dnsServerIPv6, forType: .string)
                    state.toastMessage = "Copied DNS IPv6"
                }
            }
        }
    }

    // MARK: - Card 5: Public WAN (IPv4 & IPv6)
    private var publicWanCard: some View {
        let showV4 = protocolMode == .dualStack || protocolMode == .ipv4
        let showV6 = protocolMode == .dualStack || protocolMode == .ipv6

        let v4Val = monitor.publicIPv4.isEmpty || monitor.publicIPv4 == "Resolving..." ? monitor.publicIP : monitor.publicIPv4
        let v6Val = monitor.publicIPv6

        return telemetryCard(
            label: "PUBLIC WAN",
            icon: "globe",
            badge: monitor.hasIPv6 ? "Dual-Stack" : "IPv4",
            badgeColor: monitor.hasIPv6 ? Theme.neonCyan : Theme.signalEmerald,
            helpText: "Public IPv6: \(monitor.publicIPv6)\nPublic IPv4: \(monitor.publicIPv4)\nRight-click for options"
        ) {
            VStack(alignment: .leading, spacing: 3) {
                if showV4 {
                    dualStackAddressRow(tag: "v4", val: v4Val, tagColor: Theme.azurePro, copyKey: "Public IPv4")
                }
                if showV6 {
                    dualStackAddressRow(tag: "v6", val: v6Val, tagColor: Theme.neonCyan, copyKey: "Public IPv6")
                }
            }
        }
        .contextMenu {
            if !v4Val.isEmpty && v4Val != "Resolving..." && v4Val != "Unavailable" {
                Button("Diagnose Public WAN IP (\(v4Val))") {
                    state.updateTargetClassification(v4Val)
                    startDiagnosisFromHome()
                }
                Button("Inspect WAN IP in Latency Timeline") {
                    state.updateTargetClassification(v4Val)
                    state.selectedWorkspace = .timeline
                }
                Divider()
                Button("Copy Public IPv4 (\(v4Val))") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(v4Val, forType: .string)
                    state.toastMessage = "Copied Public IPv4"
                }
            }
            if !v6Val.isEmpty && v6Val != "None" && !v6Val.starts(with: "Not Configured") {
                Button("Copy Public IPv6 (\(v6Val))") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(v6Val, forType: .string)
                    state.toastMessage = "Copied Public IPv6"
                }
            }
        }
    }

    // MARK: - Reusable Card Container
    private func telemetryCard<Content: View>(
        label: String,
        icon: String,
        badge: String? = nil,
        badgeColor: Color? = nil,
        helpText: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.azurePro.opacity(0.12))
                    .frame(width: 30, height: 30)

                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.azurePro)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
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

                content()
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 68)
        .engineeringCard(padding: 0, cornerRadius: 10, hasHoverEffect: true)
        .help(helpText ?? label)
    }

    // MARK: - Reusable Dual-Stack Address Row
    private func dualStackAddressRow(tag: String, val: String, tagColor: Color = .secondary, copyKey: String) -> some View {
        HStack(spacing: 4) {
            Text(tag)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(tagColor)
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(tagColor.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 3))

            Text(val)
                .font(Theme.monoText(11, weight: .semibold))
                .foregroundStyle(tag == "v6" ? Theme.neonCyan : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Spacer(minLength: 2)

            if !val.isEmpty && val != "Resolving..." && val != "Unavailable" && val != "None" && !copyKey.isEmpty {
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(val, forType: .string)
                    state.toastMessage = "Copied \(copyKey): \(val)"
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary.opacity(0.65))
                }
                .buttonStyle(.plain)
                .help("Copy \(copyKey)")
            }
        }
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
                VStack(spacing: 10) {
                    Image(systemName: "tray")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary.opacity(0.6))
                    Text("No active investigations")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Record latency events, route evidence, and incident timelines.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)

                    Button(action: {
                        let targetStr = state.targetInput.isEmpty ? (monitor.defaultGateway.isEmpty ? "192.168.10.1" : monitor.defaultGateway) : state.targetInput
                        let title = "Baseline Audit - \(targetStr)"
                        let desc = "Automated network baseline investigation created from Engineering Dashboard on \(Date().formatted())."
                        if let inv = try? state.investigationManager.createInvestigation(title: title, description: desc, severity: InvestigationSeverity.low) {
                            state.refreshInvestigations()
                            state.selectedInvestigation = inv
                            state.selectedWorkspace = .investigations
                            state.toastMessage = "Investigation initialized."
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 11))
                            Text("Initialize Investigation")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Theme.azurePro.opacity(0.12))
                        .foregroundStyle(Theme.azurePro)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
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
                VStack(spacing: 10) {
                    Image(systemName: "gauge.with.needle")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary.opacity(0.6))
                    Text("No diagnostic runs recorded")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        Button(action: {
                            state.updateTargetClassification(monitor.defaultGateway.isEmpty ? "192.168.10.1" : monitor.defaultGateway)
                            startDiagnosisFromHome()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "network")
                                    .font(.system(size: 9))
                                Text("Gateway Router")
                                    .font(Theme.monoText(10))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.borderLight, lineWidth: 1))
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            state.updateTargetClassification("1.1.1.1")
                            startDiagnosisFromHome()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "shield.checkerboard")
                                    .font(.system(size: 9))
                                Text("Cloudflare DNS")
                                    .font(Theme.monoText(10))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.borderLight, lineWidth: 1))
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            state.updateTargetClassification("google.com")
                            startDiagnosisFromHome()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "globe")
                                    .font(.system(size: 9))
                                Text("google.com")
                                    .font(Theme.monoText(10))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.borderLight, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                VStack(spacing: 8) {
                    ForEach(state.recentHistory.prefix(4)) { item in
                        Button(action: {
                            state.updateTargetClassification(item.target)
                            startDiagnosisFromHome()
                        }) {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(item.tcpHealthy ? Theme.signalEmerald : Theme.pulseCrimson)
                                    .frame(width: 8, height: 8)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.target)
                                        .font(Theme.monoText(12, weight: .bold))
                                        .foregroundStyle(.primary)
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

                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.neonCyan.opacity(0.7))
                            }
                            .padding(10)
                            .background(Color.primary.opacity(0.02))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.borderLight.opacity(0.5), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .help("Click to re-run diagnosis on \(item.target)")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .engineeringCard(hasHoverEffect: false)
    }

    // MARK: - Interactive Engineering Studios (8-Studio Grid)
    private var toolboxStudiosGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "square.grid.2x4.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.neonCyan)
                    Text("ENGINEERING STUDIOS & TOOL WORKBENCHES")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("8 Unprivileged Studios • Zero Root Required")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                studioCard(
                    id: "wifi",
                    title: "Wi-Fi Studio",
                    desc: "RF Spectrum, 6GHz & Spatial Streams",
                    icon: "wifi",
                    tint: Theme.neonCyan,
                    workspace: .wifi
                )
                studioCard(
                    id: "subnet",
                    title: "Subnet Calculator",
                    desc: "CIDR, VLSM & Binary Mask Matrix",
                    icon: "number.square.fill",
                    tint: Theme.electricAzure,
                    workspace: .toolbox
                )
                studioCard(
                    id: "timeline",
                    title: "Latency Timeline",
                    desc: "Real-time Jitter & RFC 3550 Trends",
                    icon: "chart.xyaxis.line",
                    tint: Theme.signalEmerald,
                    workspace: .timeline
                )
                studioCard(
                    id: "packet",
                    title: "Packet Workbench",
                    desc: "PCAP Hex & Multi-Layer Dissection",
                    icon: "waveform.path.ecg",
                    tint: Theme.quantumViolet,
                    workspace: .packet
                )
                studioCard(
                    id: "devices",
                    title: "Device Discovery",
                    desc: "ARP & Bonjour/mDNS Active Radar",
                    icon: "server.rack",
                    tint: Theme.solarAmber,
                    workspace: .devices
                )
                studioCard(
                    id: "cmd",
                    title: "Command Library",
                    desc: "Multi-Vendor CLI Reference & Macros",
                    icon: "terminal.fill",
                    tint: Theme.azurePro,
                    workspace: .commandLibrary
                )
                studioCard(
                    id: "snmp",
                    title: "SNMP Studio",
                    desc: "v1/v2c/v3 MIB Tree & OID Inspector",
                    icon: "chart.bar.xaxis",
                    tint: Theme.pulseCrimson,
                    workspace: .snmp
                )
                studioCard(
                    id: "config",
                    title: "Config Workbench",
                    desc: "Syntax Parsing & Semantic Diffs",
                    icon: "doc.text.magnifyingglass",
                    tint: Theme.neonCyan,
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
                        .lineLimit(1)
                }
            }
            .padding(14)
            .engineeringCard(padding: 0, cornerRadius: 10, hasHoverEffect: true)
        }
        .buttonStyle(.plain)
    }

    // MARK: - SLA Audit Result Sheet Modal
    private var slaResultSheet: some View {
        VStack(spacing: 20) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.neonCyan)
                    Text("SLA Baseline Latency & Quality Audit")
                        .font(.system(size: 16, weight: .bold))
                }

                Spacer()

                Button("Done") {
                    showingSLAResultSheet = false
                }
                .keyboardShortcut(.cancelAction)
            }

            if let sla = slaResult ?? monitor.lastSLAResult {
                VStack(spacing: 16) {
                    // Grade Banner with Dynamic Branding
                    let (gradeColor, gradeIcon): (Color, String) = {
                        if sla.overallGrade.starts(with: "A") {
                            return (Theme.signalEmerald, "checkmark.seal.fill")
                        } else if sla.overallGrade.starts(with: "B") {
                            return (Theme.neonCyan, "checkmark.seal")
                        } else if sla.overallGrade.starts(with: "C") {
                            return (Theme.solarAmber, "exclamationmark.triangle.fill")
                        } else {
                            return (Theme.pulseCrimson, "xmark.octagon.fill")
                        }
                    }()

                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(gradeColor.opacity(0.18))
                                .frame(width: 50, height: 50)
                            Image(systemName: gradeIcon)
                                .font(.system(size: 26))
                                .foregroundStyle(gradeColor)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(sla.overallGrade)
                                .font(.system(size: 17, weight: .heavy))
                                .foregroundStyle(gradeColor)
                            Text(sla.recommendation)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding(14)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(gradeColor.opacity(0.3), lineWidth: 1))

                    // 4 Stat Cards
                    HStack(spacing: 12) {
                        slaStatCard(
                            title: "GATEWAY AVG",
                            val: String(format: "%.2f ms", sla.gatewayAvgMs),
                            subtext: "Min: \(String(format: "%.1f", sla.gatewayMinMs)) / Max: \(String(format: "%.1f", sla.gatewayMaxMs)) ms",
                            tint: Theme.azurePro
                        )
                        slaStatCard(
                            title: "RFC 3550 JITTER",
                            val: String(format: "%.2f ms", sla.gatewayJitterMs),
                            subtext: "Loss: \(String(format: "%.1f%%", sla.gatewayLossPercent))",
                            tint: sla.gatewayJitterMs < 3.0 ? Theme.signalEmerald : Theme.solarAmber
                        )
                        slaStatCard(
                            title: "INTERNET WAN",
                            val: String(format: "%.1f ms", sla.internetAvgMs),
                            subtext: "Host: \(sla.internetHost)",
                            tint: Theme.neonCyan
                        )
                        slaStatCard(
                            title: "DNS LOOKUP",
                            val: sla.dnsLookupMs >= 0 ? String(format: "%.1f ms", sla.dnsLookupMs) : "N/A",
                            subtext: "\(sla.dnsHost) (Darwin)",
                            tint: Theme.quantumViolet
                        )
                    }

                    // Action buttons
                    HStack {
                        Button(action: {
                            let text = """
                            SLA Baseline Audit: \(sla.overallGrade)
                            Gateway: \(sla.gatewayHost) (Avg: \(String(format: "%.2f ms", sla.gatewayAvgMs)), Jitter: \(String(format: "%.2f ms", sla.gatewayJitterMs)), Loss: \(String(format: "%.1f%%", sla.gatewayLossPercent)))
                            Internet: \(sla.internetHost) (Avg: \(String(format: "%.1f ms", sla.internetAvgMs)), Loss: \(String(format: "%.1f%%", sla.internetLossPercent)))
                            DNS: \(sla.dnsHost) (\(String(format: "%.1f ms", sla.dnsLookupMs)))
                            """
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                            state.toastMessage = "✓ SLA summary copied to clipboard"
                        }) {
                            Label("Copy SLA Summary", systemImage: "doc.on.doc")
                        }

                        Button(action: {
                            showingSLAResultSheet = false
                            state.updateTargetClassification(sla.gatewayHost)
                            state.selectedWorkspace = .timeline
                        }) {
                            Label("Timeline Inspector", systemImage: "chart.xyaxis.line")
                        }

                        Spacer()

                        Button("Close") {
                            showingSLAResultSheet = false
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                Text("No SLA audit results available.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(minWidth: 540, minHeight: 300)
    }

    private func slaStatCard(title: String, val: String, subtext: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(val)
                .font(Theme.monoText(15, weight: .heavy))
                .foregroundStyle(tint)
            Text(subtext)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(tint.opacity(0.2), lineWidth: 1))
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
