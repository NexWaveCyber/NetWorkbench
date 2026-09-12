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
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showInspector = false

    var body: some Scene {
        WindowGroup {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                AppSidebar(state: state)
                    .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
            } detail: {
                detailViewForWorkspace(state.selectedWorkspace)
                    .frame(minWidth: 500, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)
            }
            .navigationSplitViewStyle(.automatic)
            .inspector(isPresented: $showInspector) {
                NetworkInspectorView(result: state.latestResult)
                    .inspectorColumnWidth(min: 260, ideal: 290, max: 350)
            }
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button(action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            if columnVisibility == .detailOnly {
                                columnVisibility = .all
                            } else {
                                columnVisibility = .detailOnly
                            }
                        }
                    }) {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 13))
                    }
                    .help("Toggle Sidebar (⌃⌘S)")
                }

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

                    Button(action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            showInspector.toggle()
                        }
                    }) {
                        Image(systemName: "sidebar.right")
                            .foregroundStyle(showInspector ? Theme.neonCyan : Color.secondary)
                    }
                    .help("Toggle Network Inspector (⌥⌘I)")
                }
            }
            .frame(minWidth: 1100, idealWidth: 1320, minHeight: 700, idealHeight: 880)
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
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 1320, height: 880)
        .commands {
            SidebarCommands()
            InspectorCommands()

            CommandGroup(after: .appInfo) {
                Divider()
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
                Divider()
                Button("Devices") { state.selectedWorkspace = .devices }
                    .keyboardShortcut("4", modifiers: [.command])
                Button("SNMP Studio") { state.selectedWorkspace = .snmp }
                    .keyboardShortcut("5", modifiers: [.command])
                Button("Config Workbench") { state.selectedWorkspace = .config }
                    .keyboardShortcut("6", modifiers: [.command])
                Button("Packet Workbench") { state.selectedWorkspace = .packet }
                    .keyboardShortcut("7", modifiers: [.command])
                Divider()
                Button("Investigations") { state.selectedWorkspace = .investigations }
                    .keyboardShortcut("8", modifiers: [.command])
                Button("Environments") { state.selectedWorkspace = .environments }
                Button("Command Library") { state.selectedWorkspace = .commandLibrary }
                Button("History") { state.selectedWorkspace = .history }
                    .keyboardShortcut("9", modifiers: [.command])
                Button("Settings") { state.selectedWorkspace = .settings }
                    .keyboardShortcut(",", modifiers: [.command])
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
            DeviceWorkbenchView(state: state)
        case .snmp:
            SNMPStudioView(state: state)
        case .config:
            ConfigWorkbenchView(state: state)
        case .packet:
            PacketWorkbenchView(state: state)
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
