import SwiftUI
import NetworkCore
import DiagnosticsEngine
import InvestigationKit

public struct DiagnoseWorkspaceView: View {
    @Bindable var state: AppState
    @State private var copiedReport = false

    public init(state: AppState) {
        self.state = state
    }

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - Hero Target Input Bar
            headerBar
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // MARK: - Content Area
            if state.isDiagnosing {
                progressView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let result = state.latestResult {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        overallStatusBanner(result: result)
                        findingsSection(result: result)
                        multiLayerObservationsGrid(result: result)
                    }
                    .padding(20)
                }
            } else {
                emptyStateView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    // MARK: - Header Bar
    private var headerBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "stethoscope")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.accentColor)

                HStack(spacing: 8) {
                    TextField("Enter target host, IP, URL, or subnet...", text: $state.targetInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15, design: .monospaced))
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
                            .background(Color.accentColor.opacity(0.12))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1), lineWidth: 1))

                Button(action: triggerDiagnosis) {
                    HStack(spacing: 6) {
                        if state.isDiagnosing {
                            ProgressView()
                                .controlSize(.small)
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

            // Pre-canned quick test chips
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
                    .font(.system(size: 11, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
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
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))

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
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }

    // MARK: - Findings Section
    private func findingsSection(result: DiagnosticResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ANALYTICAL FINDINGS")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(result.findings) { finding in
                    HStack(alignment: .top, spacing: 12) {
                        // Classification Pill (Observed, Derived, Inferred)
                        Text(finding.classification.rawValue.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
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

                                Text("•")
                                    .foregroundStyle(.secondary)

                                Text("Confidence: \(finding.confidence.rawValue)")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }

                            Text(finding.statement)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.primary.opacity(0.85))
                        }
                    }
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.06), lineWidth: 1))
                }
            }
        }
    }

    // MARK: - Multi-Layer Grid
    private func multiLayerObservationsGrid(result: DiagnosticResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MULTI-LAYER OBSERVATIONS")
                .font(.system(size: 12, weight: .bold))
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
                        Text("Not applicable for direct IP targets").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }

                // Layer 2: Transport & Latency
                observationCard(title: "Transport & Latency", icon: "waveform.path.ecg") {
                    if let lat = result.latency {
                        VStack(alignment: .leading, spacing: 6) {
                            metricRow(label: "Median RTT", value: String(format: "%.1f ms", lat.medianMs))
                            metricRow(label: "Min / Max", value: "\(String(format: "%.1f", lat.minMs)) / \(String(format: "%.1f", lat.maxMs)) ms")
                            metricRow(label: "P95 Latency", value: String(format: "%.1f ms", lat.p95Ms))
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
                                metricRow(label: "TLS Subject", value: cert.subjectSummary)
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
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            Divider()
            content()
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.06), lineWidth: 1))
    }

    private func metricRow(label: String, value: String, isSuccess: Bool? = nil) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(isSuccess == nil ? Color.primary : (isSuccess! ? Color.green : Color.red))
        }
    }

    // MARK: - Progress View
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

    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 14) {
            Image(systemName: "network.badge.shield.half.filled")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

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
        case .healthy: return .green
        case .degraded: return .orange
        case .critical: return .red
        case .unreachable: return .red
        }
    }

    private func classificationColor(_ c: FindingClassification) -> Color {
        switch c {
        case .observed: return .blue
        case .derived: return .purple
        case .inferred: return .orange
        }
    }
}
