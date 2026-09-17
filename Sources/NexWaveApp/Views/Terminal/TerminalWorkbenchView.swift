import SwiftUI
import TerminalKit
import CommandLibrary
import AppKit

/// Integrated tabbed SSH, USB Serial Console, and Multi-Vendor CLI terminal workspace
/// Features true streaming ANSI SGR color rendering, split-panes, broadcast mode,
/// hardware break generator, persistent profile vault, and paced script execution.
public struct TerminalWorkbenchView: View {
    @Bindable var state: AppState
    @State private var inputCommand: String = ""
    @State private var showNewSessionSheet: Bool = false
    @State private var showProfileVaultSheet: Bool = false
    @State private var showPacedPasteSheet: Bool = false
    @State private var showSSHKeyStudioSheet: Bool = false
    @State private var showSSHTunnelsSheet: Bool = false
    @State private var fontSize: CGFloat = 12
    @State private var autoScroll: Bool = true
    @State private var selectedTheme: TerminalTheme = .obsidian
    @State private var isSearching: Bool = false
    @State private var searchQuery: String = ""
    @State private var focusedPane: Int = 0 // 0: Primary, 1: Secondary, 2: Pane 3, 3: Pane 4
    @FocusState private var focusedPaneState: Int?

    // Quick Connect
    @State private var quickConnectInput: String = ""

    // Paced Script Runner States
    @State private var scriptText: String = ""
    @State private var scriptDelayMs: Double = 50.0
    @State private var stopOnError: Bool = true
    @State private var isRunningScript: Bool = false
    @State private var scriptCurrentLineIndex: Int = 0
    @State private var scriptTotalLines: Int = 0

    // New Session Form States
    @State private var newSessionType: Int = 0 // 0: SSH, 1: Serial, 2: Simulation, 3: Local Shell
    @State private var sshHost: String = "192.168.1.1"
    @State private var sshPort: String = "22"
    @State private var sshUser: String = "admin"
    @State private var sshPassword: String = ""
    @State private var sshKeyPath: String = ""
    @State private var sshEnableJumpHost: Bool = false
    @State private var sshJumpHost: String = ""
    @State private var sshJumpPort: String = "22"
    @State private var sshJumpUser: String = "admin"
    @State private var sshEnableLegacyCiphers: Bool = false

    @State private var selectedSerialPort: String = ""
    @State private var selectedBaudRate: Int = 9600
    @State private var selectedDataBits: Int = 8
    @State private var selectedParity: SerialParity = .none
    @State private var selectedStopBits: Int = 1
    @State private var selectedFlowControl: SerialFlowControl = .none
    @State private var selectedSimPreset: String = "Catalyst 9300 Core"

    // Profile Vault Form States
    @State private var selectedVaultFolder: String = "All"
    @State private var vaultSearchText: String = ""
    @State private var isCreatingProfile: Bool = false
    @State private var profileName: String = ""
    @State private var profileFolder: String = "Data Center"

    // SSH Key Studio States (MobaKeyGen)
    @State private var newKeyType: String = "Ed25519"
    @State private var newKeyComment: String = "saeid@mac"
    @State private var keyGenSuccessToast: String? = nil
    @State private var selectedKeyForDeploy: String = ""
    @State private var deployHost: String = ""
    @State private var deployPort: String = "22"
    @State private var deployUser: String = "root"
    @State private var isDeployingKey: Bool = false
    @State private var deployStatusMsg: String? = nil

    // SSH Tunnel Form States (MobaSSHTunnel)
    @State private var tunnelNameInput: String = ""
    @State private var tunnelTypeInput: SSHTunnelType = .localForward
    @State private var tunnelLocalPortInput: String = "8080"
    @State private var tunnelDestHostInput: String = "192.168.1.1"
    @State private var tunnelDestPortInput: String = "443"
    @State private var tunnelSSHHostInput: String = ""
    @State private var tunnelSSHPortInput: String = "22"
    @State private var tunnelSSHUserInput: String = "admin"
    @State private var tunnelIdentityKeyInput: String = ""

    public init(state: AppState) {
        self.state = state
    }

    private var activeSession: TerminalSession? {
        state.terminalManager.activeSession
    }

    private var secondarySession: TerminalSession? {
        state.terminalManager.secondarySession
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Collapsible MobaXterm Session Tree & Quick Connect Sidebar
            if state.terminalManager.isSidebarExpanded {
                sessionTreeSidebar
                    .frame(width: 260)
                Divider().overlay(Theme.borderLight)
            }

            VStack(spacing: 0) {
                // Header Bar
                headerBar

                Divider().overlay(Theme.borderLight)

                // Broadcast Banner (when active)
                if state.terminalManager.isBroadcastEnabled {
                    broadcastWarningBanner
                    Divider().overlay(Theme.borderLight)
                }

                // Session Tab Strip
                sessionTabBar

                Divider().overlay(Theme.borderLight)

                // Search Bar (collapsible)
                if isSearching {
                    transcriptSearchBar
                    Divider().overlay(Theme.borderLight)
                }

                // Command Macros Strip
                commandSnippetsBar

                Divider().overlay(Theme.borderLight)

                // Main Terminal Canvas (Single, Split, or Quad Grid)
                mainTerminalLayoutView
            }
        }
        .background(Theme.surfaceBackground)
        .sheet(isPresented: $showNewSessionSheet) {
            newSessionModal
        }
        .sheet(isPresented: $showProfileVaultSheet) {
            profileVaultModal
        }
        .sheet(isPresented: $showPacedPasteSheet) {
            pacedScriptRunnerModal
        }
        .sheet(isPresented: $showSSHKeyStudioSheet) {
            sshKeyStudioModal
        }
        .sheet(isPresented: $showSSHTunnelsSheet) {
            sshTunnelsModal
        }
        .onAppear {
            if selectedSerialPort.isEmpty, let firstPort = state.terminalManager.availableSerialPorts.first {
                selectedSerialPort = firstPort.devicePath
            }
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 12) {
            // Sidebar toggle button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    state.terminalManager.isSidebarExpanded.toggle()
                }
            }) {
                Image(systemName: state.terminalManager.isSidebarExpanded ? "sidebar.left" : "sidebar.leading")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(state.terminalManager.isSidebarExpanded ? Theme.neonCyan : .secondary)
            }
            .buttonStyle(.plain)
            .help("Toggle MobaXterm Session & Quick Connect Sidebar")

            ZStack {
                Circle()
                    .fill(Theme.cyanPulse.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: "terminal.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.cyanPulse)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("TERMINAL & SERIAL CONSOLE BRIDGE")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                    HUDStatusBadge(
                        title: activeSession?.status.rawValue ?? "No Session",
                        color: Color(hex: activeSession?.status.badgeColorHex ?? "#8E8E93"),
                        icon: activeSession?.status == .connected ? "antenna.radiowaves.left.and.right" : nil
                    )

                    if let s = activeSession {
                        if s.status != .connected && s.status != .connecting("Establishing connection...") {
                            Button(action: {
                                s.connect()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Reconnect")
                                }
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Theme.neonCyan.opacity(0.18))
                                .foregroundStyle(Theme.neonCyan)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(Theme.neonCyan.opacity(0.6), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .help("Reconnect this session")
                        } else if s.status == .connected {
                            Button(action: {
                                s.disconnect()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "power")
                                    Text("Disconnect")
                                }
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.red.opacity(0.18))
                                .foregroundStyle(Color.red)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                            }
                            .buttonStyle(.plain)
                            .help("Disconnect active session")
                        }
                    }
                }
                Text("Direct PTY SSH, POSIX Serial Console, and Cisco/Arista/Junos Multi-Vendor CLI")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Header Utilities
            HStack(spacing: 8) {
                // Split Screen Mode Picker
                Picker("", selection: $state.terminalManager.splitMode) {
                    ForEach(TerminalSplitMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 150)
                .help("Switch between Single, Side-by-Side, Stacked, or 2x2 Quad Grid terminal panes")

                // Broadcast Multi-Exec Toggle Button
                Button(action: {
                    state.terminalManager.isBroadcastEnabled.toggle()
                }) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(state.terminalManager.isBroadcastEnabled ? Theme.crimsonCritical : Color.gray.opacity(0.5))
                            .frame(width: 7, height: 7)
                        Text(state.terminalManager.isBroadcastEnabled ? "BROADCAST ON" : "Broadcast")
                            .font(.system(size: 10.5, weight: .bold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(state.terminalManager.isBroadcastEnabled ? Theme.crimsonCritical.opacity(0.18) : Theme.cardBackground)
                    .foregroundStyle(state.terminalManager.isBroadcastEnabled ? Theme.crimsonCritical : .secondary)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(state.terminalManager.isBroadcastEnabled ? Theme.crimsonCritical.opacity(0.6) : Theme.borderLight, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .help("Broadcast typed commands to all connected switch sessions simultaneously")

                // SSH Key Studio (MobaKeyGen)
                Button(action: { showSSHKeyStudioSheet = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "key.fill")
                        Text("SSH Keys")
                    }
                    .font(.system(size: 10.5, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .help("Open SSH Key Studio: Generate Ed25519/RSA keys, copy public key, deploy to server (MobaKeyGen)")

                // SSH Tunnels (MobaSSHTunnel)
                Button(action: { showSSHTunnelsSheet = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.swap")
                        Text("Tunnels")
                    }
                    .font(.system(size: 10.5, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .help("Manage SSH Port Forwarding & Tunnels: -L Local, -R Remote, -D SOCKS5 Proxy (MobaSSHTunnel)")

                // Live Syntax Highlighting Toggle
                Button(action: {
                    state.terminalManager.isSyntaxHighlightingEnabled.toggle()
                    for s in state.terminalManager.sessions {
                        s.syntaxHighlightConfig.isEnabled = state.terminalManager.isSyntaxHighlightingEnabled
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "paintpalette.fill")
                        Text(state.terminalManager.isSyntaxHighlightingEnabled ? "SYNTAX ON" : "Syntax")
                    }
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(state.terminalManager.isSyntaxHighlightingEnabled ? Theme.neonCyan : .secondary)
                }
                .buttonStyle(.bordered)
                .help("Toggle live syntax highlighting for IP addresses, MAC addresses, error states, and up/down keywords")

                // Hardware Serial Break (ROMMON) Button
                Button(action: sendHardwareBreak) {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.badge.clock")
                        Text("Break (ROMMON)")
                    }
                    .font(.system(size: 10.5, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .help("Send hardware serial break signal (250-500ms space) for Cisco ROMMON password recovery or Juniper loader prompt")

                // Paced Script Paste Runner Button
                Button(action: { showPacedPasteSheet = true }) {
                    Label("Run Script", systemImage: "doc.text.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .help("Paste multi-line configuration blocks with controlled line-by-line delay and error pauses")

                // Profile Vault Button
                Button(action: { showProfileVaultSheet = true }) {
                    Label("Profiles", systemImage: "books.vertical.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .help("Open saved switch and console profile bookmarks")

                // Font Size Adjuster
                HStack(spacing: 4) {
                    Button(action: { if fontSize > 10 { fontSize -= 1; updatePTYDimensions() } }) {
                        Image(systemName: "textformat.size.smaller")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)

                    Text("\(Int(fontSize))pt")
                        .font(Theme.monoText(10))
                        .foregroundStyle(.secondary)
                        .frame(width: 28)

                    Button(action: { if fontSize < 18 { fontSize += 1; updatePTYDimensions() } }) {
                        Image(systemName: "textformat.size.larger")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                // Theme Selector Menu
                Menu {
                    ForEach(TerminalTheme.allCases) { theme in
                        Button(action: { selectedTheme = theme }) {
                            HStack {
                                Text(theme.rawValue)
                                if selectedTheme == theme {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Label(selectedTheme.rawValue, systemImage: "paintpalette")
                        .font(.system(size: 10.5))
                }
                .menuStyle(.borderedButton)

                // Timestamps Toggle
                Button(action: {
                    if let s = activeSession {
                        s.showTimestamps.toggle()
                    }
                }) {
                    Image(systemName: "clock")
                        .font(.system(size: 11))
                        .foregroundStyle(activeSession?.showTimestamps == true ? Theme.cyanPulse : .secondary)
                }
                .buttonStyle(.bordered)
                .help("Toggle microsecond per-line timestamp prefixes")

                // Search Transcript Toggle
                Button(action: {
                    isSearching.toggle()
                    if !isSearching { searchQuery = "" }
                }) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(isSearching ? Theme.cyanPulse : .primary)
                }
                .buttonStyle(.bordered)
                .help("Search Terminal Transcript")

                // External Terminal Launch Menu
                Menu {
                    if let session = activeSession, case .ssh(let host, let port, let user, _, _, _, _) = session.connectionType {
                        Button("Open in Terminal.app") {
                            let cmd = ExternalTerminalBridge.shared.sshCommand(host: host, port: port, username: user)
                            ExternalTerminalBridge.shared.launchInTerminalApp(command: cmd)
                        }
                        if ExternalTerminalBridge.shared.isITermInstalled {
                            Button("Open in iTerm2") {
                                let cmd = ExternalTerminalBridge.shared.sshCommand(host: host, port: port, username: user)
                                ExternalTerminalBridge.shared.launchInITerm2(command: cmd)
                            }
                        }
                        Divider()
                        Button("Copy SSH Command") {
                            let cmd = ExternalTerminalBridge.shared.sshCommand(host: host, port: port, username: user)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(cmd, forType: .string)
                        }
                    } else {
                        Button("Launch Terminal.app") {
                            ExternalTerminalBridge.shared.launchInTerminalApp(command: "echo 'NexWave Terminal Bridge Active'")
                        }
                    }
                } label: {
                    Label("External", systemImage: "arrow.up.forward.app")
                        .font(.system(size: 10.5))
                }
                .menuStyle(.borderedButton)

                // Export Transcript
                Button(action: exportTranscript) {
                    Label("Export Log", systemImage: "square.and.arrow.up")
                        .font(.system(size: 10.5))
                }
                .buttonStyle(.bordered)

                // Clear Output
                Button(action: { activeSession?.clear() }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .help("Clear Terminal Screen")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.surfaceBackground)
    }

    // MARK: - Broadcast Warning Banner

    private var broadcastWarningBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.crimsonCritical)

            Text("BROADCAST MODE ACTIVE:")
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(Theme.crimsonCritical)

            let connectedCount = state.terminalManager.sessions.filter { $0.status == .connected }.count
            Text("All typed keystrokes and macros are transmitted simultaneously across \(connectedCount) connected session tabs.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)

            Spacer()

            Button("Disable Broadcast") {
                state.terminalManager.isBroadcastEnabled = false
            }
            .font(.system(size: 10, weight: .bold))
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Theme.crimsonCritical.opacity(0.12))
    }

    // MARK: - Session Tab Bar

    private var sessionTabBar: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(state.terminalManager.sessions) { session in
                        let isSelected = session.id == state.terminalManager.activeSessionId
                        HStack(spacing: 6) {
                            Image(systemName: session.connectionType.iconName)
                                .font(.system(size: 10))
                                .foregroundStyle(isSelected ? Theme.cyanPulse : .secondary)

                            Circle()
                                .fill(Color(hex: session.status.badgeColorHex))
                                .frame(width: 6, height: 6)

                            Text(session.title)
                                .font(Theme.monoText(11, weight: isSelected ? .bold : .medium))
                                .foregroundStyle(isSelected ? Color.white : .secondary)

                            Button(action: {
                                state.terminalManager.closeSession(id: session.id)
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, 2)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(isSelected ? Theme.cardBackground : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isSelected ? Theme.cyanPulse.opacity(0.4) : Theme.borderLight, lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            state.terminalManager.activeSessionId = session.id
                        }
                    }
                }
            }

            Spacer()

            // New Session Button
            Button(action: {
                state.terminalManager.refreshSerialPorts()
                showNewSessionSheet = true
            }) {
                Label("New Session", systemImage: "plus")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.cyanPulse)
            .foregroundStyle(Color.black)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
    }

    // MARK: - Search Bar

    private var transcriptSearchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            TextField("Filter lines (e.g. error, GigabitEthernet, down, BGP)...", text: $searchQuery)
                .font(Theme.monoText(11))
                .textFieldStyle(.plain)

            if !searchQuery.isEmpty {
                let matchCount = activeSession?.searchLines(query: searchQuery).count ?? 0
                Text("\(matchCount) match\(matchCount == 1 ? "" : "es")")
                    .font(Theme.monoText(10))
                    .foregroundStyle(.secondary)

                Button(action: { searchQuery = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Button("Done") {
                isSearching = false
                searchQuery = ""
            }
            .font(.system(size: 11))
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Theme.cardBackground)
    }

    // MARK: - Quick Command Snippets Bar

    private var commandSnippetsBar: some View {
        HStack(spacing: 8) {
            Text("MACROS:")
                .font(Theme.monoText(9, weight: .bold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(state.terminalManager.macros) { macro in
                        macroChip(macro)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .background(Theme.surfaceBackground.opacity(0.8))
    }

    private func macroChip(_ macro: CommandMacro) -> some View {
        Button(action: {
            executeMacro(macro)
        }) {
            HStack(spacing: 4) {
                Text(macro.category)
                    .font(Theme.monoText(8, weight: .bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color(hex: selectedTheme.promptColorHex).opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                Text(macro.name)
                    .font(Theme.monoText(10, weight: .medium))
            }
            .foregroundStyle(Color(hex: selectedTheme.promptColorHex))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(hex: selectedTheme.promptColorHex).opacity(0.08))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color(hex: selectedTheme.promptColorHex).opacity(0.25), lineWidth: 0.75))
        }
        .buttonStyle(.plain)
        .help("Execute '\(macro.command)'")
    }

    // MARK: - Main Terminal Layout (Single / Split Panes)

    @ViewBuilder
    private var mainTerminalLayoutView: some View {
        if let primary = activeSession {
            switch state.terminalManager.splitMode {
            case .single:
                terminalPane(session: primary, paneIndex: 0)

            case .vertical:
                HStack(spacing: 2) {
                    terminalPane(session: primary, paneIndex: 0)
                    Divider().overlay(Theme.borderLight)
                    if let sec = secondarySession {
                        terminalPane(session: sec, paneIndex: 1)
                    } else {
                        emptySecondaryPanePlaceholder
                    }
                }

            case .horizontal:
                VStack(spacing: 2) {
                    terminalPane(session: primary, paneIndex: 0)
                    Divider().overlay(Theme.borderLight)
                    if let sec = secondarySession {
                        terminalPane(session: sec, paneIndex: 1)
                    } else {
                        emptySecondaryPanePlaceholder
                    }
                }

            case .quadGrid:
                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        terminalPane(session: primary, paneIndex: 0)
                        Divider().overlay(Theme.borderLight)
                        if let sec = secondarySession {
                            terminalPane(session: sec, paneIndex: 1)
                        } else {
                            emptySecondaryPanePlaceholder
                        }
                    }
                    Divider().overlay(Theme.borderLight)
                    HStack(spacing: 2) {
                        if let p3 = state.terminalManager.pane3Session {
                            terminalPane(session: p3, paneIndex: 2)
                        } else {
                            emptySecondaryPanePlaceholder
                        }
                        Divider().overlay(Theme.borderLight)
                        if let p4 = state.terminalManager.pane4Session {
                            terminalPane(session: p4, paneIndex: 3)
                        } else {
                            emptySecondaryPanePlaceholder
                        }
                    }
                }
            }
        } else {
            emptySessionPlaceholder
        }
    }

    private func paneSessionBinding(paneIndex: Int) -> Binding<UUID?> {
        switch paneIndex {
        case 0: return $state.terminalManager.activeSessionId
        case 1: return $state.terminalManager.secondarySessionId
        case 2: return $state.terminalManager.pane3SessionId
        default: return $state.terminalManager.pane4SessionId
        }
    }

    // MARK: - Individual Terminal Console Pane

    private func terminalPane(session: TerminalSession, paneIndex: Int) -> some View {
        let isFocused = (focusedPane == paneIndex)
        let displayedLines = searchQuery.isEmpty ? session.lines : session.searchLines(query: searchQuery)

        return VStack(spacing: 0) {
            // Pane Header Strip (in split mode)
            if state.terminalManager.splitMode != .single {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: session.connectionType.iconName)
                            .font(.system(size: 10))
                        Text(session.title)
                            .font(Theme.monoText(11, weight: .bold))
                    }
                    .foregroundStyle(isFocused ? Theme.neonCyan : .secondary)

                    Spacer()

                    // Session picker for this pane
                    Picker("", selection: paneSessionBinding(paneIndex: paneIndex)) {
                        ForEach(state.terminalManager.sessions) { s in
                            Text(s.title).tag(Optional(s.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 140)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Theme.surfaceBackground)
                Divider().overlay(Theme.borderLight)
            }

            // Screen Output ScrollView with ANSI SGR Rendering
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(displayedLines) { line in
                            HStack(alignment: .top, spacing: 6) {
                                // Optional microsecond timestamp
                                if session.showTimestamps {
                                    Text(timestampString(for: line.timestamp))
                                        .font(Theme.monoText(max(8, fontSize - 2)))
                                        .foregroundColor(Color.secondary.opacity(0.6))
                                        .frame(width: 75, alignment: .leading)
                                }

                                if line.isCommandInput {
                                    HStack(spacing: 6) {
                                        Text(">")
                                            .font(Theme.monoText(fontSize, weight: .bold))
                                            .foregroundStyle(Color(hex: selectedTheme.promptColorHex))
                                        Text(line.text)
                                            .font(Theme.monoText(fontSize, weight: .semibold))
                                            .foregroundStyle(Color(hex: selectedTheme.foregroundColorHex))
                                    }
                                    .padding(.vertical, 1)
                                } else {
                                    // True streaming ANSI SGR rendered spans
                                    HStack(spacing: 0) {
                                        ForEach(line.spans) { span in
                                            Text(span.text)
                                                .font(Theme.monoText(fontSize, weight: span.style.isBold ? .bold : .regular))
                                                .underline(span.style.isUnderline)
                                                .italic(span.style.isItalic)
                                                .foregroundStyle(colorForSpan(span.style))
                                                .background(backgroundColorForSpan(span.style))
                                        }
                                    }
                                    .textSelection(.enabled)
                                }
                            }
                        }
                        // Interactive Cursor Indicator
                        HStack(spacing: 2) {
                            Text("▋")
                                .font(Theme.monoText(fontSize, weight: .bold))
                                .foregroundStyle(isFocused ? Color(hex: selectedTheme.promptColorHex) : Color.secondary.opacity(0.35))
                        }

                        Color.clear
                            .frame(height: 1)
                            .id("bottomAnchor_\(paneIndex)")
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(hex: selectedTheme.backgroundColorHex))
                .onChange(of: session.lines.count) { _, _ in
                    if autoScroll {
                        proxy.scrollTo("bottomAnchor_\(paneIndex)", anchor: .bottom)
                    }
                }
            }
            .contentShape(Rectangle())
            .focusable()
            .focusEffectDisabled()
            .focused($focusedPaneState, equals: paneIndex)
            .onKeyPress { press in
                handleDirectKeyPress(press, session: session)
            }
            .onTapGesture {
                focusedPane = paneIndex
                focusedPaneState = paneIndex
            }

            Divider().overlay(Theme.borderLight)

            // Interactive Bottom Input Bar
            let askingPassword = isPasswordPrompt(session)
            HStack(spacing: 8) {
                Text("\(session.title) #")
                    .font(Theme.monoText(11, weight: .bold))
                    .foregroundStyle(Color(hex: selectedTheme.promptColorHex))

                if askingPassword {
                    SecureField("Remote host password / passphrase (press Enter to send)...", text: $inputCommand)
                        .font(Theme.monoText(12))
                        .textFieldStyle(.plain)
                        .onSubmit {
                            submitCommand(to: session)
                        }
                } else {
                    TextField("Enter command (or click terminal canvas to type directly)...", text: $inputCommand)
                        .font(Theme.monoText(12))
                        .textFieldStyle(.plain)
                        .onSubmit {
                            submitCommand(to: session)
                        }
                }

                // Quick keys
                HStack(spacing: 4) {
                    Button("Enter") {
                        submitCommand(to: session)
                    }
                    .buttonStyle(.bordered)
                    .font(.system(size: 11))

                    Button("Ctrl+C") {
                        session.sendControl(0x03)
                    }
                    .buttonStyle(.bordered)
                    .font(.system(size: 11))
                    .tint(Theme.pulseCrimson)
                    .help("Send SIGINT (Ctrl+C)")

                    Button("Ctrl+Z") {
                        session.sendControl(0x1A)
                    }
                    .buttonStyle(.bordered)
                    .font(.system(size: 11))
                    .help("Send SIGTSTP (Ctrl+Z) to exit Cisco config mode")

                    Button("Tab") {
                        session.sendControl(0x09)
                    }
                    .buttonStyle(.bordered)
                    .font(.system(size: 11))
                    .help("Send Tab Autocomplete")
                }
            }
            .padding(8)
            .background(Theme.cardBackground)
        }
        .overlay(
            state.terminalManager.splitMode != .single ?
            RoundedRectangle(cornerRadius: 0)
                .stroke(isFocused ? Theme.neonCyan.opacity(0.8) : Color.clear, lineWidth: 1.5)
            : nil
        )
    }

    private var emptySecondaryPanePlaceholder: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "square.split.2x1")
                .font(.system(size: 32))
                .foregroundStyle(.secondary.opacity(0.4))
            Text("Secondary Split Pane Empty")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Select an open session from the top menu or launch a new session.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: selectedTheme.backgroundColorHex).opacity(0.95))
    }

    private var emptySessionPlaceholder: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "terminal")
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(0.4))
            Text("No Active Terminal Session")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.secondary)
            Text("Open an SSH session, connect a USB serial console cable, launch a simulated router, or pick from the Profile Vault.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            HStack(spacing: 12) {
                Button(action: { showNewSessionSheet = true }) {
                    Label("New Terminal Session", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.cyanPulse)
                .foregroundStyle(Color.black)

                Button(action: { showProfileVaultSheet = true }) {
                    Label("Open Profile Vault", systemImage: "books.vertical.fill")
                }
                .buttonStyle(.bordered)
            }
            Spacer()
        }
    }

    // MARK: - New Session Modal

    private var newSessionModal: some View {
        VStack(spacing: 20) {
            HStack {
                Label("New Terminal Session", systemImage: "terminal.fill")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Button("Close") { showNewSessionSheet = false }
                    .buttonStyle(.plain)
            }

            Picker("Connection Mode", selection: $newSessionType) {
                Text("SSH").tag(0)
                Text("USB Serial Console").tag(1)
                Text("Simulated CLI").tag(2)
                Text("Local Shell").tag(3)
            }
            .pickerStyle(.segmented)

            VStack(spacing: 14) {
                if newSessionType == 0 {
                    // SSH Form
                    VStack(alignment: .leading, spacing: 6) {
                        Text("HOST IP OR DOMAIN")
                            .font(Theme.monoText(10, weight: .bold))
                            .foregroundStyle(.secondary)
                        TextField("192.168.1.1", text: $sshHost)
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("PORT")
                                .font(Theme.monoText(10, weight: .bold))
                                .foregroundStyle(.secondary)
                            TextField("22", text: $sshPort)
                                .textFieldStyle(.roundedBorder)
                        }
                        .frame(width: 80)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("USERNAME")
                                .font(Theme.monoText(10, weight: .bold))
                                .foregroundStyle(.secondary)
                            TextField("admin", text: $sshUser)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("PASSWORD / KEYCHAIN PASSPHRASE")
                            .font(Theme.monoText(10, weight: .bold))
                            .foregroundStyle(.secondary)
                        SecureField("Device password (auto-injected on prompt)", text: $sshPassword)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Local SSH Keys dropdown selector (MobaKeyGen)
                    let discoveredKeys = state.terminalManager.keyStudio.discoverLocalKeys()
                    if !discoveredKeys.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("SELECT LOCAL SSH KEY")
                                .font(Theme.monoText(10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $sshKeyPath) {
                                Text("Password only (no key)").tag("")
                                ForEach(discoveredKeys) { k in
                                    Text("\(k.name) (\(k.keyType))").tag(k.privateKeyPath)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("OR CUSTOM IDENTITY KEY PATH")
                            .font(Theme.monoText(10, weight: .bold))
                            .foregroundStyle(.secondary)
                        HStack {
                            TextField("~/.ssh/id_rsa or /path/to/key.pem", text: $sshKeyPath)
                                .textFieldStyle(.roundedBorder)
                            Button("Browse...") {
                                let panel = NSOpenPanel()
                                panel.allowsMultipleSelection = false
                                panel.canChooseDirectories = false
                                panel.canChooseFiles = true
                                if panel.runModal() == .OK, let url = panel.url {
                                    sshKeyPath = url.path
                                }
                            }
                            .font(.system(size: 11))
                        }
                    }

                    // Bastion / Jump Host (ProxyJump)
                    DisclosureGroup("Bastion Jump Host (ProxyJump)", isExpanded: $sshEnableJumpHost) {
                        VStack(spacing: 8) {
                            TextField("Jump Host (e.g. bastion.corp.net)", text: $sshJumpHost)
                                .textFieldStyle(.roundedBorder)
                            HStack(spacing: 8) {
                                TextField("Port", text: $sshJumpPort)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 70)
                                TextField("Jump Username", text: $sshJumpUser)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .font(Theme.monoText(10, weight: .bold))

                    // Legacy Network Hardware Ciphers Toggle
                    Toggle(isOn: $sshEnableLegacyCiphers) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Enable Legacy Network Ciphers")
                                .font(Theme.monoText(10, weight: .bold))
                            Text("Allows ssh-rsa, diffie-hellman, and 3des for older Cisco IOS 12/15, legacy switches & firewalls")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }

                } else if newSessionType == 1 {
                    // Direct POSIX USB Serial Form
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("DETECTED SERIAL PORT (/DEV/CU.*)")
                                .font(Theme.monoText(10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Refresh") {
                                state.terminalManager.refreshSerialPorts()
                            }
                            .font(.system(size: 10))
                        }

                        if state.terminalManager.availableSerialPorts.isEmpty {
                            Text("No USB serial devices detected. Connect a console cable or test with Simulated CLI.")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.solarAmber)
                                .padding(8)
                                .background(Theme.solarAmber.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        } else {
                            Picker("Port", selection: $selectedSerialPort) {
                                ForEach(state.terminalManager.availableSerialPorts) { port in
                                    Text(port.friendlyName).tag(port.devicePath)
                                }
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("BAUD RATE")
                                .font(Theme.monoText(10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $selectedBaudRate) {
                                ForEach(SerialDiscovery.standardBaudRates, id: \.self) { rate in
                                    Text("\(rate)").tag(rate)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("PARITY")
                                .font(Theme.monoText(10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $selectedParity) {
                                ForEach(SerialParity.allCases) { p in
                                    Text(p.rawValue).tag(p)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("FLOW CONTROL")
                                .font(Theme.monoText(10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $selectedFlowControl) {
                                ForEach(SerialFlowControl.allCases) { fc in
                                    Text(fc.rawValue).tag(fc)
                                }
                            }
                        }
                    }

                } else if newSessionType == 2 {
                    // Multi-Vendor Simulated CLI
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SIMULATED NETWORK VENDOR & HARDWARE")
                            .font(Theme.monoText(10, weight: .bold))
                            .foregroundStyle(.secondary)
                        Picker("Preset", selection: $selectedSimPreset) {
                            Text("Cisco IOS-XE (Catalyst 9300 Core)").tag("Catalyst 9300 Core")
                            Text("Arista EOS (7050X 100G Spine)").tag("Arista 7050X Spine")
                            Text("Juniper Junos (EX4300 Distribution)").tag("Juniper EX4300")
                        }
                        Text("Fully interactive offline CLI responding to authentic vendor show commands, configuration hierarchies, and context-sensitive help.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                } else {
                    // Local Shell
                    VStack(alignment: .leading, spacing: 6) {
                        Text("LOCAL MACOS SHELL")
                            .font(Theme.monoText(10, weight: .bold))
                            .foregroundStyle(.secondary)
                        Text("Spawns an interactive /bin/zsh shell session inside NexWave with your environment variables and network tools (ssh, ping, nc, nmap).")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(14)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Action Button
            Button(action: launchConfiguredSession) {
                Text("Start Connection")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.cyanPulse)
            .foregroundStyle(Color.black)
        }
        .padding(20)
        .frame(width: 480)
    }

    // MARK: - Profile Vault Modal

    private var profileVaultModal: some View {
        VStack(spacing: 16) {
            HStack {
                Label("Session Profile Vault", systemImage: "books.vertical.fill")
                    .font(.headline.bold())
                Spacer()
                Button("Close") { showProfileVaultSheet = false }
                    .buttonStyle(.plain)
            }

            // Search and Folder Filter
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search profiles by name, host, or user...", text: $vaultSearchText)
                    .textFieldStyle(.plain)

                Spacer()

                Picker("Folder", selection: $selectedVaultFolder) {
                    Text("All Folders").tag("All")
                    Text("Data Center").tag("Data Center")
                    Text("Campus Access").tag("Campus Access")
                    Text("Lab Rack").tag("Lab Rack")
                }
                .pickerStyle(.menu)
                .frame(width: 140)
            }
            .padding(8)
            .background(Theme.cardBackground)
            .cornerRadius(8)

            // Profiles List
            let filteredProfiles = state.terminalManager.savedProfiles.filter { p in
                (selectedVaultFolder == "All" || p.folder == selectedVaultFolder) &&
                (vaultSearchText.isEmpty || p.name.localizedCaseInsensitiveContains(vaultSearchText) || p.host.localizedCaseInsensitiveContains(vaultSearchText))
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(filteredProfiles) { profile in
                        HStack {
                            Circle()
                                .fill(Color(hex: profile.badgeColorHex))
                                .frame(width: 8, height: 8)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.name)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white)
                                HStack(spacing: 6) {
                                    Text(profile.folder)
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Theme.borderLight)
                                        .cornerRadius(3)
                                    Text(profile.connectionType.uppercased())
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(Theme.neonCyan)
                                    Text(profile.host.isEmpty ? profile.serialPath : "\(profile.username)@\(profile.host):\(profile.port)")
                                        .font(Theme.monoText(10))
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()

                            Button("Connect") {
                                state.terminalManager.launchProfile(profile)
                                showProfileVaultSheet = false
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.cyanPulse)
                            .foregroundStyle(Color.black)
                            .font(.system(size: 11, weight: .semibold))

                            Button(action: {
                                state.terminalManager.deleteProfile(id: profile.id)
                            }) {
                                Image(systemName: "trash")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(12)
                        .background(Theme.cardBackground)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderLight, lineWidth: 1))
                    }
                }
            }
            .frame(height: 280)
        }
        .padding(20)
        .frame(width: 540)
    }

    // MARK: - Paced Script Runner Modal

    private var pacedScriptRunnerModal: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Paced Configuration Script Runner", systemImage: "doc.text.fill")
                    .font(.headline.bold())
                Spacer()
                Button("Close") { showPacedPasteSheet = false }
                    .buttonStyle(.plain)
            }

            Text("Paste multi-line configuration blocks to transmit to the active session with controlled pacing to avoid switch buffer overflows.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $scriptText)
                .font(Theme.monoText(11))
                .frame(height: 180)
                .padding(4)
                .background(Theme.cardBackground)
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.borderLight, lineWidth: 1))

            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("INTER-LINE DELAY: \(Int(scriptDelayMs)) ms")
                        .font(Theme.monoText(10, weight: .bold))
                        .foregroundStyle(.secondary)
                    Slider(value: $scriptDelayMs, in: 10...500, step: 10)
                        .frame(width: 180)
                }

                Toggle("Pause on Error ('%')", isOn: $stopOnError)
                    .font(.system(size: 12))
            }

            if isRunningScript {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: Double(scriptCurrentLineIndex), total: Double(max(1, scriptTotalLines)))
                    Text("Executing line \(scriptCurrentLineIndex) of \(scriptTotalLines)...")
                        .font(Theme.monoText(10))
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                Button(isRunningScript ? "Running..." : "Execute Paced Script") {
                    runPacedScript()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.cyanPulse)
                .foregroundStyle(Color.black)
                .disabled(scriptText.isEmpty || isRunningScript)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    // MARK: - Actions & Helpers

    private func submitCommand(to targetSession: TerminalSession) {
        let cmd = inputCommand
        inputCommand = ""

        if state.terminalManager.isBroadcastEnabled {
            state.terminalManager.broadcastCommand(cmd)
        } else {
            targetSession.sendCommand(cmd)
        }
    }

    private func isPasswordPrompt(_ session: TerminalSession) -> Bool {
        guard let last = session.lines.last?.text.lowercased() else { return false }
        return last.contains("password:") || last.contains("password for") || last.contains("passphrase:")
    }

    private func handleDirectKeyPress(_ press: KeyPress, session: TerminalSession) -> KeyPress.Result {
        // Handle Ctrl combinations (Ctrl+C, Ctrl+D, Ctrl+Z, etc.)
        if press.modifiers.contains(.control) {
            let charStr = press.characters.lowercased()
            if let first = charStr.first, let ascii = first.asciiValue {
                if ascii >= 97 && ascii <= 122 {
                    let code = ascii - 96
                    session.sendControl(code)
                    return .handled
                }
            }
        }

        switch press.key {
        case .return:
            if state.terminalManager.isBroadcastEnabled {
                state.terminalManager.broadcastText("\r")
            } else {
                session.sendRawString("\r")
            }
            return .handled
        case .delete:
            if state.terminalManager.isBroadcastEnabled {
                state.terminalManager.broadcastText("\u{7F}")
            } else {
                session.sendRawString("\u{7F}")
            }
            return .handled
        case .escape:
            session.sendRawString("\u{1B}")
            return .handled
        case .tab:
            session.sendRawString("\t")
            return .handled
        case .upArrow:
            session.sendRawString("\u{1B}[A")
            return .handled
        case .downArrow:
            session.sendRawString("\u{1B}[B")
            return .handled
        case .rightArrow:
            session.sendRawString("\u{1B}[C")
            return .handled
        case .leftArrow:
            session.sendRawString("\u{1B}[D")
            return .handled
        default:
            if !press.characters.isEmpty && !press.modifiers.contains(.command) {
                if state.terminalManager.isBroadcastEnabled {
                    state.terminalManager.broadcastText(press.characters)
                } else {
                    session.sendRawString(press.characters)
                }
                return .handled
            }
        }
        return .ignored
    }

    private func executeMacro(_ macro: CommandMacro) {
        let cmd = macro.command
        if state.terminalManager.isBroadcastEnabled {
            state.terminalManager.broadcastCommand(cmd)
        } else {
            activeSession?.sendCommand(cmd)
        }
    }

    private func sendHardwareBreak() {
        if state.terminalManager.isBroadcastEnabled {
            state.terminalManager.broadcastBreak()
        } else {
            activeSession?.sendBreak()
        }
    }

    private func launchConfiguredSession() {
        showNewSessionSheet = false

        switch newSessionType {
        case 0:
            let portInt = Int(sshPort) ?? 22
            let key = sshKeyPath.isEmpty ? nil : sshKeyPath
            let pass = sshPassword.isEmpty ? nil : sshPassword
            let jump: SSHJumpConfig? = (sshEnableJumpHost && !sshJumpHost.isEmpty) ?
                SSHJumpConfig(host: sshJumpHost, port: Int(sshJumpPort) ?? 22, username: sshJumpUser) : nil

            state.terminalManager.openSSHSession(
                host: sshHost,
                port: portInt,
                username: sshUser,
                identityFile: key,
                password: pass,
                jumpHost: jump,
                enableLegacyCiphers: sshEnableLegacyCiphers
            )
        case 1:
            let path = selectedSerialPort.isEmpty ? "/dev/cu.usbserial-001" : selectedSerialPort
            state.terminalManager.openSerialSession(
                devicePath: path,
                baudRate: selectedBaudRate,
                dataBits: selectedDataBits,
                parity: selectedParity,
                stopBits: selectedStopBits,
                flowControl: selectedFlowControl
            )
        case 2:
            state.terminalManager.openSimulatedSession(preset: selectedSimPreset)
        default:
            state.terminalManager.openLocalShell()
        }
    }

    private func runPacedScript() {
        guard let session = activeSession else { return }
        let rawLines = scriptText.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !rawLines.isEmpty else { return }

        isRunningScript = true
        scriptTotalLines = rawLines.count
        scriptCurrentLineIndex = 0

        Task {
            for (idx, line) in rawLines.enumerated() {
                guard isRunningScript else { break }
                await MainActor.run {
                    scriptCurrentLineIndex = idx + 1
                    session.sendCommand(line)
                }
                try? await Task.sleep(nanoseconds: UInt64(scriptDelayMs * 1_000_000))
            }
            await MainActor.run {
                isRunningScript = false
                showPacedPasteSheet = false
                scriptText = ""
            }
        }
    }

    private func updatePTYDimensions() {
        // Approximate character columns and rows from standard 80x24 base
        let cols = max(80, Int(1000.0 / (fontSize * 0.6)))
        let rows = max(24, Int(600.0 / (fontSize * 1.2)))
        activeSession?.resize(cols: cols, rows: rows)
    }

    private func exportTranscript() {
        guard let session = activeSession else { return }
        let text = session.exportSessionLog()
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "session_\(session.title.replacingOccurrences(of: "@", with: "_")).log"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func timestampString(for date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        return "[\(df.string(from: date))]"
    }

    private func colorForSpan(_ style: ANSIStyle) -> Color {
        if let fg = style.foreground {
            return Color(red: Double(fg.r) / 255.0, green: Double(fg.g) / 255.0, blue: Double(fg.b) / 255.0)
        }
        return Color(hex: selectedTheme.foregroundColorHex)
    }

    private func backgroundColorForSpan(_ style: ANSIStyle) -> Color {
        if let bg = style.background {
            return Color(red: Double(bg.r) / 255.0, green: Double(bg.g) / 255.0, blue: Double(bg.b) / 255.0)
        }
        return Color.clear
    }

    // MARK: - MobaXterm Collapsible Session Tree & Quick Connect Sidebar

    private var sessionTreeSidebar: some View {
        VStack(spacing: 0) {
            // Quick Connect Card
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Quick Connect", systemImage: "bolt.fill")
                        .font(Theme.monoText(10, weight: .bold))
                        .foregroundStyle(Theme.neonCyan)
                    Spacer()
                    Button(action: { showNewSessionSheet = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.cyanPulse)
                    }
                    .buttonStyle(.plain)
                    .help("New Connection Wizard")
                }

                HStack(spacing: 4) {
                    TextField("root@185.81.99.104", text: $quickConnectInput)
                        .textFieldStyle(.plain)
                        .font(Theme.monoText(11))
                        .onSubmit {
                            performQuickConnect()
                        }

                    if !quickConnectInput.isEmpty {
                        Button("Go") {
                            performQuickConnect()
                        }
                        .font(Theme.monoText(9, weight: .bold))
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.cyanPulse)
                        .foregroundStyle(Color.black)
                    }
                }
                .padding(6)
                .background(Theme.surfaceBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.borderLight, lineWidth: 1))
            }
            .padding(10)
            .background(Theme.cardBackground)

            Divider().overlay(Theme.borderLight)

            // Hierarchical Folder Tree of Saved Sessions
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(["Data Center", "Campus Access", "WAN Edge", "Lab Rack", "General"], id: \.self) { folder in
                        let folderProfiles = state.terminalManager.savedProfiles.filter { $0.folder == folder }
                        if !folderProfiles.isEmpty {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 4) {
                                    Image(systemName: "folder.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Theme.solarAmber)
                                    Text(folder.uppercased())
                                        .font(Theme.monoText(9, weight: .bold))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(folderProfiles.count)")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary.opacity(0.6))
                                }
                                .padding(.horizontal, 8)
                                .padding(.top, 4)

                                ForEach(folderProfiles) { profile in
                                    Button(action: {
                                        state.terminalManager.launchProfile(profile)
                                    }) {
                                        HStack(spacing: 6) {
                                            Circle()
                                                .fill(Color(hex: profile.badgeColorHex))
                                                .frame(width: 6, height: 6)
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(profile.name)
                                                    .font(Theme.monoText(10, weight: .semibold))
                                                    .lineLimit(1)
                                                Text(profile.host.isEmpty ? profile.serialPath : "\(profile.username)@\(profile.host)")
                                                    .font(.system(size: 9))
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                            Spacer()
                                        }
                                        .padding(.vertical, 4)
                                        .padding(.horizontal, 8)
                                        .background(Theme.cardBackground.opacity(0.7))
                                        .clipShape(RoundedRectangle(cornerRadius: 5))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 6)
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            Divider().overlay(Theme.borderLight)

            // MobaXterm Bottom Utilities Strip
            HStack(spacing: 6) {
                Button(action: { showSSHKeyStudioSheet = true }) {
                    VStack(spacing: 2) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 11))
                        Text("Keys")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help("SSH Key Studio & Generator (MobaKeyGen)")

                Button(action: { showSSHTunnelsSheet = true }) {
                    VStack(spacing: 2) {
                        Image(systemName: "arrow.triangle.swap")
                            .font(.system(size: 11))
                        Text("Tunnels")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help("SSH Port Forwarding & Tunnels (MobaSSHTunnel)")

                Button(action: { showProfileVaultSheet = true }) {
                    VStack(spacing: 2) {
                        Image(systemName: "books.vertical.fill")
                            .font(.system(size: 11))
                        Text("Vault")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help("Profile Vault")
            }
            .padding(8)
            .background(Theme.surfaceBackground)
        }
        .background(Theme.surfaceBackground.opacity(0.95))
    }

    private func performQuickConnect() {
        let input = quickConnectInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }

        var user = "root"
        var host = input
        var port = 22

        if host.contains("@") {
            let parts = host.components(separatedBy: "@")
            user = parts[0]
            host = parts[1]
        }

        if host.contains(":") {
            let parts = host.components(separatedBy: ":")
            host = parts[0]
            if let p = Int(parts[1]) {
                port = p
            }
        }

        state.terminalManager.openSSHSession(
            host: host,
            port: port,
            username: user,
            autoConnect: true
        )
        quickConnectInput = ""
    }

    // MARK: - SSH Key Studio Modal (MobaKeyGen)

    private var localDiscoveredSSHKeys: [SSHKeyInfo] {
        state.terminalManager.keyStudio.discoverLocalKeys()
    }

    private var sshKeyStudioModal: some View {
        VStack(spacing: 16) {
            sshKeyStudioHeader
            sshKeyStudioDiscoveredKeys(localKeys: localDiscoveredSSHKeys)
            Divider().overlay(Theme.borderLight)
            sshKeyStudioGenerateForm
            Divider().overlay(Theme.borderLight)
            sshKeyStudioDeployForm(localKeys: localDiscoveredSSHKeys)
        }
        .padding(20)
        .frame(width: 580)
    }

    private var sshKeyStudioHeader: some View {
        VStack(spacing: 8) {
            HStack {
                Label("SSH Key Studio & Generator (MobaKeyGen)", systemImage: "key.fill")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Button("Close") { showSSHKeyStudioSheet = false }
                    .buttonStyle(.plain)
            }

            if let toast = keyGenSuccessToast {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.emeraldHealthy)
                    Text(toast)
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                }
                .padding(8)
                .background(Theme.emeraldHealthy.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func sshKeyStudioDiscoveredKeys(localKeys: [SSHKeyInfo]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("LOCAL SSH KEYPAIRS (~/.ssh/)")
                    .font(Theme.monoText(10, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(localKeys.count) found")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if localKeys.isEmpty {
                Text("No SSH keys found in ~/.ssh/. Generate an Ed25519 or RSA key below to authenticate securely without passwords.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.solarAmber)
                    .padding(8)
                    .background(Theme.solarAmber.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(localKeys) { key in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(key.name)
                                            .font(Theme.monoText(11, weight: .bold))
                                        Text(key.keyType)
                                            .font(Theme.monoText(9, weight: .bold))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(key.keyType == "Ed25519" ? Theme.neonCyan.opacity(0.2) : Theme.solarAmber.opacity(0.2))
                                            .foregroundStyle(key.keyType == "Ed25519" ? Theme.neonCyan : Theme.solarAmber)
                                            .clipShape(Capsule())
                                    }
                                    Text(key.fingerprint)
                                        .font(Theme.monoText(9))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Button("Copy Public Key") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(key.publicKeyString, forType: .string)
                                    keyGenSuccessToast = "Public key for \(key.name) copied to clipboard!"
                                }
                                .font(.system(size: 10))
                                .buttonStyle(.bordered)

                                Button("Use Key") {
                                    sshKeyPath = key.privateKeyPath
                                    showSSHKeyStudioSheet = false
                                    showNewSessionSheet = true
                                }
                                .font(.system(size: 10))
                                .buttonStyle(.borderedProminent)
                                .tint(Theme.cyanPulse)
                                .foregroundStyle(Color.black)
                            }
                            .padding(8)
                            .background(Theme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                .frame(maxHeight: 130)
            }
        }
    }

    private var sshKeyStudioGenerateForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GENERATE NEW SSH KEYPAIR")
                .font(Theme.monoText(10, weight: .bold))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Picker("Algorithm", selection: $newKeyType) {
                    Text("Ed25519 (Recommended)").tag("Ed25519")
                    Text("RSA 4096-bit (Legacy)").tag("RSA")
                }
                .pickerStyle(.segmented)

                TextField("Comment (e.g. user@mac)", text: $newKeyComment)
                    .textFieldStyle(.roundedBorder)

                Button("Generate") {
                    generateNewKeyPair()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.cyanPulse)
                .foregroundStyle(Color.black)
            }
        }
    }

    private func generateNewKeyPair() {
        do {
            let newKey: SSHKeyInfo
            if newKeyType == "Ed25519" {
                newKey = try state.terminalManager.keyStudio.generateEd25519Key(comment: newKeyComment)
            } else {
                newKey = try state.terminalManager.keyStudio.generateRSAKey(comment: newKeyComment)
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(newKey.publicKeyString, forType: .string)
            keyGenSuccessToast = "Generated \(newKey.name)! Public key automatically copied to clipboard."
        } catch {
            keyGenSuccessToast = "Error: \(error.localizedDescription)"
        }
    }

    private func sshKeyStudioDeployForm(localKeys: [SSHKeyInfo]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DEPLOY PUBLIC KEY TO REMOTE SERVER (ssh-copy-id)")
                .font(Theme.monoText(10, weight: .bold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("Server Host (IP / Domain)", text: $deployHost)
                    .textFieldStyle(.roundedBorder)
                TextField("Port", text: $deployPort)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                TextField("User", text: $deployUser)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)

                Button(isDeployingKey ? "Deploying..." : "Deploy Key") {
                    if let firstKey = localKeys.first {
                        deploySelectedKey(firstKey: firstKey)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(deployHost.isEmpty || localKeys.isEmpty || isDeployingKey)
            }

            if let msg = deployStatusMsg {
                Text(msg)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.neonCyan)
            }
        }
    }

    private func deploySelectedKey(firstKey: SSHKeyInfo) {
        guard !deployHost.isEmpty else { return }
        isDeployingKey = true
        let host = deployHost
        let port = Int(deployPort) ?? 22
        let user = deployUser
        let path = firstKey.publicKeyPath
        Task {
            do {
                let res = try await state.terminalManager.keyStudio.deployKeyToServer(
                    publicKeyPath: path,
                    host: host,
                    port: port,
                    username: user
                )
                await MainActor.run {
                    deployStatusMsg = res
                    isDeployingKey = false
                }
            } catch {
                await MainActor.run {
                    deployStatusMsg = error.localizedDescription
                    isDeployingKey = false
                }
            }
        }
    }

    // MARK: - SSH Port Forwarding & Tunnels Modal (MobaSSHTunnel)

    private var sshTunnelsModal: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("SSH Port Forwarding & Tunnels (MobaSSHTunnel)", systemImage: "arrow.triangle.swap")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Button("Close") { showSSHTunnelsSheet = false }
                    .buttonStyle(.plain)
            }

            sshTunnelsList
            Divider().overlay(Theme.borderLight)
            sshTunnelsCreateForm
        }
        .padding(20)
        .frame(width: 580)
    }

    private var sshTunnels: [SSHTunnelConfig] {
        state.terminalManager.tunnelManager.tunnels
    }

    private var sshTunnelsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ACTIVE & SAVED TUNNELS")
                .font(Theme.monoText(10, weight: .bold))
                .foregroundStyle(.secondary)

            if sshTunnels.isEmpty {
                Text("No SSH tunnels configured. Create a Local, Remote, or Dynamic SOCKS5 tunnel below.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(8)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(sshTunnels) { tunnel in
                            HStack {
                                Circle()
                                    .fill(tunnel.isActive ? Theme.emeraldHealthy : Color.gray.opacity(0.5))
                                    .frame(width: 8, height: 8)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(tunnel.name)
                                            .font(Theme.monoText(11, weight: .bold))
                                        Text(tunnel.tunnelType.flag)
                                            .font(Theme.monoText(9, weight: .bold))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Theme.cyanPulse.opacity(0.15))
                                            .foregroundStyle(Theme.cyanPulse)
                                            .clipShape(RoundedRectangle(cornerRadius: 3))
                                    }

                                    Text(tunnel.tunnelType == .dynamicSOCKS5 ?
                                         "localhost:\(tunnel.localPort) (SOCKS5 Proxy) via \(tunnel.sshUsername)@\(tunnel.sshHost)" :
                                         "localhost:\(tunnel.localPort) -> \(tunnel.destinationHost):\(tunnel.destinationPort) via \(tunnel.sshUsername)@\(tunnel.sshHost)")
                                        .font(Theme.monoText(9))
                                        .foregroundStyle(.secondary)

                                    if let err = tunnel.lastError {
                                        Text(err)
                                            .font(.system(size: 9))
                                            .foregroundStyle(Theme.crimsonCritical)
                                    }
                                }

                                Spacer()

                                Button(tunnel.isActive ? "Stop" : "Start") {
                                    if tunnel.isActive {
                                        state.terminalManager.tunnelManager.stopTunnel(id: tunnel.id)
                                    } else {
                                        try? state.terminalManager.tunnelManager.startTunnel(id: tunnel.id)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .tint(tunnel.isActive ? Theme.crimsonCritical : Theme.emeraldHealthy)

                                Button(action: {
                                    state.terminalManager.tunnelManager.deleteTunnel(id: tunnel.id)
                                }) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(8)
                            .background(Theme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                .frame(maxHeight: 150)
            }
        }
    }

    private var sshTunnelsCreateForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ADD NEW SSH TUNNEL")
                .font(Theme.monoText(10, weight: .bold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Picker("Type", selection: $tunnelTypeInput) {
                    ForEach(SSHTunnelType.allCases) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.menu)

                TextField("Tunnel Name (optional)", text: $tunnelNameInput)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 8) {
                TextField("Local Port", text: $tunnelLocalPortInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)

                if tunnelTypeInput != .dynamicSOCKS5 {
                    TextField("Remote Host", text: $tunnelDestHostInput)
                        .textFieldStyle(.roundedBorder)
                    TextField("Remote Port", text: $tunnelDestPortInput)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                }
            }

            HStack(spacing: 8) {
                TextField("SSH Host (Gateway)", text: $tunnelSSHHostInput)
                    .textFieldStyle(.roundedBorder)
                TextField("Port", text: $tunnelSSHPortInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                TextField("User", text: $tunnelSSHUserInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)

                Button("Save Tunnel") {
                    saveNewTunnel()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.cyanPulse)
                .foregroundStyle(Color.black)
                .disabled(tunnelSSHHostInput.isEmpty)
            }
        }
    }

    private func saveNewTunnel() {
        guard !tunnelSSHHostInput.isEmpty else { return }
        let newTunnel = SSHTunnelConfig(
            name: tunnelNameInput,
            tunnelType: tunnelTypeInput,
            localPort: Int(tunnelLocalPortInput) ?? 8080,
            destinationHost: tunnelDestHostInput,
            destinationPort: Int(tunnelDestPortInput) ?? 80,
            sshHost: tunnelSSHHostInput,
            sshPort: Int(tunnelSSHPortInput) ?? 22,
            sshUsername: tunnelSSHUserInput,
            sshIdentityFile: tunnelIdentityKeyInput.isEmpty ? nil : tunnelIdentityKeyInput
        )
        state.terminalManager.tunnelManager.saveTunnel(newTunnel)
        tunnelNameInput = ""
        tunnelSSHHostInput = ""
    }
}

