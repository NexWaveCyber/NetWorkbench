import SwiftUI
import AppKit
import NetworkCore
import DNSEngine
import DiagnosticsEngine
import TracerouteEngine
import InvestigationKit

public enum DiagnoseTab: String, CaseIterable, Identifiable {
    case all = "Comprehensive Overview"
    case path = "Path Topology"
    case dns = "DNS Records"
    case app = "TLS & HTTP Response"

    public var id: String { rawValue }
}

public struct DiagnoseWorkspaceView: View {
    @Bindable var state: AppState
    @State private var copiedMarkdown = false
    @State private var copiedJSON = false
    @State private var copiedRemediationId: String? = nil
    @State private var selectedTab: DiagnoseTab = .all
    @State private var headerSearchText: String = ""
    @State private var customPortInput: String = ""
    @State private var isShowingCustomPortPopover = false

    public init(state: AppState) {
        self.state = state
    }

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header Bar
            headerBar
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Theme.surfaceBackground)

            Divider()

            // MARK: - Content Area
            if state.isDiagnosing {
                progressView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let result = state.latestResult {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        overallStatusBanner(result: result)

                        // Segmented View Filter
                        Picker("View Mode", selection: $selectedTab) {
                            ForEach(DiagnoseTab.allCases) { tab in
                                Text(tab.rawValue).tag(tab)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 540)

                        switch selectedTab {
                        case .all:
                            findingsSection(result: result)
                            
                            if let lat = result.latency, lat.received > 0 {
                                LatencySparklineView(
                                    samples: lat.rawSamples.isEmpty ? [lat.minMs, lat.medianMs, lat.maxMs] : lat.rawSamples,
                                    minMs: lat.minMs,
                                    maxMs: lat.maxMs,
                                    medianMs: lat.medianMs,
                                    avgMs: lat.avgMs,
                                    p95Ms: lat.p95Ms
                                )
                                .engineeringCard()
                            }
                            
                            if let path = result.path, !path.hops.isEmpty {
                                PathTopologyView(hops: path.hops, latencyJumpHop: path.latencyJumpHop)
                            }
                            
                            multiLayerObservationsGrid(result: result)

                        case .path:
                            if let path = result.path {
                                PathTopologyView(hops: path.hops, latencyJumpHop: path.latencyJumpHop)
                                hopsTableView(path: path)
                            } else {
                                Text("No path hops recorded.")
                                    .foregroundStyle(.secondary)
                            }

                        case .dns:
                            dnsDetailView(result: result)

                        case .app:
                            httpDetailView(result: result)
                        }
                    }
                    .padding(20)
                }
            } else {
                emptyStateView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.secondaryBackground)
    }

    // MARK: - Header Bar
    private var headerBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.neonCyan.opacity(0.12))
                        .frame(width: 34, height: 34)

                    Image(systemName: "stethoscope")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.neonCyan)
                }

                // Main Target Input Field & Badges
                HStack(spacing: 8) {
                    TextField("Enter target host, IP, URL, or subnet...", text: $state.targetInput)
                        .textFieldStyle(.plain)
                        .font(Theme.monoText(14))
                        .onChange(of: state.targetInput) { _, newValue in
                            state.updateTargetClassification(newValue)
                        }
                        .onSubmit {
                            triggerDiagnosis()
                        }

                    // Target Type Capsule
                    if let target = state.classifiedTarget {
                        Text(target.targetType.rawValue)
                            .font(Theme.monoText(10, weight: .bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Theme.azurePro.opacity(0.15))
                            .foregroundStyle(Theme.azurePro)
                            .clipShape(Capsule())
                    }

                    // Port Selector Capsule
                    Menu {
                        Button("Default (443 - HTTPS)") { state.customPort = nil }
                        Button("Port 80 (HTTP)") { state.customPort = 80 }
                        Button("Port 53 (DNS)") { state.customPort = 53 }
                        Button("Port 853 (DNS-over-TLS)") { state.customPort = 853 }
                        Button("Port 22 (SSH)") { state.customPort = 22 }
                        Button("Port 8080 (Alt-HTTP)") { state.customPort = 8080 }
                        Divider()
                        Button("Custom Port...") {
                            isShowingCustomPortPopover = true
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "number")
                                .font(.system(size: 9, weight: .bold))
                            Text(portLabel)
                                .font(Theme.monoText(10, weight: .bold))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(state.customPort == nil ? Color.primary.opacity(0.06) : Theme.neonCyan.opacity(0.15))
                        .foregroundStyle(state.customPort == nil ? Color.secondary : Theme.neonCyan)
                        .clipShape(Capsule())
                    }
                    .menuStyle(.borderlessButton)
                    .popover(isPresented: $isShowingCustomPortPopover) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Specify Diagnostic Port")
                                .font(.system(size: 12, weight: .bold))
                            HStack {
                                TextField("e.g. 8443", text: $customPortInput)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 90)
                                Button("Apply") {
                                    if let p = UInt16(customPortInput) {
                                        state.customPort = p
                                    }
                                    isShowingCustomPortPopover = false
                                }
                                .keyboardShortcut(.defaultAction)
                            }
                        }
                        .padding(12)
                    }

                    // Recent History & Fleet Device Recall Menu
                    if !state.recentHistory.isEmpty || !state.managedDevices.isEmpty {
                        Menu {
                            if !state.managedDevices.isEmpty {
                                Section("Managed Fleet Inventory") {
                                    ForEach(state.managedDevices.prefix(6), id: \.id) { dev in
                                        Button("\(dev.name) (\(dev.managementIP))") {
                                            state.updateTargetClassification(dev.managementIP)
                                            triggerDiagnosis()
                                        }
                                    }
                                }
                            }

                            if !state.recentHistory.isEmpty {
                                Section("Recent Targets") {
                                    ForEach(state.recentHistory.prefix(8), id: \.id) { record in
                                        Button(record.target) {
                                            state.updateTargetClassification(record.target)
                                            triggerDiagnosis()
                                        }
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .menuStyle(.borderlessButton)
                        .help("Recall recent target or managed inventory device")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.borderLight, lineWidth: 1))

                // Diagnose Trigger Button
                Button(action: triggerDiagnosis) {
                    HStack(spacing: 6) {
                        if state.isDiagnosing {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "play.fill")
                                .font(.system(size: 11))
                        }
                        Text("Diagnose")
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(state.classifiedTarget == nil || state.isDiagnosing ? AnyShapeStyle(Color.gray.opacity(0.3)) : AnyShapeStyle(Theme.cyanGlowGradient))
                    .foregroundStyle(state.classifiedTarget == nil || state.isDiagnosing ? Color.secondary : Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(state.classifiedTarget == nil || state.isDiagnosing)
            }

            // Quick Targets
            HStack(spacing: 8) {
                Text("Quick Targets:")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                ForEach(["1.1.1.1", "google.com", "api.github.com", MenuBarMonitorEngine.shared.defaultGateway], id: \.self) { sample in
                    Button(action: {
                        state.updateTargetClassification(sample)
                        triggerDiagnosis()
                    }) {
                        Text(sample)
                            .font(Theme.monoText(11))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.primary.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.borderLight, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var portLabel: String {
        if let p = state.customPort {
            return "PORT \(p)"
        }
        if let t = state.classifiedTarget {
            return "PORT \(t.defaultPort.rawValue)"
        }
        return "PORT 443"
    }

    private func triggerDiagnosis() {
        guard let target = state.classifiedTarget else { return }
        Task {
            await state.runDiagnosis(target: target, port: state.customPort)
        }
    }

    // MARK: - Overall Status Banner
    private func overallStatusBanner(result: DiagnosticResult) -> some View {
        HStack(alignment: .top, spacing: 18) {
            ZStack {
                Circle()
                    .fill(statusColor(result.overallStatus).opacity(0.12))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Circle()
                            .strokeBorder(statusColor(result.overallStatus).opacity(0.35), lineWidth: 1.5)
                    )
                    .shadow(color: statusColor(result.overallStatus).opacity(0.25), radius: 8)

                Image(systemName: statusIcon(result.overallStatus))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(statusColor(result.overallStatus))
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    PulsingBeacon(color: statusColor(result.overallStatus), size: 7, isLive: true)

                    Text(result.overallStatus.rawValue)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(statusColor(result.overallStatus))

                    Text("•")
                        .foregroundStyle(.secondary)

                    Text(result.target.displayString)
                        .font(Theme.monoText(15, weight: .bold))

                    // Resolved IP Pill
                    if let firstIP = result.dns?.ipv4Addresses.first?.description ?? result.dns?.ipv6Addresses.first?.description {
                        HStack(spacing: 3) {
                            Text("IP: \(firstIP)")
                                .font(Theme.monoText(10.5, weight: .semibold))
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(firstIP, forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 9))
                            }
                            .buttonStyle(.plain)
                            .help("Copy target IP")
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Capsule())
                    }

                    // Wall-Clock Execution Time Badge
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.neonCyan)
                        Text(String(format: "%.1fs", result.executionDurationMs / 1000.0))
                            .font(Theme.monoText(10, weight: .bold))
                            .foregroundStyle(Theme.neonCyan)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(Theme.neonCyan.opacity(0.12))
                    .clipShape(Capsule())
                    .help("Total wall-clock pipeline duration (concurrent execution)")

                    Spacer()

                    // Export Markdown Button
                    Button(action: {
                        let md = AuditReportExporter.exportMarkdown(result: result)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(md, forType: .string)
                        copiedMarkdown = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            copiedMarkdown = false
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: copiedMarkdown ? "checkmark" : "doc.text")
                                .font(.system(size: 11, weight: .semibold))
                            Text(copiedMarkdown ? "MD Copied!" : "Export MD")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    // Export JSON Button
                    Button(action: {
                        let jsonStr = AuditReportExporter.exportJSON(result: result)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(jsonStr, forType: .string)
                        copiedJSON = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            copiedJSON = false
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: copiedJSON ? "checkmark" : "curlybraces")
                                .font(.system(size: 11, weight: .semibold))
                            Text(copiedJSON ? "JSON Copied!" : "Export JSON")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    // Create Investigation Button
                    Button(action: {
                        state.createInvestigationFromLatestResult()
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text("Create Investigation")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(Theme.cyanGlowGradient)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .shadow(color: Theme.neonCyan.opacity(0.25), radius: 6, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                }

                Text(result.overallSummary)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.primary.opacity(0.88))
            }
        }
        .glassHUDCard(padding: 18, cornerRadius: 12)
    }

    // MARK: - Findings Section
    private func findingsSection(result: DiagnosticResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("DETERMINISTIC ANALYTICAL FINDINGS & REMEDIATION")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(result.findings.count) Findings Evaluated")
                    .font(Theme.monoText(10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }

            VStack(spacing: 12) {
                ForEach(result.findings) { finding in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 12) {
                            Text(finding.classification.rawValue.uppercased())
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(classificationColor(finding.classification).opacity(0.14))
                                .foregroundStyle(classificationColor(finding.classification))
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .strokeBorder(classificationColor(finding.classification).opacity(0.3), lineWidth: 0.75)
                                )

                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(finding.title)
                                        .font(.system(size: 13, weight: .bold))

                                    Spacer()

                                    Text(finding.faultDomain)
                                        .font(Theme.monoText(10, weight: .semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.primary.opacity(0.04))
                                        .clipShape(Capsule())
                                        .foregroundStyle(.secondary)

                                    Text("•").foregroundStyle(.secondary)

                                    HStack(spacing: 3) {
                                        ForEach(0..<3) { idx in
                                            Circle()
                                                .fill(confidenceDotColor(idx: idx, conf: finding.confidence))
                                                .frame(width: 5, height: 5)
                                        }
                                        Text("\(finding.confidence.rawValue)")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Text(finding.statement)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.primary.opacity(0.88))
                            }
                        }

                        // Actionable Remediation Card
                        if let remediation = finding.remediation {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Image(systemName: "wrench.and.screwdriver.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Theme.neonCyan)
                                    Text("RECOMMENDED ACTIONABLE REMEDIATION")
                                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                        .foregroundStyle(Theme.neonCyan)
                                    Spacer()
                                    Button {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(remediation, forType: .string)
                                        copiedRemediationId = finding.id
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                            copiedRemediationId = nil
                                        }
                                    } label: {
                                        HStack(spacing: 3) {
                                            Image(systemName: copiedRemediationId == finding.id ? "checkmark" : "doc.on.doc")
                                                .font(.system(size: 8.5))
                                            Text(copiedRemediationId == finding.id ? "Copied" : "Copy")
                                                .font(.system(size: 8.5, weight: .semibold))
                                        }
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Theme.neonCyan.opacity(0.12))
                                        .foregroundStyle(Theme.neonCyan)
                                        .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }

                                Text(remediation)
                                    .font(Theme.monoText(11.5))
                                    .foregroundStyle(Color.primary.opacity(0.92))
                                    .lineSpacing(2)
                            }
                            .padding(10)
                            .background(Theme.neonCyan.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.neonCyan.opacity(0.2), lineWidth: 1))
                        }
                    }
                    .padding(12)
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.borderLight, lineWidth: 1))
                }
            }
        }
    }

    // MARK: - Multi-Layer Grid
    private func multiLayerObservationsGrid(result: DiagnosticResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MULTI-LAYER TELEMETRY OBSERVATIONS")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                // Layer 1: DNS
                observationCard(title: "Layer 7: DNS Resolution", icon: "arrow.triangle.branch", tint: Theme.azurePro) {
                    if let dns = result.dns {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Status")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                HStack(spacing: 5) {
                                    Text(dns.isHealthy ? "Healthy" : "Failed")
                                        .font(Theme.monoText(12, weight: .semibold))
                                        .foregroundStyle(dns.isHealthy ? Theme.signalEmerald : Theme.pulseCrimson)
                                    if dns.isDNSSECValidated {
                                        Text("DNSSEC")
                                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1.5)
                                            .background(Theme.signalEmerald.opacity(0.15))
                                            .foregroundStyle(Theme.signalEmerald)
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                            metricRow(label: "Query Time", value: String(format: "%.1f ms", dns.queryTimeMs))
                            
                            HStack {
                                Text("IPv4")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if let v4 = dns.ipv4Addresses.first?.description {
                                    HStack(spacing: 4) {
                                        Text(v4)
                                            .font(Theme.monoText(11.5, weight: .semibold))
                                        if dns.ipv4Addresses.count > 1 {
                                            Text("+\(dns.ipv4Addresses.count - 1)")
                                                .font(.system(size: 8.5, weight: .bold))
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(Color.primary.opacity(0.08))
                                                .clipShape(Capsule())
                                        }
                                        Button {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(v4, forType: .string)
                                        } label: {
                                            Image(systemName: "doc.on.doc").font(.system(size: 8.5))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                } else {
                                    Text("None").font(Theme.monoText(12)).foregroundStyle(.secondary)
                                }
                            }
                            
                            metricRow(label: "IPv6", value: dns.ipv6Addresses.first?.description ?? "None")
                        }
                    } else {
                        Text("Not applicable for direct IP").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }

                // Layer 2: Transport & Latency
                observationCard(title: "Layer 4: Transport & Latency", icon: "waveform.path.ecg", tint: Theme.neonCyan) {
                    if let lat = result.latency {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Probe Protocol")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(lat.lossPercentage < 100 ? Theme.signalEmerald : Theme.solarAmber)
                                        .frame(width: 5, height: 5)
                                    Text(lat.probeProtocol == .icmp ? "ICMP Echo" : "TCP Syn")
                                        .font(Theme.monoText(10.5, weight: .bold))
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.primary.opacity(0.06))
                                .clipShape(Capsule())
                            }

                            if lat.received > 0 {
                                metricRow(label: "Median RTT (P50)", value: String(format: "%.1f ms", lat.medianMs))
                                metricRow(label: "Min / Max / P95", value: "\(String(format: "%.1f", lat.minMs)) / \(String(format: "%.1f", lat.maxMs)) / \(String(format: "%.1f", lat.p95Ms)) ms")
                                metricRow(label: "RFC 3550 Jitter", value: String(format: "%.1f ms", lat.jitterMs))
                                metricRow(label: "Packet Loss", value: String(format: "%.0f%% (%d/%d)", lat.lossPercentage, lat.lost, lat.sent), isSuccess: lat.lossPercentage == 0)
                            } else {
                                metricRow(label: "ICMP Status", value: "100% Filtered / Dropped", isSuccess: false)
                                if let tcp = result.tcp, tcp.isSuccess {
                                    metricRow(label: "TCP Handshake", value: "\(String(format: "%.1f", tcp.latencyMs ?? 0)) ms (Service Open)", isSuccess: true)
                                }
                            }
                        }
                    } else {
                        Text("No latency samples available").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }

                // Layer 3: Path Traversal
                observationCard(title: "Layer 3: Path Routing", icon: "point.topleft.down.to.point.bottomright.curvepath", tint: Theme.solarAmber) {
                    if let path = result.path {
                        VStack(alignment: .leading, spacing: 6) {
                            metricRow(label: "Total Hops", value: "\(path.totalHops)")
                            metricRow(label: "Target Reached", value: path.finalHopReached ? "Yes" : "No", isSuccess: path.finalHopReached)
                            if let jump = path.latencyJumpHop, let delta = path.latencyDeltaMs {
                                metricRow(label: "Anomaly Spike", value: "+\(String(format: "%.0f", delta))ms at hop \(jump)")
                            } else {
                                metricRow(label: "Path Stability", value: "No anomalous RTT spikes")
                            }
                        }
                    } else {
                        Text("Path trace not executed").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }

                // Layer 4: TLS & Application
                observationCard(title: "Layer 7: TLS & Application", icon: "lock.shield", tint: Theme.quantumViolet) {
                    if let http = result.http {
                        VStack(alignment: .leading, spacing: 6) {
                            metricRow(label: "HTTP Status", value: "\(http.statusCode)", isSuccess: (200...399).contains(http.statusCode))
                            metricRow(label: "TTFB", value: http.ttfbMs != nil ? String(format: "%.1f ms", http.ttfbMs!) : "N/A")
                            if let cert = http.certificateInfo {
                                if cert.isSelfSigned || cert.isUntrusted {
                                    HStack {
                                        Text("Certificate Trust")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        HStack(spacing: 3) {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .font(.system(size: 8))
                                            Text("Self-Signed / Untrusted")
                                                .font(Theme.monoText(10, weight: .bold))
                                        }
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Theme.solarAmber.opacity(0.15))
                                        .foregroundStyle(Theme.solarAmber)
                                        .clipShape(Capsule())
                                    }
                                } else {
                                    metricRow(label: "Certificate Expiry", value: cert.daysUntilExpiry != nil ? "\(cert.daysUntilExpiry!) days" : "Valid", isSuccess: !cert.isExpired)
                                }
                            } else {
                                metricRow(label: "Security", value: "Plaintext HTTP / None")
                            }
                        }
                    } else {
                        Text("HTTP/TLS not probed").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func observationCard<Content: View>(title: String, icon: String, tint: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 13, weight: .bold))
            }
            Divider()
            content()
        }
        .engineeringCard(padding: 14)
    }

    private func metricRow(label: String, value: String, isSuccess: Bool? = nil) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(Theme.monoText(12, weight: .semibold))
                .foregroundStyle(isSuccess == true ? Theme.signalEmerald : (isSuccess == false ? Theme.pulseCrimson : Color.primary))
        }
    }

    // MARK: - Specialized Views
    private func hopsTableView(path: PathObservation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("HOP ROUTING TABLE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(path.hops.count) hops • Final: \(path.finalHopReached ? "Reached" : "Unreached")")
                    .font(Theme.monoText(10))
                    .foregroundStyle(.secondary)
            }

            Table(path.hops) {
                TableColumn("Hop") { hop in
                    Text("\(hop.hopNumber)")
                        .font(Theme.monoText(12, weight: .bold))
                }
                .width(45)

                TableColumn("IP Address") { hop in
                    HStack(spacing: 4) {
                        Text(hop.address ?? "* * *")
                            .font(Theme.monoText(12))
                            .foregroundStyle(hop.isTimeout ? .secondary : Color.primary)
                        if let addr = hop.address, addr != "* * *" {
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(addr, forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc").font(.system(size: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .width(180)

                TableColumn("ASN / Carrier") { hop in
                    if let asn = hop.asn {
                        Text("\(asn) \(hop.asName ?? "")")
                            .font(Theme.monoText(11))
                            .foregroundStyle(Theme.azurePro)
                    } else {
                        Text("-").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                .width(140)

                TableColumn("Round-Trip Time") { hop in
                    if let rtt = hop.rttMs {
                        Text(String(format: "%.1f ms", rtt))
                            .font(Theme.monoText(12))
                            .foregroundStyle(hop.hopNumber == path.latencyJumpHop ? Theme.solarAmber : Theme.neonCyan)
                    } else {
                        Text("Timeout").font(.system(size: 11)).foregroundStyle(Theme.pulseCrimson)
                    }
                }
                .width(110)

                TableColumn("Delta RTT") { hop in
                    if let delta = hop.deltaMs, delta > 0.5 {
                        Text(String(format: "+%.1f ms", delta))
                            .font(Theme.monoText(11, weight: .semibold))
                            .foregroundStyle(hop.hopNumber == path.latencyJumpHop ? Theme.solarAmber : .secondary)
                    } else {
                        Text("-").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                .width(85)

                TableColumn("Status") { hop in
                    if hop.isTimeout {
                        Text("Filtered / No ICMP").font(.system(size: 11)).foregroundStyle(.secondary)
                    } else if hop.hopNumber == path.latencyJumpHop {
                        Text("Latency Spike").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.solarAmber)
                    } else {
                        Text("Responded").font(.system(size: 11)).foregroundStyle(Theme.signalEmerald)
                    }
                }
            }
            .frame(minHeight: 220)
        }
        .engineeringCard()
    }

    private func dnsDetailView(result: DiagnosticResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let dns = result.dns {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text("DNS WIRE RECORDS (\(dns.records.count))")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)

                            if dns.isDNSSECValidated {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.shield.fill")
                                    Text("DNSSEC Validated (AD Flag)")
                                }
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2.5)
                                .background(Theme.signalEmerald.opacity(0.15))
                                .foregroundStyle(Theme.signalEmerald)
                                .clipShape(Capsule())
                            } else {
                                HStack(spacing: 4) {
                                    Image(systemName: "shield.slash")
                                    Text("Standard Resolution (Unsigned)")
                                }
                                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2.5)
                                .background(Color.primary.opacity(0.05))
                                .foregroundStyle(.secondary)
                                .clipShape(Capsule())
                            }
                        }

                        Text("Resolver: \(dns.resolverName) • Query time: \(String(format: "%.1f ms", dns.queryTimeMs))")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }

                Table(dns.records) {
                    TableColumn("Type") { rec in
                        Text(rec.type.rawValue)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(dnsTypeBadgeColor(rec.type).opacity(0.15))
                            .foregroundStyle(dnsTypeBadgeColor(rec.type))
                            .clipShape(Capsule())
                    }
                    .width(65)

                    TableColumn("Hostname") { rec in
                        Text(rec.name)
                            .font(Theme.monoText(11.5))
                            .foregroundStyle(.secondary)
                    }
                    .width(160)

                    TableColumn("Record Value") { rec in
                        HStack(spacing: 6) {
                            Text(rec.value)
                                .font(Theme.monoText(12))
                                .lineLimit(1)
                            Spacer()
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(rec.value, forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc").font(.system(size: 8.5))
                            }
                            .buttonStyle(.plain)
                            .help("Copy record value")
                        }
                    }

                    TableColumn("TTL") { rec in
                        Text("\(rec.ttl)s")
                            .font(Theme.monoText(11))
                            .foregroundStyle(.secondary)
                    }
                    .width(70)
                }
                .frame(minHeight: 220)
            }
        }
        .engineeringCard()
    }

    private func httpDetailView(result: DiagnosticResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let http = result.http {
                Text("HTTP & TLS PROTOCOL PERFORMANCE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    paramCell(label: "HTTP Status", val: "\(http.statusCode)", color: (200...399).contains(http.statusCode) ? Theme.signalEmerald : Theme.pulseCrimson)
                    paramCell(label: "Protocol Version", val: http.httpVersion ?? "HTTP/1.1")
                    paramCell(label: "Total Duration", val: String(format: "%.1f ms", http.totalTimeMs))
                    paramCell(label: "DNS Stage", val: http.dnsTimeMs != nil ? String(format: "%.1f ms", http.dnsTimeMs!) : "Cached")
                    paramCell(label: "TCP Handshake", val: http.connectTimeMs != nil ? String(format: "%.1f ms", http.connectTimeMs!) : "-")
                    paramCell(label: "TLS Handshake", val: http.tlsTimeMs != nil ? String(format: "%.1f ms", http.tlsTimeMs!) : "-")
                }

                if let cert = http.certificateInfo {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("X.509 SECURITY CERTIFICATE")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Spacer()
                            if cert.isSelfSigned || cert.isUntrusted {
                                HStack(spacing: 3) {
                                    Image(systemName: "exclamationmark.shield.fill")
                                    Text("Self-Signed / Untrusted")
                                }
                                .font(Theme.monoText(9.5, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.solarAmber.opacity(0.15))
                                .foregroundStyle(Theme.solarAmber)
                                .clipShape(Capsule())
                            }
                            if let proto = cert.protocolVersion {
                                Text(proto)
                                    .font(Theme.monoText(9.5, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Theme.signalEmerald.opacity(0.12))
                                    .foregroundStyle(Theme.signalEmerald)
                                    .clipShape(Capsule())
                            }
                            if let cipher = cert.cipherSuite {
                                Text(cipher)
                                    .font(Theme.monoText(9.5, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Theme.quantumViolet.opacity(0.12))
                                    .foregroundStyle(Theme.quantumViolet)
                                    .clipShape(Capsule())
                            }
                        }

                        Text("Subject: \(cert.subjectSummary)")
                            .font(Theme.monoText(12))
                        if cert.issuerSummary != cert.subjectSummary && !cert.issuerSummary.isEmpty {
                            Text("Issuer: \(cert.issuerSummary)")
                                .font(Theme.monoText(11))
                                .foregroundStyle(.secondary)
                        }

                        let expiryDesc: String = {
                            if let days = cert.daysUntilExpiry {
                                if days < 0 {
                                    return "(\(abs(days)) days overdue)"
                                } else if days == 0 {
                                    return "(Expires today)"
                                } else {
                                    return "(\(days) days remaining)"
                                }
                            }
                            return ""
                        }()

                        Text("Expires on: \(cert.expirationDate?.formatted(date: .abbreviated, time: .shortened) ?? "Unknown") \(expiryDesc)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(cert.isExpired ? Theme.pulseCrimson : Theme.signalEmerald)
                    }
                }

                // HTTP Response Headers Table
                if !http.headers.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("HTTP RESPONSE HEADERS (\(filteredHeaders(http.headers).count))")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)

                            Spacer()

                            HStack(spacing: 4) {
                                Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(.secondary)
                                TextField("Filter headers...", text: $headerSearchText)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 11))
                                    .frame(width: 140)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.primary.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.borderLight, lineWidth: 1))
                        }

                        Table(filteredHeaders(http.headers)) {
                            TableColumn("Header Name") { header in
                                Text(header.key)
                                    .font(Theme.monoText(11, weight: .bold))
                                    .foregroundStyle(Theme.neonCyan)
                            }
                            .width(180)

                            TableColumn("Header Value") { header in
                                HStack {
                                    Text(header.value)
                                        .font(Theme.monoText(11.5))
                                        .lineLimit(1)
                                    Spacer()
                                    Button {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(header.value, forType: .string)
                                    } label: {
                                        Image(systemName: "doc.on.doc").font(.system(size: 8.5))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .frame(minHeight: 180)
                    }
                }
            }
        }
        .engineeringCard()
    }

    private struct HeaderItem: Identifiable {
        var id: String { key }
        let key: String
        let value: String
    }

    private func filteredHeaders(_ headers: [String: String]) -> [HeaderItem] {
        let items = headers.map { HeaderItem(key: $0.key, value: $0.value) }
            .sorted(by: { $0.key < $1.key })
        if headerSearchText.isEmpty {
            return items
        }
        return items.filter {
            $0.key.localizedCaseInsensitiveContains(headerSearchText) ||
            $0.value.localizedCaseInsensitiveContains(headerSearchText)
        }
    }

    private func paramCell(label: String, val: String, color: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(val).font(Theme.monoText(13, weight: .bold)).foregroundStyle(color ?? Color.primary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func dnsTypeBadgeColor(_ type: DNSRecordType) -> Color {
        switch type {
        case .a: return Theme.azurePro
        case .aaaa: return Theme.neonCyan
        case .cname: return Theme.solarAmber
        case .mx: return Theme.quantumViolet
        case .txt: return Color.secondary
        default: return Color.primary
        }
    }

    // MARK: - Progress & Empty States
    private var progressView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Theme.neonCyan.opacity(0.1))
                    .frame(width: 80, height: 80)
                    .overlay(
                        Circle()
                            .stroke(Theme.neonCyan.opacity(0.3), lineWidth: 2)
                            .scaleEffect(1.3)
                    )

                Image(systemName: "radar")
                    .font(.system(size: 32))
                    .foregroundStyle(Theme.neonCyan)
            }

            VStack(spacing: 8) {
                Text(state.currentProgress?.stage.rawValue ?? "Diagnosing Target...")
                    .font(.system(size: 17, weight: .bold))

                Text(state.currentProgress?.message ?? "Running concurrent multi-layer deterministic diagnostics...")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: state.currentProgress?.percentage ?? 0.0)
                .progressViewStyle(.linear)
                .tint(Theme.neonCyan)
                .frame(width: 320)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Theme.neonCyan.opacity(0.08))
                    .frame(width: 88, height: 88)

                Image(systemName: "network.badge.shield.half.filled")
                    .font(.system(size: 42))
                    .foregroundStyle(Theme.neonCyan)
            }

            VStack(spacing: 6) {
                Text("NexWave Deterministic Diagnostic Engine")
                    .font(.system(size: 20, weight: .bold))

                Text("Enter a target hostname, IP, URL, or select a quick-launch diagnostic preset below to run comprehensive concurrent telemetry across DNS, TCP, Latency, Route Topology, and Application layers.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 500)
            }

            // Quick-Launch Preset Cards (4-grid)
            VStack(alignment: .leading, spacing: 10) {
                Text("RECOMMENDED DIAGNOSTIC PRESETS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    presetCard(
                        title: "Cloudflare Edge",
                        host: "1.1.1.1",
                        desc: "Global DNS root & anycast edge benchmark",
                        icon: "bolt.shield",
                        tint: Theme.neonCyan
                    )
                    presetCard(
                        title: "Google Public Core",
                        host: "google.com",
                        desc: "Dual-stack IPv4/IPv6 transit & HTTP/3 probe",
                        icon: "globe.americas.fill",
                        tint: Theme.azurePro
                    )
                    presetCard(
                        title: "GitHub API",
                        host: "api.github.com",
                        desc: "TLS 1.3 REST application endpoint check",
                        icon: "server.rack",
                        tint: Theme.quantumViolet
                    )
                    presetCard(
                        title: "Default Gateway",
                        host: MenuBarMonitorEngine.shared.defaultGateway,
                        desc: "First-hop router, ARP & local subnet health",
                        icon: "router",
                        tint: Theme.signalEmerald
                    )
                }
            }
            .frame(maxWidth: 580)
            .padding(.top, 8)
        }
        .padding(24)
    }

    private func presetCard(title: String, host: String, desc: String, icon: String, tint: Color) -> some View {
        Button {
            state.updateTargetClassification(host)
            triggerDiagnosis()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(tint.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(tint)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(title)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(tint)
                    }
                    Text(host)
                        .font(Theme.monoText(10, weight: .semibold))
                        .foregroundStyle(tint)
                    Text(desc)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(10)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.borderLight, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func statusColor(_ status: OverallHealthStatus) -> Color {
        switch status {
        case .healthy: return Theme.signalEmerald
        case .degraded: return Theme.solarAmber
        case .critical: return Theme.pulseCrimson
        case .unreachable: return Theme.pulseCrimson
        }
    }

    private func statusIcon(_ status: OverallHealthStatus) -> String {
        switch status {
        case .healthy: return "checkmark.shield.fill"
        case .degraded: return "exclamationmark.shield.fill"
        case .critical: return "xmark.shield.fill"
        case .unreachable: return "slash.circle.fill"
        }
    }

    private func classificationColor(_ c: FindingClassification) -> Color {
        switch c {
        case .observed: return Theme.electricAzure
        case .derived: return Theme.solarAmber
        case .inferred: return Theme.quantumViolet
        }
    }

    private func confidenceDotColor(idx: Int, conf: ConfidenceLevel) -> Color {
        switch conf {
        case .high:
            return Theme.signalEmerald
        case .medium:
            return idx < 2 ? Theme.solarAmber : Color.primary.opacity(0.15)
        case .low:
            return idx == 0 ? Theme.pulseCrimson : Color.primary.opacity(0.15)
        }
    }
}
