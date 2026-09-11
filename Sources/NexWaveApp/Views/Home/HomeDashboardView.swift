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
            VStack(alignment: .leading, spacing: 20) {
                // Hero Diagnosis Card
                heroDiagnoseCard

                // Local Network Interface KPI Bar
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
        .background(Theme.secondaryBackground)
        .navigationTitle("Engineering Dashboard")
    }

    // MARK: - Hero Diagnose Card
    private var heroDiagnoseCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("GLOBAL DIAGNOSE ENGINE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.cyanPulse)

                    Text("Deterministic Multi-Layer Network Diagnosis")
                        .font(.system(size: 20, weight: .bold))
                }
                Spacer()
                Image(systemName: "bolt.shield.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Theme.cyanPulse)
            }

            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)

                    TextField("Enter hostname, IP address, URL, or subnet (e.g. google.com, 10.20.0.1)...", text: $state.targetInput)
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
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Theme.azurePro.opacity(0.15))
                            .foregroundStyle(Theme.azurePro)
                            .clipShape(Capsule())
                    }
                }
                .padding(12)
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderLight, lineWidth: 1))

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
        .engineeringCard(padding: 20)
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
        HStack(spacing: 16) {
            kpiPill(label: "PRIMARY LINK", val: "en0 (Wi-Fi 6 / GbE)", icon: "wifi")
            kpiPill(label: "LOCAL IP", val: "192.168.1.142", icon: "laptopcomputer")
            kpiPill(label: "DEFAULT GATEWAY", val: "192.168.1.1", icon: "network")
            kpiPill(label: "SYSTEM RESOLVER", val: "System DNS", icon: "arrow.triangle.branch")
        }
    }

    private func kpiPill(label: String, val: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Theme.azurePro)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
                Text(val).font(Theme.monoText(12, weight: .semibold)).lineLimit(1)
            }
            Spacer()
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderLight, lineWidth: 1))
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
                .foregroundStyle(Theme.azurePro)
            }

            Divider()

            if state.investigations.isEmpty {
                VStack(spacing: 8) {
                    Text("No active investigations")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("Diagnose a target and click 'Create Investigation' to track network anomalies.")
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
        .frame(maxWidth: .infinity)
        .engineeringCard()
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
                .foregroundStyle(Theme.azurePro)
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
                                .fill(item.tcpHealthy ? Theme.emeraldHealthy : Theme.crimsonCritical)
                                .frame(width: 8, height: 8)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.target)
                                    .font(Theme.monoText(12, weight: .semibold))
                                Text(Date(timeIntervalSince1970: item.timestamp).formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if let lat = item.pingLatency {
                                Text("\(String(format: "%.1f", lat)) ms")
                                    .font(Theme.monoText(11, weight: .medium))
                                    .foregroundStyle(Theme.cyanPulse)
                            }
                        }
                        .padding(8)
                        .background(Color.primary.opacity(0.02))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .engineeringCard()
    }

    // MARK: - Interactive Studios
    private var toolboxStudiosGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("INTERACTIVE ENGINEERING STUDIOS")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                studioCard(title: "Subnet Calculator", desc: "CIDR / VLSM / Binary", icon: "number.square.fill", workspace: .toolbox)
                studioCard(title: "Command Library", desc: "Multi-vendor CLI DB", icon: "terminal.fill", workspace: .commandLibrary)
                studioCard(title: "SNMP Studio", desc: "v1/v2c/v3 MIB Browser", icon: "chart.bar.xaxis", workspace: .snmp)
                studioCard(title: "Config Workbench", desc: "Syntax & Diff Engine", icon: "doc.text.magnifyingglass", workspace: .config)
            }
        }
    }

    private func studioCard(title: String, desc: String, icon: String, workspace: WorkspaceItem) -> some View {
        Button(action: {
            state.selectedWorkspace = workspace
        }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.cyanPulse)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                    Text(desc)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderLight, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func severityColor(_ s: InvestigationSeverity) -> Color {
        switch s {
        case .low: return Theme.azurePro
        case .medium: return Theme.amberWarning
        case .high: return Theme.crimsonCritical
        case .critical: return Theme.purpleInferred
        }
    }
}
