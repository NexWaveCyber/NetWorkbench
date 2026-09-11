import SwiftUI
import NetworkCore
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
    @State private var copiedReport = false
    @State private var selectedTab: DiagnoseTab = .all

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
                        .frame(maxWidth: 500)

                        switch selectedTab {
                        case .all:
                            findingsSection(result: result)
                            if let lat = result.latency, lat.received > 0 {
                                LatencySparklineView(
                                    samples: [lat.minMs, (lat.minMs + lat.medianMs)/2, lat.medianMs, (lat.medianMs + lat.maxMs)/2, lat.maxMs],
                                    minMs: lat.minMs,
                                    maxMs: lat.maxMs,
                                    medianMs: lat.medianMs
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
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.neonCyan.opacity(0.12))
                        .frame(width: 32, height: 32)

                    Image(systemName: "stethoscope")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.neonCyan)
                }

                HStack(spacing: 8) {
                    TextField("Enter target host, IP, URL, or subnet...", text: $state.targetInput)
                        .textFieldStyle(.plain)
                        .font(Theme.monoText(15))
                        .onChange(of: state.targetInput) { _, newValue in
                            state.updateTargetClassification(newValue)
                        }
                        .onSubmit {
                            triggerDiagnosis()
                        }

                    if let target = state.classifiedTarget {
                        Text(target.targetType.rawValue)
                            .font(Theme.monoText(10, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Theme.azurePro.opacity(0.15))
                            .foregroundStyle(Theme.azurePro)
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.borderLight, lineWidth: 1))

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

                ForEach(["google.com", "1.1.1.1", "api.github.com", "192.168.1.1"], id: \.self) { sample in
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

    private func triggerDiagnosis() {
        guard let target = state.classifiedTarget else { return }
        Task {
            await state.runDiagnosis(target: target)
        }
    }

    // MARK: - Overall Status Banner
    private func overallStatusBanner(result: DiagnosticResult) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle()
                    .fill(statusColor(result.overallStatus).opacity(0.15))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Circle()
                            .strokeBorder(statusColor(result.overallStatus), lineWidth: 2)
                    )
                    .shadow(color: statusColor(result.overallStatus).opacity(0.3), radius: 6)

                Image(systemName: statusIcon(result.overallStatus))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(statusColor(result.overallStatus))
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .center) {
                    Text(result.overallStatus.rawValue)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(statusColor(result.overallStatus))

                    Text("•")
                        .foregroundStyle(.secondary)

                    Text(result.target.displayString)
                        .font(Theme.monoText(15, weight: .bold))

                    Spacer()

                    Button(action: {
                        let md = AuditReportExporter.exportMarkdown(result: result)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(md, forType: .string)
                        copiedReport = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            copiedReport = false
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: copiedReport ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 11))
                            Text(copiedReport ? "Report Copied!" : "Export Report")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.borderLight, lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        state.createInvestigationFromLatestResult()
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 11))
                            Text("Create Investigation")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Theme.cyanGlowGradient)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .shadow(color: Theme.neonCyan.opacity(0.25), radius: 4)
                    }
                    .buttonStyle(.plain)
                }

                Text(result.overallSummary)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .engineeringCard(padding: 16)
    }

    // MARK: - Findings Section
    private func findingsSection(result: DiagnosticResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("DETERMINISTIC ANALYTICAL FINDINGS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(result.findings.count) Findings Identified")
                    .font(Theme.monoText(10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }

            VStack(spacing: 10) {
                ForEach(result.findings) { finding in
                    HStack(alignment: .top, spacing: 14) {
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
                            metricRow(label: "Status", value: dns.isHealthy ? "Healthy" : "Failed", isSuccess: dns.isHealthy)
                            metricRow(label: "Query Time", value: String(format: "%.1f ms", dns.queryTimeMs))
                            metricRow(label: "IPv4", value: dns.ipv4Addresses.first?.description ?? "None")
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
                            metricRow(label: "Median RTT", value: String(format: "%.1f ms", lat.medianMs))
                            metricRow(label: "Min / Max", value: "\(String(format: "%.1f", lat.minMs)) / \(String(format: "%.1f", lat.maxMs)) ms")
                            metricRow(label: "RFC 3550 Jitter", value: String(format: "%.1f ms", lat.jitterMs))
                            metricRow(label: "Packet Loss", value: String(format: "%.0f%% (%d/%d)", lat.lossPercentage, lat.lost, lat.sent), isSuccess: lat.lossPercentage == 0)
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
                                metricRow(label: "Anomaly", value: "+\(String(format: "%.0f", delta))ms at hop \(jump)")
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
                                metricRow(label: "Certificate Expiry", value: cert.daysUntilExpiry != nil ? "\(cert.daysUntilExpiry!) days" : "Valid", isSuccess: !cert.isExpired)
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
                .foregroundStyle(isSuccess == nil ? Color.primary : (isSuccess! ? Theme.signalEmerald : Theme.pulseCrimson))
        }
    }

    // MARK: - Specialized Views
    private func hopsTableView(path: PathObservation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HOP ROUTING TABLE")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)

            Table(path.hops) {
                TableColumn("Hop") { hop in
                    Text("\(hop.hopNumber)")
                        .font(Theme.monoText(12, weight: .bold))
                }
                .width(50)

                TableColumn("IP Address") { hop in
                    Text(hop.address ?? "* * *")
                        .font(Theme.monoText(12))
                        .foregroundStyle(hop.isTimeout ? .secondary : Color.primary)
                }
                .width(200)

                TableColumn("Round-Trip Time") { hop in
                    if let rtt = hop.rttMs {
                        Text(String(format: "%.1f ms", rtt))
                            .font(Theme.monoText(12))
                            .foregroundStyle(hop.hopNumber == path.latencyJumpHop ? Theme.solarAmber : Theme.neonCyan)
                    } else {
                        Text("Timeout").font(.system(size: 11)).foregroundStyle(Theme.pulseCrimson)
                    }
                }
                .width(120)

                TableColumn("Status") { hop in
                    if hop.isTimeout {
                        Text("Filtered / No ICMP").font(.system(size: 11)).foregroundStyle(.secondary)
                    } else if hop.hopNumber == path.latencyJumpHop {
                        Text("Latency Spike Detected").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.solarAmber)
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
                HStack {
                    Text("DNS RECORDS (\(dns.records.count))")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Resolver: \(dns.resolverName) (\(String(format: "%.1f", dns.queryTimeMs)) ms)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Table(dns.records) {
                    TableColumn("Type") { rec in
                        Text(rec.type.rawValue)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.azurePro.opacity(0.15))
                            .foregroundStyle(Theme.azurePro)
                            .clipShape(Capsule())
                    }
                    .width(65)

                    TableColumn("Value") { rec in
                        Text(rec.value)
                            .font(Theme.monoText(12))
                    }

                    TableColumn("TTL") { rec in
                        Text("\(rec.ttl)s")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .width(70)
                }
                .frame(minHeight: 200)
            }
        }
        .engineeringCard()
    }

    private func httpDetailView(result: DiagnosticResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let http = result.http {
                Text("HTTP & TLS PROTOCOL METRICS")
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
                        Text("X.509 CERTIFICATE DETAILS")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text("Subject: \(cert.subjectSummary)")
                            .font(Theme.monoText(12))
                        Text("Expires on: \(cert.expirationDate?.formatted() ?? "Unknown") (\(cert.daysUntilExpiry ?? 0) days remaining)")
                            .font(.system(size: 11))
                            .foregroundStyle(cert.isExpired ? Theme.pulseCrimson : Theme.signalEmerald)
                    }
                }
            }
        }
        .engineeringCard()
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

                Text(state.currentProgress?.message ?? "Running multi-layer deterministic diagnostics...")
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
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Theme.neonCyan.opacity(0.08))
                    .frame(width: 88, height: 88)

                Image(systemName: "network.badge.shield.half.filled")
                    .font(.system(size: 42))
                    .foregroundStyle(Theme.neonCyan)
            }

            VStack(spacing: 6) {
                Text("Global Diagnostic Engine")
                    .font(.system(size: 20, weight: .bold))

                Text("Enter a target hostname, IP address, URL, or subnet above to initiate a comprehensive multi-layer diagnosis.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
        }
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
