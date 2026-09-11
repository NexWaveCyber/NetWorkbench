import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Set dock icon image dynamically
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") ??
                         Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
           let img = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = img
        } else {
            // Check adjacent Resources folder if unbundled
            let execDir = Bundle.main.bundleURL.deletingLastPathComponent()
            let fallbackURL = execDir.appendingPathComponent("../Resources/AppIcon.icns")
            if let img = NSImage(contentsOf: fallbackURL) {
                NSApp.applicationIconImage = img
            }
        }
    }
}

@main
struct NexWaveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup {
            NavigationSplitView {
                AppSidebar(state: state)
            } detail: {
                detailViewForWorkspace(state.selectedWorkspace)
            }
            .frame(minWidth: 1050, minHeight: 680)
            .sheet(isPresented: $state.showCommandPalette) {
                CommandPaletteView(state: state)
            }
            .overlay(alignment: .bottomTrailing) {
                if let toast = state.toastMessage {
                    Text(toast)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThickMaterial)
                        .clipShape(Capsule())
                        .shadow(radius: 4)
                        .padding(24)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                state.toastMessage = nil
                            }
                        }
                }
            }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Command Palette...") {
                    state.showCommandPalette = true
                }
                .keyboardShortcut("k", modifiers: [.command])
            }

            CommandMenu("Workspaces") {
                Button("Home / Dashboard") { state.selectedWorkspace = .home }
                    .keyboardShortcut("1", modifiers: [.command])
                Button("Diagnose") { state.selectedWorkspace = .diagnose }
                    .keyboardShortcut("2", modifiers: [.command])
                Button("Toolbox") { state.selectedWorkspace = .toolbox }
                    .keyboardShortcut("3", modifiers: [.command])
                Button("Devices") { state.selectedWorkspace = .devices }
                    .keyboardShortcut("4", modifiers: [.command])
                Button("SNMP Studio") { state.selectedWorkspace = .snmp }
                    .keyboardShortcut("5", modifiers: [.command])
                Button("Config Workbench") { state.selectedWorkspace = .config }
                    .keyboardShortcut("6", modifiers: [.command])
                Button("Investigations") { state.selectedWorkspace = .investigations }
                    .keyboardShortcut("7", modifiers: [.command])
                Button("Command Library") { state.selectedWorkspace = .commandLibrary }
                    .keyboardShortcut("8", modifiers: [.command])
                Button("History") { state.selectedWorkspace = .history }
                    .keyboardShortcut("9", modifiers: [.command])
            }
        }
    }

    @ViewBuilder
    private func detailViewForWorkspace(_ workspace: WorkspaceItem) -> some View {
        switch workspace {
        case .home:
            HomeDashboardView(state: state)
        case .diagnose:
            DiagnoseWorkspaceView(state: state)
        case .investigations:
            InvestigationsWorkspaceView(state: state)
        case .commandLibrary:
            CommandLibraryView()
        case .history:
            HistoryWorkspaceView(state: state)
        case .toolbox:
            SecondaryWorkspaceView(
                title: "Engineering Toolbox",
                icon: "wrench.and.screwdriver",
                subtitle: "Advanced stand-alone network utilities",
                capabilities: [
                    "Continuous Multi-Ping with percentile latency",
                    "Path Analysis & MTR with hop drift",
                    "IPv4 & IPv6 Subnet Calculator with VLSM",
                    "DNS Studio (Do53, DoH, DoT, DNSSEC)",
                    "TCP & Port Diagnostic Probes",
                    "HTTP/TLS Inspector with Certificate Chains",
                    "Internet Intelligence (ASN, RDAP, RPKI)"
                ]
            )
        case .devices:
            SecondaryWorkspaceView(
                title: "Device Workbench",
                icon: "server.rack",
                subtitle: "Saved switch, router, and firewall profiles",
                capabilities: [
                    "Inventory Management with Tags",
                    "Keychain Credential Storage (Zero Plaintext)",
                    "Interface Error Rate Polling",
                    "Local Network Discovery (ARP/NDP & Bonjour)",
                    "Terminal Quick Connect",
                    "Diagnostic Baseline Comparison"
                ]
            )
        case .snmp:
            SecondaryWorkspaceView(
                title: "SNMP Studio",
                icon: "chart.bar.xaxis",
                subtitle: "Pure Swift SNMP v1, v2c, and v3 Protocol Workbench",
                capabilities: [
                    "SNMP v1/v2c Community Queries",
                    "SNMP v3 USM (AuthPriv with SHA-256 & AES-256)",
                    "Interactive MIB Trie Browser (RFC 1213, IF-MIB)",
                    "Interface Error & Discard Counter Deltas",
                    "Bandwidth Utilization Rate Calculations",
                    "Table & Bulk Walk Engine"
                ]
            )
        case .config:
            SecondaryWorkspaceView(
                title: "Config Workbench",
                icon: "doc.text.magnifyingglass",
                subtitle: "Network Configuration Intelligence & Structural Diff",
                capabilities: [
                    "Cisco IOS, IOS-XE, NX-OS Lexical Parser",
                    "Semantic Structural Diff (Interfaces, VLANs, ACLs)",
                    "Deterministic ACL Packet Flow Simulator",
                    "Sensitive Password & Community Redactor",
                    "Hierarchical Section Folding & Search",
                    "Pre-Commit Assurance Checks"
                ]
            )
        case .packet:
            SecondaryWorkspaceView(
                title: "Packet Workbench",
                icon: "waveform.path.ecg",
                subtitle: "High-Speed Streaming PCAP / PCAPNG Summaries",
                capabilities: [
                    "Zero-GPL Native Streaming Capture Reader",
                    "Top Talkers & Protocol Distribution",
                    "Conversational Flow Analysis",
                    "TCP Retransmission & Anomaly Detection",
                    "DNS Latency & Failure Rate Tracking",
                    "Seamless 'Open in Wireshark' Integration"
                ]
            )
        case .environments:
            SecondaryWorkspaceView(
                title: "Environments",
                icon: "network",
                subtitle: "Logical Network Engineering Scopes",
                capabilities: [
                    "Scoped Subnets & Gateways",
                    "Custom DNS Resolver Associations",
                    "Site Notes & Engineering Runbooks",
                    "Scoped Device Credentials"
                ]
            )
        case .settings:
            SecondaryWorkspaceView(
                title: "Settings & Privacy",
                icon: "gearshape.fill",
                subtitle: "Local Data Management & Security Configuration",
                capabilities: [
                    "100% Local-First Storage (SQLite WAL Mode)",
                    "Hardware Keychain Services Status",
                    "Local Test History Retention Policies",
                    "Zero Secret Telemetry Guarantee",
                    "Export Sanitized Diagnostics Bundle"
                ]
            )
        }
    }
}
