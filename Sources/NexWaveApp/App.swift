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
    @State private var showInspector = true

    var body: some Scene {
        WindowGroup {
            NavigationSplitView {
                AppSidebar(state: state)
            } detail: {
                detailViewForWorkspace(state.selectedWorkspace)
            }
            .inspector(isPresented: $showInspector) {
                NetworkInspectorView(result: state.latestResult)
            }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Theme.signalEmerald)
                            .frame(width: 6, height: 6)
                        Text("en0 • 192.168.1.142")
                            .font(Theme.monoText(11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(Capsule())
                    .help("Active Interface: en0 (Wi-Fi / Ethernet)")
                }

                ToolbarItemGroup(placement: .automatic) {
                    Button(action: { state.showCommandPalette = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 11))
                            Text("Command Palette")
                                .font(.system(size: 12))
                            Text("⌘K")
                                .font(Theme.monoText(10, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.primary.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                    .help("Open Command Palette (Cmd+K)")

                    Button(action: { showInspector.toggle() }) {
                        Image(systemName: showInspector ? "sidebar.right" : "sidebar.right")
                            .foregroundStyle(showInspector ? Theme.azurePro : Color.primary)
                    }
                    .help("Toggle Network Inspector (Cmd+I)")
                }
            }
            .frame(minWidth: 1100, minHeight: 700)
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

                Button("Toggle Inspector") {
                    showInspector.toggle()
                }
                .keyboardShortcut("i", modifiers: [.command])
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
        case .toolbox:
            ToolboxWorkspaceContainerView()
        case .investigations:
            InvestigationsWorkspaceView(state: state)
        case .commandLibrary:
            CommandLibraryView()
        case .history:
            HistoryWorkspaceView(state: state)
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
