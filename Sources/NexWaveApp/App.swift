import SwiftUI
import AppKit
import TerminalKit

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
    @State private var menuBarMonitor = MenuBarMonitorEngine.shared
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showInspector = false
    @AppStorage("menuBarIconStyle") private var menuBarIconStyle: String = "nextGenWave"

    init() {
        MenuBarMonitorEngine.shared.startMonitoring()
    }

    var body: some Scene {
        WindowGroup(id: "main-window") {
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
                    HStack(spacing: 7) {
                        PulsingBeacon(color: Theme.signalEmerald, size: 6, isLive: true)
                        Text("\(menuBarMonitor.activeInterface) • \(menuBarMonitor.localIP)")
                            .font(Theme.monoText(11, weight: .semibold))
                            .foregroundStyle(.primary.opacity(0.85))

                        if let wifi = menuBarMonitor.wifiLink, wifi.transmitRate > 0 {
                            Text("\(Int(wifi.transmitRate)) Mbps")
                                .font(Theme.monoText(9, weight: .bold))
                                .foregroundStyle(Theme.cyanPulse)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Theme.cyanPulse.opacity(0.12))
                                .clipShape(Capsule())
                        } else {
                            Text("1.0 Gbps")
                                .font(Theme.monoText(9, weight: .bold))
                                .foregroundStyle(Theme.cyanPulse)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Theme.cyanPulse.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(LinearGradient(
                                colors: [Color.white.opacity(0.15), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ), lineWidth: 0.75)
                    )
                    .help("Active Network Adapter: \(menuBarMonitor.activeInterface) (\(menuBarMonitor.localIP)) • Gateway: \(menuBarMonitor.defaultGateway)")
                }

                ToolbarItemGroup(placement: .automatic) {
                    Button(action: { state.showCommandPalette = true }) {
                        HStack(spacing: 7) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.neonCyan)
                            Text("Command Palette")
                                .font(.system(size: 12, weight: .medium))
                            Text("⌘K")
                                .font(Theme.monoText(10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(Color.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.75)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Open Command Palette (⌘K)")

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
                    HStack(spacing: 10) {
                        Image(systemName: "bolt.shield.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.neonCyan)

                        Text(toast)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThickMaterial)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(Theme.cyanPulse.opacity(0.3), lineWidth: 1)
                    )
                    .shadow(color: Theme.neonCyan.opacity(0.15), radius: 10, x: 0, y: 3)
                    .padding(24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                state.toastMessage = nil
                            }
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
                Button("Wi-Fi Studio") { state.selectedWorkspace = .wifi }
                Button("Timeline Monitor") { state.selectedWorkspace = .timeline }
                Button("Devices") { state.selectedWorkspace = .devices }
                    .keyboardShortcut("4", modifiers: [.command])
                Button("Terminal & Console") { state.selectedWorkspace = .terminal }
                    .keyboardShortcut("t", modifiers: [.command])
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

        MenuBarExtra {
            MenuBarQuickGlanceView(monitor: menuBarMonitor, state: state)
        } label: {
            HStack(spacing: 4) {
                let iconName: String = {
                    if menuBarMonitor.healthStatus == .offline {
                        switch menuBarIconStyle {
                        case "network": return "network.slash"
                        case "topology": return "circle.slash"
                        default: return "waveform.slash"
                        }
                    } else if menuBarMonitor.healthStatus == .degraded {
                        switch menuBarIconStyle {
                        case "network": return "network.badge.shield.half.filled"
                        case "topology": return "point.3.connected.trianglepath.dotted"
                        default: return "waveform.badge.exclamationmark"
                        }
                    } else {
                        switch menuBarIconStyle {
                        case "forwardWave": return "wave.3.forward"
                        case "sineWave": return "waveform.path"
                        case "spectrumWave": return "waveform"
                        case "network": return "network"
                        case "topology": return "point.3.connected.trianglepath.dotted"
                        default: return "waveform.path.ecg" // NexWave Signature Next-Gen Wave
                        }
                    }
                }()
                Image(systemName: iconName)

                if menuBarMonitor.healthStatus == .offline {
                    Text("Offline")
                        .font(Theme.monoText(10, weight: .bold))
                } else if let ms = menuBarMonitor.gatewayLatencyMs {
                    Text(ms < 1.0 ? "<1ms" : String(format: "%.0fms", ms))
                        .font(Theme.monoText(10, weight: .bold))
                }
            }
            .help(menuBarStatusTooltip)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarStatusTooltip: String {
        var lines = [
            "NexWave Network Workbench",
            "Health: \(menuBarMonitor.healthScorePercentage)% (\(menuBarMonitor.healthScoreLabel))",
            "Active Interface: \(menuBarMonitor.activeInterface) (\(menuBarMonitor.localIP)/\(menuBarMonitor.cidrPrefix))"
        ]
        if let gw = menuBarMonitor.gatewayLatencyMs {
            let gwStr = gw < 1.0 ? "< 1 ms" : String(format: "%.1f ms", gw)
            lines.append("Gateway: \(menuBarMonitor.defaultGateway) (\(gwStr))")
        }
        if let inet = menuBarMonitor.internetLatencyMs {
            lines.append("Internet WAN (1.1.1.1): \(String(format: "%.1f ms", inet))")
        }
        if let wifi = menuBarMonitor.wifiLink {
            let mcsStr = wifi.mcsIndex != nil ? " • MCS \(wifi.mcsIndex!)" : ""
            lines.append("Wi-Fi: \"\(wifi.ssid)\" (\(wifi.rssi) dBm\(mcsStr) • Ch \(wifi.channel) • \(wifi.phyMode.displayName))")
        } else if menuBarMonitor.healthStatus != .offline {
            lines.append("Ethernet: 1.0 Gbps Full-Duplex (1000BASE-T)")
        } else {
            lines.append("Carrier Status: Disconnected / Link Down")
        }
        lines.append("Click for Quick Glance • ⌘1 Open App")
        return lines.joined(separator: "\n")
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
        case .wifi:
            WiFiStudioView()
        case .timeline:
            TimeSeriesStudioView()
        case .investigations:
            InvestigationsWorkspaceView(state: state)
        case .commandLibrary:
            CommandLibraryView(state: state)
        case .history:
            HistoryWorkspaceView(state: state)
        case .devices:
            DeviceWorkbenchView(state: state)
        case .terminal:
            TerminalWorkbenchView(state: state)
        case .snmp:
            SNMPStudioView(state: state)
        case .config:
            ConfigWorkbenchView(state: state)
        case .packet:
            PacketWorkbenchView(state: state)
        case .environments:
            EnvironmentsWorkspaceView(state: state)
        case .settings:
            SettingsWorkspaceView(state: state)
        }
    }
}
