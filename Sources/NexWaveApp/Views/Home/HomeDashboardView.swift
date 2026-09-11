import SwiftUI
import NetworkCore
import DiagnosticsEngine
import InvestigationKit

public struct HomeDashboardView: View {
    @Bindable var state: AppState

    public init(state: AppState) {
        self.state = state
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Hero Banner
                heroDiagnoseCard

                // Two column layout: Active Investigations & Recent Diagnoses
                HStack(alignment: .top, spacing: 20) {
                    activeInvestigationsCard
                    recentDiagnosesCard
                }

                // Quick Tool Launchers
                quickToolGrid
            }
            .padding(24)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
        .navigationTitle("Home / Dashboard")
    }

    // MARK: - Hero Diagnose Card
    private var heroDiagnoseCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("DIAGNOSE HOST OR ENDPOINT")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.accentColor)

                    Text("Instant Multi-Layer Network Diagnosis")
                        .font(.system(size: 20, weight: .bold))
                }
                Spacer()
                Image(systemName: "bolt.shield.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.accentColor.opacity(0.8))
            }

            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)

                    TextField("Enter hostname, IP address, URL, or subnet...", text: $state.targetInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15, design: .monospaced))
                        .onChange(of: state.targetInput) { _, newValue in
                            state.updateTargetClassification(newValue)
                        }
                        .onSubmit {
                            startDiagnosisFromHome()
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
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1), lineWidth: 1))

                Button(action: startDiagnosisFromHome) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                        Text("Diagnose")
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.classifiedTarget == nil)
            }
        }
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }

    private func startDiagnosisFromHome() {
        state.selectedWorkspace = .diagnose
        if let target = state.classifiedTarget {
            Task {
                await state.runDiagnosis(target: target)
            }
        }
    }

    // MARK: - Active Investigations Card
    private var activeInvestigationsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Active Investigations", systemImage: "briefcase.fill")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Button("View All") {
                    state.selectedWorkspace = .investigations
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.accentColor)
            }

            Divider()

            if state.investigations.isEmpty {
                VStack(spacing: 8) {
                    Text("No active investigations")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("Run a diagnosis and click 'Create Investigation' to track network problems.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                VStack(spacing: 8) {
                    ForEach(state.investigations.prefix(4)) { inv in
                        Button(action: {
                            state.selectedInvestigation = inv
                            state.selectedWorkspace = .investigations
                        }) {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(severityColor(inv.severity))
                                    .frame(width: 8, height: 8)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(inv.title)
                                        .font(.system(size: 12, weight: .medium))
                                        .lineLimit(1)
                                    Text(inv.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text(inv.status.rawValue)
                                    .font(.system(size: 10, weight: .semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.primary.opacity(0.06))
                                    .clipShape(Capsule())
                            }
                            .padding(8)
                            .background(Color.primary.opacity(0.02))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.06), lineWidth: 1))
    }

    // MARK: - Recent Diagnoses Card
    private var recentDiagnosesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Recent Diagnostics", systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Button("History") {
                    state.selectedWorkspace = .history
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.accentColor)
            }

            Divider()

            if state.recentHistory.isEmpty {
                VStack(spacing: 8) {
                    Text("No recent tests")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("Diagnostic runs will appear here automatically.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                VStack(spacing: 8) {
                    ForEach(state.recentHistory.prefix(4)) { item in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(item.tcpHealthy ? Color.green : Color.red)
                                .frame(width: 8, height: 8)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.target)
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                Text(Date(timeIntervalSince1970: item.timestamp).formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if let lat = item.pingLatency {
                                Text("\(String(format: "%.1f", lat)) ms")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(8)
                        .background(Color.primary.opacity(0.02))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.06), lineWidth: 1))
    }

    // MARK: - Quick Tools
    private var quickToolGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ENGINEERING TOOLBOX")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                quickToolButton(title: "Command Library", subtitle: "Multi-vendor CLI", icon: "terminal.fill", workspace: .commandLibrary)
                quickToolButton(title: "Config Workbench", subtitle: "Syntax & Diff", icon: "doc.text.magnifyingglass", workspace: .config)
                quickToolButton(title: "SNMP Studio", subtitle: "v1/v2c/v3 Browser", icon: "chart.bar.xaxis", workspace: .snmp)
                quickToolButton(title: "Packet Workbench", subtitle: "PCAP Summaries", icon: "waveform.path.ecg", workspace: .packet)
            }
        }
    }

    private func quickToolButton(title: String, subtitle: String, icon: String, workspace: WorkspaceItem) -> some View {
        Button(action: {
            state.selectedWorkspace = workspace
        }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.06), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func severityColor(_ s: InvestigationSeverity) -> Color {
        switch s {
        case .low: return .blue
        case .medium: return .orange
        case .high: return .red
        case .critical: return .purple
        }
    }
}
