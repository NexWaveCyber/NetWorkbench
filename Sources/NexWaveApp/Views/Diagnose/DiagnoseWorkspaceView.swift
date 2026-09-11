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
                        .frame(maxWidth: 480)

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
                Image(systemName: "stethoscope")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.cyanPulse)

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
                            .font(.system(size: 11, weight: .semibold))
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
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderLight, lineWidth: 1))

                Button(action: triggerDiagnosis) {
                    HStack(spacing: 6) {
                        if state.isDiagnosing {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "play.fill")
                        }
                        Text("Diagnose")
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.classifiedTarget == nil || state.isDiagnosing)
            }

            // Quick Targets
            HStack(spacing: 8) {
                Text("Quick Targets:")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                ForEach(["google.com", "1.1.1.1", "api.github.com", "192.168.1.1"], id: \.self) { sample in
                    Button(sample) {
                        state.updateTargetClassification(sample)
                        triggerDiagnosis()
                    }
                    .buttonStyle(.plain)
                    .font(Theme.monoText(11))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
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
            Circle()
                .fill(statusColor(result.overallStatus))
                .frame(width: 14, height: 14)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
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
                        Label(copiedReport ? "Copied!" : "Copy Report", systemImage: copiedReport ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)

                    Button(action: {
                        state.createInvestigationFromLatestResult()
                    }) {
                        Label("Create Investigation", systemImage: "plus.circle.fill")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.borderedProminent)
                }

                Text(result.overallSummary)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .engineeringCard()
    }

    // MARK: - Findings Section
    private func findingsSection(result: DiagnosticResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ANALYTICAL FINDINGS")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(result.findings) { finding in
                    HStack(alignment: .top, spacing: 12) {
                        Text(finding.classification.rawValue.uppercased())
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(classificationColor(finding.classification).opacity(0.15))
                            .foregroundStyle(classificationColor(finding.classification))
                            .clipShape(RoundedRectangle(cornerRadius: 4))

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(finding.title)
                                    .font(.system(size: 13, weight: .semibold))

                                Spacer()

                                Text(finding.faultDomain)
                                    .font(.system(size: 11))
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
                                .foregroundStyle(Color.primary.opacity(0.9))
                        }
                    }
                    .padding(12)
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderLight, lineWidth: 1))
                }
            }
        }
    }

    // MARK: - Multi-Layer Grid
    private func multiLayerObservationsGrid(result: DiagnosticResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MULTI-LAYER OBSERVATIONS")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                // Layer 1: DNS
                observationCard(title: "DNS Resolution", icon: "arrow.triangle.branch") {
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
                observationCard(title: "Transport & Latency", icon: "waveform.path.ecg") {
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
                observationCard(title: "Path Traversal", icon: "point.topleft.down.to.point.bottomright.curvepath") {
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
                observationCard(title: "Application & TLS", icon: "lock.shield") {
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

    private func observationCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(Theme.azurePro)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
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
                .font(Theme.monoText(12, weight: .medium))
                .foregroundStyle(isSuccess == nil ? Color.primary : (isSuccess! ? Theme.emeraldHealthy : Theme.crimsonCritical))
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
                            .foregroundStyle(hop.hopNumber == path.latencyJumpHop ? Theme.amberWarning : Theme.cyanPulse)
                    } else {
                        Text("Timeout").font(.system(size: 11)).foregroundStyle(Theme.crimsonCritical)
                    }
                }
                .width(120)

                TableColumn("Status") { hop in
                    if hop.isTimeout {
                        Text("Filtered / No ICMP").font(.system(size: 11)).foregroundStyle(.secondary)
                    } else if hop.hopNumber == path.latencyJumpHop {
                        Text("Latency Spike Detected").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.amberWarning)
                    } else {
                        Text("Responded").font(.system(size: 11)).foregroundStyle(Theme.emeraldHealthy)
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
                            .background(Theme.azurePro.opacity(0.12))
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
                    paramCell(label: "HTTP Status", val: "\(http.statusCode)", color: (200...399).contains(http.statusCode) ? Theme.emeraldHealthy : Theme.crimsonCritical)
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
                            .foregroundStyle(cert.isExpired ? Theme.crimsonCritical : Theme.emeraldHealthy)
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
        VStack(spacing: 16) {
            ProgressView(value: state.currentProgress?.percentage ?? 0.0)
                .progressViewStyle(.linear)
                .frame(width: 320)

            VStack(spacing: 6) {
                Text(state.currentProgress?.stage.rawValue ?? "Diagnosing...")
                    .font(.system(size: 15, weight: .semibold))

                Text(state.currentProgress?.message ?? "")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 14) {
            Image(systemName: "network.badge.shield.half.filled")
                .font(.system(size: 48))
                .foregroundStyle(Theme.cyanPulse)

            Text("Global Diagnose Engine")
                .font(.system(size: 18, weight: .bold))

            Text("Enter a target hostname, IP address, URL, or subnet above to initiate a comprehensive multi-layer diagnosis.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
    }

    private func statusColor(_ status: OverallHealthStatus) -> Color {
        switch status {
        case .healthy: return Theme.emeraldHealthy
        case .degraded: return Theme.amberWarning
        case .critical: return Theme.crimsonCritical
        case .unreachable: return Theme.crimsonCritical
        }
    }

    private func classificationColor(_ c: FindingClassification) -> Color {
        switch c {
        case .observed: return Theme.azurePro
        case .derived: return Theme.amberWarning
        case .inferred: return Theme.purpleInferred
        }
    }

    private func confidenceDotColor(idx: Int, conf: ConfidenceLevel) -> Color {
        switch conf {
        case .high:
            return Theme.emeraldHealthy
        case .medium:
            return idx < 2 ? Theme.amberWarning : Color.primary.opacity(0.15)
        case .low:
            return idx == 0 ? Theme.crimsonCritical : Color.primary.opacity(0.15)
        }
    }
}
