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
    @State private var showFileTransferSheet: Bool = false
    @State private var copyToastMessage: String? = nil
    @State private var localFilePathToUpload: String = ""
    @State private var remoteUploadPath: String = "/tmp/"
    @State private var isTransferringFile: Bool = false
    @State private var transferStatusMessage: String? = nil
    // Global & Persisted Terminal Display Preferences
    @AppStorage("terminal_font_size") private var globalFontSize: Double = 12.0
    @AppStorage("terminal_font_family") private var globalFontFamily: String = "SF Mono (System)"
    @AppStorage("terminal_theme") private var globalThemeName: String = TerminalTheme.obsidian.rawValue
    @AppStorage("terminal_cursor_style") private var globalCursorStyle: String = TerminalCursorStyle.block.rawValue
    @AppStorage("terminal_cursor_blink") private var globalCursorBlink: Bool = true
    @AppStorage("terminal_line_spacing") private var globalLineSpacing: Double = 2.0
    @AppStorage("terminal_max_buffer") private var globalMaxBuffer: Int = 5000

    @State private var autoScroll: Bool = true
    @State private var showTerminalSettingsSheet: Bool = false
    @State private var settingsTargetSessionId: UUID? = nil
    @State private var settingsScope: Int = 0 // 0: Global Defaults, 1: Active Tab Override
    @State private var showMacrosBar: Bool = false

    private var targetSettingsSession: TerminalSession? {
        if let id = settingsTargetSessionId {
            return state.terminalManager.sessions.first(where: { $0.id == id }) ?? activeSession
        }
        return activeSession
    }

    private func effectiveFontSize(for session: TerminalSession) -> CGFloat {
        session.fontSizeOverride ?? CGFloat(globalFontSize)
    }

    private func effectiveFontFamily(for session: TerminalSession) -> String {
        session.fontFamilyOverride ?? globalFontFamily
    }

    private func effectiveTheme(for session: TerminalSession) -> TerminalTheme {
        if let ov = session.themeOverride { return ov }
        return TerminalTheme(rawValue: globalThemeName) ?? .obsidian
    }

    private func effectiveCursorStyle(for session: TerminalSession) -> TerminalCursorStyle {
        if let ov = session.cursorStyleOverride { return ov }
        return TerminalCursorStyle(rawValue: globalCursorStyle) ?? .block
    }

    private var selectedTheme: TerminalTheme {
        get {
            if let s = activeSession { return effectiveTheme(for: s) }
            return TerminalTheme(rawValue: globalThemeName) ?? .obsidian
        }
        nonmutating set {
            if let s = activeSession, s.themeOverride != nil {
                s.themeOverride = newValue
            } else {
                globalThemeName = newValue.rawValue
            }
        }
    }

    private var fontSize: CGFloat {
        get {
            if let s = activeSession { return effectiveFontSize(for: s) }
            return CGFloat(globalFontSize)
        }
        nonmutating set {
            if let s = activeSession, s.fontSizeOverride != nil {
                s.fontSizeOverride = newValue
            } else {
                globalFontSize = Double(newValue)
            }
        }
    }
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
    @State private var sshHost: String = "170.75.170.64"
    @State private var sshPort: String = "22"
    @State private var sshUser: String = "ubuntu"
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

    // Saved Sessions Tree & Dynamic Folder States
    @State private var sessionSearchQuery: String = ""
    @State private var selectedProtocolFilter: String = "ALL" // "ALL", "SSH", "SERIAL", "LOCAL"
    @State private var showFolderEditorSheet: Bool = false
    @State private var folderEditingId: UUID? = nil
    @State private var folderNameInput: String = ""
    @State private var folderParentIdInput: UUID? = nil
    @State private var folderColorHexInput: String = "#F59E0B"
    @State private var profileEditingId: UUID? = nil
    @State private var showEditProfileSheet: Bool = false
    @State private var sessionFolderTargetId: UUID? = nil
    @State private var newSessionTargetFolderId: UUID? = nil
    @State private var showBookmarkSessionSheet: Bool = false
    @State private var sessionToBookmark: TerminalSession? = nil
    @State private var bookmarkNameInput: String = ""
    @State private var bookmarkFolderId: UUID? = nil
    @State private var bookmarkTagsInput: String = ""
    @State private var bookmarkNotesInput: String = ""
    @State private var editingProfileName: String = ""
    @State private var editingProfileFolderId: UUID? = nil
    @State private var editingProfileHost: String = ""
    @State private var editingProfilePort: String = "22"
    @State private var editingProfileUsername: String = "admin"
    @State private var editingProfileIdentityFile: String = ""
    @State private var editingProfileConnectionType: String = "ssh"
    @State private var editingProfileSerialPath: String = ""
    @State private var editingProfileSerialBaud: Int = 9600
    @State private var editingProfileJumpHost: String = ""
    @State private var editingProfileJumpPort: String = "22"
    @State private var editingProfileJumpUser: String = "admin"
    @State private var editingProfileEnableLegacyCiphers: Bool = false
    @State private var editingProfileBadgeColorHex: String = "#00E5FF"
    @State private var editingProfileTags: String = ""
    @State private var editingProfileNotes: String = ""

    // SSH Key Studio States (MobaKeyGen)
    @State private var newKeyType: String = "Ed25519"
    @State private var newKeyComment: String = "saeid@mac"
    @State private var keyGenSuccessToast: String? = nil
    @State private var selectedKeyForDeploy: String = ""
    @State private var deployHost: String = ""
    @State private var deployPort: String = "22"
    @State private var deployUser: String = "ubuntu"
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

    // Dual-Pane Interactive SFTP Browser Engine
    @State private var remoteFileBrowser = RemoteFileBrowserEngine()
    @State private var showFileQuickPreview: Bool = false
    @State private var newRemoteDirName: String = ""
    @State private var showNewDirAlert: Bool = false

    // SSH Key Studio Tabs (0: Key Gen, 1: Known Hosts Inspector)
    @State private var keyStudioTab: Int = 0
    @State private var newKeyPassphrase: String = ""

    // Modem Signal Inspector Sheet
    @State private var showModemSignalSheet: Bool = false
    @State private var modemStatus: SerialModemStatus = SerialModemStatus()

    // Known Hosts & Tunnel Latency Cache
    @State private var knownHostsSearch: String = ""
    @State private var knownHostsList: [KnownHostEntry] = []
    @State private var knownHostsStatusMsg: String? = nil
    @State private var tunnelLatencies: [UUID: Double] = [:]

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

                // Command Macros Strip (collapsible)
                if showMacrosBar {
                    commandSnippetsBar
                    Divider().overlay(Theme.borderLight)
                }

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
        .sheet(isPresented: $showFileTransferSheet) {
            fileTransferModal
                .onAppear {
                    remoteFileBrowser.refreshLocalDirectory()
                    if let s = activeSession, case .ssh(let host, let port, let username, let identityFile, let password, let jumpHost, _) = s.connectionType {
                        remoteFileBrowser.refreshRemoteDirectory(
                            host: host,
                            port: port,
                            username: username,
                            identityFile: identityFile,
                            password: password,
                            jumpHost: jumpHost
                        )
                    }
                }
        }
        .sheet(isPresented: $showModemSignalSheet) {
            modemSignalModal
        }
        .sheet(isPresented: $showTerminalSettingsSheet) {
            terminalSettingsModal
        }
        .sheet(isPresented: $showFolderEditorSheet) {
            folderEditorModal
        }
        .sheet(isPresented: $showEditProfileSheet) {
            editProfileModal
        }
        .sheet(isPresented: $showBookmarkSessionSheet) {
            bookmarkSessionModal
        }
        .overlay(alignment: .top) {
            if let toast = copyToastMessage {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.emeraldHealthy)
                    Text(toast)
                        .font(Theme.monoText(11, weight: .bold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Theme.cardBackground)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Theme.emeraldHealthy.opacity(0.5), lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
                .padding(.top, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(
            ZStack {
                Button("") { showNewSessionSheet = true }
                    .keyboardShortcut("t", modifiers: .command)
                Button("") { if let id = state.terminalManager.activeSessionId { state.terminalManager.closeSession(id: id) } }
                    .keyboardShortcut("w", modifiers: .command)
                Button("") { activeSession?.clear() }
                    .keyboardShortcut("k", modifiers: .command)
                Button("") { isSearching.toggle(); if !isSearching { searchQuery = "" } }
                    .keyboardShortcut("f", modifiers: .command)
                Button("") { if fontSize < 24 { fontSize += 1; updatePTYDimensions() } }
                    .keyboardShortcut("+", modifiers: .command)
                Button("") { if fontSize < 24 { fontSize += 1; updatePTYDimensions() } }
                    .keyboardShortcut("=", modifiers: .command)
                Button("") { if fontSize > 9 { fontSize -= 1; updatePTYDimensions() } }
                    .keyboardShortcut("-", modifiers: .command)
                Button("") { fontSize = 12; updatePTYDimensions() }
                    .keyboardShortcut("0", modifiers: .command)
                Button("") { state.terminalManager.isBroadcastEnabled.toggle() }
                    .keyboardShortcut("b", modifiers: [.command, .shift])
                Button("") { if let s = activeSession { copyAllTranscript(s) } }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                Button("") { showSSHTunnelsSheet.toggle() }
                    .keyboardShortcut("u", modifiers: [.command, .shift])
                Button("") { showProfileVaultSheet.toggle() }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
            }
            .opacity(0)
            .allowsHitTesting(false)
        )
        .onAppear {
            if selectedSerialPort.isEmpty, let firstPort = state.terminalManager.availableSerialPorts.first {
                selectedSerialPort = firstPort.devicePath
            }
        }
    }

    // MARK: - Helpers

    private func layoutIcon(for mode: TerminalSplitMode) -> String {
        switch mode {
        case .single: return "rectangle"
        case .vertical: return "rectangle.split.2x1"
        case .horizontal: return "rectangle.split.1x2"
        case .quadGrid: return "rectangle.split.2x2"
        }
    }

    private func layoutTooltip(for mode: TerminalSplitMode) -> String {
        switch mode {
        case .single: return "Single Pane"
        case .vertical: return "Side-by-Side Split"
        case .horizontal: return "Stacked Split"
        case .quadGrid: return "2x2 Quad Grid"
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 12) {
            // Left Group: Sidebar Toggle & Clean Title
            HStack(spacing: 10) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        state.terminalManager.isSidebarExpanded.toggle()
                    }
                }) {
                    Image(systemName: state.terminalManager.isSidebarExpanded ? "sidebar.left" : "sidebar.leading")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(state.terminalManager.isSidebarExpanded ? Theme.neonCyan : .secondary)
                        .frame(width: 28, height: 28)
                        .background(state.terminalManager.isSidebarExpanded ? Theme.neonCyan.opacity(0.12) : Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(state.terminalManager.isSidebarExpanded ? Theme.neonCyan.opacity(0.3) : Theme.borderLight, lineWidth: 0.75)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Toggle MobaXterm Session Tree Sidebar")

                // Modern Clean Title
                HStack(spacing: 6) {
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.neonCyan)

                    Text("Terminal & Console")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                .frame(height: 28)
            }
            .frame(height: 28)

            Spacer(minLength: 12)

            // Right Group: Clustered Controls & Pro Tools
            HStack(spacing: 8) {
                // 1. Layout Mode Switcher (Sleek Segmented Pill)
                HStack(spacing: 2) {
                    ForEach(TerminalSplitMode.allCases) { mode in
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                state.terminalManager.splitMode = mode
                            }
                        }) {
                            Image(systemName: layoutIcon(for: mode))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(state.terminalManager.splitMode == mode ? Theme.neonCyan : .secondary)
                                .frame(width: 26, height: 24)
                                .background(state.terminalManager.splitMode == mode ? Theme.neonCyan.opacity(0.18) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(layoutTooltip(for: mode))
                    }
                }
                .padding(2)
                .frame(height: 28)
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.borderLight, lineWidth: 0.75))

                // 2. Broadcast Multi-Exec Toggle Pill
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        state.terminalManager.isBroadcastEnabled.toggle()
                    }
                }) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(state.terminalManager.isBroadcastEnabled ? Theme.crimsonCritical : Color.secondary.opacity(0.4))
                            .frame(width: 6, height: 6)
                        Text("Broadcast")
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(state.terminalManager.isBroadcastEnabled ? Theme.crimsonCritical.opacity(0.18) : Theme.cardBackground)
                    .foregroundStyle(state.terminalManager.isBroadcastEnabled ? Theme.crimsonCritical : .secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(state.terminalManager.isBroadcastEnabled ? Theme.crimsonCritical.opacity(0.6) : Theme.borderLight, lineWidth: 0.75)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)
                .help("Broadcast keystrokes to all open sessions (Cmd+Shift+B)")

                // 2b. Active Recording Pulsing Pill (Visible only during active recording)
                if let s = activeSession, s.isRecording {
                    Button(action: {
                        toggleRecording(for: s)
                    }) {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(Theme.crimsonCritical)
                                .frame(width: 6, height: 6)
                            Text("REC")
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(Theme.crimsonCritical)
                            Image(systemName: "stop.fill")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 28)
                        .background(Theme.crimsonCritical.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(Theme.crimsonCritical.opacity(0.7), lineWidth: 0.75)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .fixedSize(horizontal: true, vertical: false)
                    .help("Recording active — click to stop and export .cast file")
                }

                // 3. Appearance & Typography Capsule ([-], Size, [+], Theme, Settings)
                HStack(spacing: 4) {
                    Button(action: { if fontSize > 10 { fontSize -= 1; updatePTYDimensions() } }) {
                        Image(systemName: "minus")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 18, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Decrease font size (Cmd+-)")

                    Text("\(Int(fontSize))")
                        .font(Theme.monoText(10.5, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 18, height: 22)

                    Button(action: { if fontSize < 24 { fontSize += 1; updatePTYDimensions() } }) {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 18, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Increase font size (Cmd++)")

                    Rectangle()
                        .fill(Theme.borderLight)
                        .frame(width: 1, height: 14)
                        .padding(.horizontal, 2)

                    // Real dynamic theme palette indicator light (never tinted white by AppKit)
                    Button(action: {
                        let all = TerminalTheme.allCases
                        if let idx = all.firstIndex(of: selectedTheme) {
                            let nextIdx = (idx + 1) % all.count
                            selectedTheme = all[nextIdx]
                        }
                    }) {
                        Circle()
                            .fill(Color(hex: selectedTheme.promptColorHex))
                            .frame(width: 8, height: 8)
                            .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 0.75))
                            .shadow(color: Color(hex: selectedTheme.promptColorHex).opacity(0.85), radius: 3)
                    }
                    .buttonStyle(.plain)
                    .help("Theme color indicator: \(selectedTheme.rawValue) (Click to cycle)")

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
                        Text("\(selectedTheme.rawValue) ▾")
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .frame(height: 22)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize(horizontal: true, vertical: false)

                    Rectangle()
                        .fill(Theme.borderLight)
                        .frame(width: 1, height: 14)
                        .padding(.horizontal, 2)

                    Button(action: {
                        settingsTargetSessionId = activeSession?.id
                        showTerminalSettingsSheet = true
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 10.5, weight: .medium))
                            if activeSession?.hasCustomOverrides == true {
                                Circle()
                                    .fill(Theme.neonCyan)
                                    .frame(width: 5, height: 5)
                            }
                        }
                        .foregroundStyle(activeSession?.hasCustomOverrides == true ? Theme.neonCyan : .secondary)
                        .frame(width: 20, height: 22)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Configure Font Family, Cursor Style, Blinking, Line Spacing, and Colors")
                }
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.borderLight, lineWidth: 0.75))

                // 4. Tools Pro Dropdown Menu
                Menu {
                    Section("SSH & File Transfer") {
                        Button(action: {
                            keyStudioTab = 0
                            showSSHKeyStudioSheet = true
                        }) {
                            Label("SSH Key Studio (MobaKeyGen)", systemImage: "key.fill")
                        }
                        Button(action: {
                            keyStudioTab = 1
                            showSSHKeyStudioSheet = true
                        }) {
                            Label("SSH Known Hosts Inspector", systemImage: "shield.lefthalf.filled")
                        }
                        Button(action: { showSSHTunnelsSheet = true }) {
                            Label("SSH Tunnels & Port Forwarding", systemImage: "arrow.triangle.swap")
                        }
                        if let s = activeSession, case .ssh = s.connectionType {
                            Button(action: { showFileTransferSheet = true }) {
                                Label("SFTP / SCP File Transfer", systemImage: "arrow.up.arrow.down.square")
                            }
                        }
                    }

                    Section("Automation & Diagnostics") {
                        Button(action: {
                            if let s = activeSession {
                                toggleRecording(for: s)
                            }
                        }) {
                            Label(activeSession?.isRecording == true ? "Stop Asciinema Recording" : "Record Session (.cast)",
                                  systemImage: activeSession?.isRecording == true ? "stop.circle.fill" : "record.circle")
                        }
                        if let s = activeSession, case .serial = s.connectionType {
                            Button(action: { showModemSignalSheet = true }) {
                                Label("Modem Signal Lines (DTR/RTS)", systemImage: "waveform.path.badge.plus")
                            }
                        }
                        Button(action: sendHardwareBreak) {
                            Label("Send Hardware Break (ROMMON)", systemImage: "bolt.badge.clock")
                        }
                        Button(action: { showPacedPasteSheet = true }) {
                            Label("Paced Script Runner", systemImage: "doc.text.fill")
                        }
                        Button(action: { showProfileVaultSheet = true }) {
                            Label("Profile Vault", systemImage: "books.vertical.fill")
                        }
                    }

                    Section("External Terminal Bridge") {
                        if let session = activeSession, case .ssh(let host, let port, let user, _, _, _, _) = session.connectionType {
                            Button("Open in macOS Terminal") {
                                let cmd = ExternalTerminalBridge.shared.sshCommand(host: host, port: port, username: user)
                                ExternalTerminalBridge.shared.launchInTerminalApp(command: cmd)
                            }
                            if ExternalTerminalBridge.shared.isITermInstalled {
                                Button("Open in iTerm2") {
                                    let cmd = ExternalTerminalBridge.shared.sshCommand(host: host, port: port, username: user)
                                    ExternalTerminalBridge.shared.launchInITerm2(command: cmd)
                                }
                            }
                            Button("Copy SSH Command") {
                                let cmd = ExternalTerminalBridge.shared.sshCommand(host: host, port: port, username: user)
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(cmd, forType: .string)
                            }
                        } else {
                            Button("Open macOS Terminal.app") {
                                ExternalTerminalBridge.shared.launchInTerminalApp(command: "echo 'NexWave Terminal Active'")
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "wrench.and.screwdriver")
                            .font(.system(size: 11))
                        Text("Tools")
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(Theme.cardBackground)
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.borderLight, lineWidth: 0.75))
                    .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize(horizontal: true, vertical: false)
                .help("Access SSH Key Studio, Tunnels, SFTP/SCP, Break Signal, and Profiles")

                // 5. Quick Action Segmented Pill (Syntax, Timestamps, Search, More ...)
                HStack(spacing: 2) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            state.terminalManager.isSyntaxHighlightingEnabled.toggle()
                            for s in state.terminalManager.sessions {
                                s.syntaxHighlightConfig.isEnabled = state.terminalManager.isSyntaxHighlightingEnabled
                            }
                        }
                    }) {
                        Image(systemName: "highlighter")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(state.terminalManager.isSyntaxHighlightingEnabled ? Theme.neonCyan : .secondary)
                            .frame(width: 26, height: 24)
                            .background(state.terminalManager.isSyntaxHighlightingEnabled ? Theme.neonCyan.opacity(0.18) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Toggle Live Network Syntax Highlighting")

                    Button(action: {
                        if let s = activeSession {
                            s.showTimestamps.toggle()
                        }
                    }) {
                        Image(systemName: "clock")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(activeSession?.showTimestamps == true ? Theme.neonCyan : .secondary)
                            .frame(width: 26, height: 24)
                            .background(activeSession?.showTimestamps == true ? Theme.neonCyan.opacity(0.18) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Toggle Per-Line Timestamps")

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isSearching.toggle()
                            if !isSearching { searchQuery = "" }
                        }
                    }) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(isSearching ? Theme.neonCyan : .secondary)
                            .frame(width: 26, height: 24)
                            .background(isSearching ? Theme.neonCyan.opacity(0.18) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Search Transcript (Cmd+F)")

                    Menu {
                        Button(action: { activeSession?.clear() }) {
                            Label("Clear Screen", systemImage: "trash")
                        }
                        .keyboardShortcut("k", modifiers: .command)

                        Button(action: {
                            if let s = activeSession {
                                copyAllTranscript(s)
                            }
                        }) {
                            Label("Copy All Output", systemImage: "doc.on.doc")
                        }
                        .keyboardShortcut("c", modifiers: [.command, .shift])

                        Button(action: exportTranscript) {
                            Label("Export Transcript Log...", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 26, height: 24)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize(horizontal: true, vertical: false)
                    .help("More Terminal Actions (Clear, Copy All, Export)")
                }
                .padding(2)
                .frame(height: 28)
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.borderLight, lineWidth: 0.75))
            }
            .frame(height: 28)
        }
        .frame(height: 38)
        .padding(.horizontal, 14)
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
                                .foregroundStyle(isSelected ? Theme.neonCyan : .secondary)

                            Circle()
                                .fill(Color(hex: session.status.badgeColorHex))
                                .frame(width: 6, height: 6)

                            Text(session.title)
                                .font(.system(size: 11, weight: isSelected ? .semibold : .medium, design: .monospaced))
                                .foregroundStyle(isSelected ? Color.white : .secondary)
                                .lineLimit(1)

                            Button(action: {
                                state.terminalManager.closeSession(id: session.id)
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8.5, weight: .bold))
                                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary.opacity(0.6))
                                    .frame(width: 14, height: 14)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Close tab (Cmd+W)")
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(isSelected ? Theme.cardBackground : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isSelected ? Theme.neonCyan.opacity(0.4) : Theme.borderLight.opacity(0.6), lineWidth: 0.75)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            state.terminalManager.activeSessionId = session.id
                        }
                        .contextMenu {
                            sessionTabContextMenu(for: session)
                        }
                    }

                    // Compact '+' button right next to tabs
                    Button(action: {
                        state.terminalManager.refreshSerialPorts()
                        showNewSessionSheet = true
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 26, height: 26)
                            .background(Theme.cardBackground.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Theme.borderLight.opacity(0.6), lineWidth: 0.75)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("New Terminal Session (Cmd+T)")
                }
                .padding(.vertical, 1)
            }

            Spacer()

            // Right side of Tab Bar: Toggle Macros Strip
            HStack(spacing: 8) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showMacrosBar.toggle()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.horizontal")
                            .font(.system(size: 10))
                        Text("Macros")
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .background(showMacrosBar ? Theme.neonCyan.opacity(0.15) : Theme.cardBackground)
                    .foregroundStyle(showMacrosBar ? Theme.neonCyan : .secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(showMacrosBar ? Theme.neonCyan.opacity(0.5) : Theme.borderLight, lineWidth: 0.75)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Toggle Command Macros Bar")
            }
            .frame(height: 26)
        }
        .frame(height: 36)
        .padding(.horizontal, 14)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
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
                        .frame(width: 14, height: 14)
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
        .frame(height: 26)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
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
        .frame(height: 26)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
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
        let sessionFontSize = effectiveFontSize(for: session)
        let sessionFontFamily = effectiveFontFamily(for: session)
        let sessionTheme = effectiveTheme(for: session)
        let sessionCursor = effectiveCursorStyle(for: session)

        return VStack(spacing: 0) {
            // Pane Header Strip (in split mode)
            if state.terminalManager.splitMode != .single {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: session.connectionType.iconName)
                            .font(.system(size: 10))
                        Text(session.title)
                            .font(Theme.monoText(11, weight: .bold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(isFocused ? Theme.neonCyan : .secondary)

                    Spacer()

                    // Session picker for this pane
                    Picker("", selection: paneSessionBinding(paneIndex: paneIndex)) {
                        ForEach(state.terminalManager.sessions) { s in
                            Text(s.title).tag(Optional(s.id))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 140)
                }
                .frame(height: 26)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Theme.surfaceBackground)
                Divider().overlay(Theme.borderLight)
            }

            // Screen Output ScrollView with ANSI SGR Rendering
            GeometryReader { geo in
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: CGFloat(globalLineSpacing)) {
                            let showLiveCursor = searchQuery.isEmpty
                            let tsWidth = timestampColumnWidth(for: sessionFontSize)
                            let tsFont = Theme.terminalFont(family: sessionFontFamily, size: max(9, sessionFontSize - 1.5))

                            ForEach(displayedLines) { line in
                                HStack(alignment: .firstTextBaseline, spacing: 0) {
                                    // Optional microsecond timestamp
                                    if session.showTimestamps {
                                        Text(timestampString(for: line.timestamp))
                                            .font(tsFont)
                                            .foregroundStyle(Color.secondary.opacity(0.65))
                                            .lineLimit(1)
                                            .fixedSize(horizontal: true, vertical: false)
                                            .frame(width: tsWidth, alignment: .leading)
                                            .padding(.trailing, 8)
                                    }

                                    renderTerminalLine(line, session: session)

                                    // If this is the active open line, show cursor inline right at the insertion point
                                    if showLiveCursor && line.id == displayedLines.last?.id && session.isLastLineOpen {
                                        BlinkingCursorView(
                                            isFocused: isFocused,
                                            color: Color(hex: sessionTheme.promptColorHex),
                                            fontSize: sessionFontSize,
                                            fontFamily: sessionFontFamily,
                                            style: sessionCursor,
                                            shouldBlink: globalCursorBlink
                                        )
                                    }
                                }
                            }

                            // If the last line is NOT open (terminated by newline) or lines are empty, cursor is on next line
                            if showLiveCursor && (!session.isLastLineOpen || displayedLines.isEmpty) {
                                HStack(alignment: .firstTextBaseline, spacing: 0) {
                                    if session.showTimestamps {
                                        Color.clear.frame(width: tsWidth + 8)
                                    }
                                    BlinkingCursorView(
                                        isFocused: isFocused,
                                        color: Color(hex: sessionTheme.promptColorHex),
                                        fontSize: sessionFontSize,
                                        fontFamily: sessionFontFamily,
                                        style: sessionCursor,
                                        shouldBlink: globalCursorBlink
                                    )
                                }
                            }

                            // Inline interactive password prompt card
                            if session.isAwaitingPasswordPrompt {
                                InlinePasswordBar(inputCommand: $inputCommand) {
                                    submitCommand(to: session)
                                }
                            }

                            Color.clear
                                .frame(height: 1)
                                .id("bottomAnchor_\(paneIndex)")
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(Color(hex: sessionTheme.backgroundColorHex))
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
                .onAppear {
                    focusedPaneState = paneIndex
                    updatePTYDimensions(for: session, size: geo.size)
                }
                .onChange(of: geo.size) { _, newSize in
                    updatePTYDimensions(for: session, size: newSize)
                }
                .onKeyPress { press in
                    handleDirectKeyPress(press, session: session)
                }
                .simultaneousGesture(TapGesture().onEnded {
                    focusedPane = paneIndex
                    focusedPaneState = paneIndex
                })
                .contextMenu {
                    terminalCanvasContextMenu(session: session)
                }
            }

            Divider().overlay(Theme.borderLight)

            // Interactive Bottom Input Bar
            let askingPassword = isPasswordPrompt(session)
            HStack(spacing: 8) {
                Text(askingPassword ? "PASSWORD :" : "\(session.title) #")
                    .font(Theme.terminalFont(family: sessionFontFamily, size: 11, weight: .bold))
                    .foregroundStyle(askingPassword ? Theme.pulseCrimson : Color(hex: sessionTheme.promptColorHex))

                if askingPassword {
                    SecureField("Remote host password / passphrase (press Enter to send)...", text: $inputCommand)
                        .font(Theme.terminalFont(family: sessionFontFamily, size: sessionFontSize))
                        .textFieldStyle(.plain)
                        .tint(Color(hex: sessionTheme.promptColorHex))
                        .onSubmit {
                            submitCommand(to: session)
                        }
                } else {
                    TextField("Enter command (or click terminal canvas to type directly)...", text: $inputCommand)
                        .font(Theme.terminalFont(family: sessionFontFamily, size: sessionFontSize))
                        .textFieldStyle(.plain)
                        .tint(Color(hex: sessionTheme.promptColorHex))
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
                            Text("MikroTik RouterOS (CCR2004 Core)").tag("MikroTik RouterOS")
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

    // MARK: - Folder Editor Modal

    private var folderEditorModal: some View {
        VStack(spacing: 16) {
            HStack {
                Label(folderEditingId == nil ? "New Folder" : "Edit Folder", systemImage: "folder.fill")
                    .font(.headline.bold())
                Spacer()
                Button("Cancel") { showFolderEditorSheet = false }
                    .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("FOLDER NAME")
                        .font(Theme.monoText(10, weight: .bold))
                        .foregroundStyle(.secondary)
                    TextField("e.g. Data Center West, Core Switches, DMZ...", text: $folderNameInput)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("PARENT FOLDER (OPTIONAL)")
                        .font(Theme.monoText(10, weight: .bold))
                        .foregroundStyle(.secondary)
                    Picker("", selection: $folderParentIdInput) {
                        Text("None (Root Directory)").tag(UUID?.none)
                        ForEach(state.terminalManager.folders.filter { f in
                            if let eid = folderEditingId { return f.id != eid }
                            return true
                        }) { f in
                            Text(f.name).tag(UUID?.some(f.id))
                        }
                    }
                    .pickerStyle(.menu)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("FOLDER ACCENT COLOR")
                        .font(Theme.monoText(10, weight: .bold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        let colorChoices = [
                            ("#F59E0B", "Solar Amber"),
                            ("#10B981", "Emerald Green"),
                            ("#00E5FF", "Neon Cyan"),
                            ("#3B82F6", "Cobalt Blue"),
                            ("#8B5CF6", "Electric Purple"),
                            ("#EC4899", "Cyber Pink"),
                            ("#EF4444", "Crimson Red"),
                            ("#64748B", "Slate Gray")
                        ]
                        ForEach(colorChoices, id: \.0) { hex, name in
                            Button(action: { folderColorHexInput = hex }) {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 22, height: 22)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white, lineWidth: folderColorHexInput == hex ? 2 : 0)
                                    )
                                    .shadow(color: Color(hex: hex).opacity(folderColorHexInput == hex ? 0.6 : 0), radius: 4)
                            }
                            .buttonStyle(.plain)
                            .help(name)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(14)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                Spacer()
                Button("Save Folder") {
                    if let editingId = folderEditingId {
                        state.terminalManager.renameFolder(id: editingId, newName: folderNameInput)
                        state.terminalManager.setFolderColor(id: editingId, colorHex: folderColorHexInput)
                        copyToastMessage = "Updated folder '\(folderNameInput)'"
                    } else {
                        state.terminalManager.createFolder(
                            name: folderNameInput,
                            parentId: folderParentIdInput,
                            colorHex: folderColorHexInput
                        )
                        copyToastMessage = "Created folder '\(folderNameInput)'"
                    }
                    showFolderEditorSheet = false
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.cyanPulse)
                .foregroundStyle(Color.black)
                .disabled(folderNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    // MARK: - Edit Profile Modal

    private var editProfileModal: some View {
        VStack(spacing: 16) {
            HStack {
                Label("Edit Session Configuration", systemImage: "slider.horizontal.3")
                    .font(.headline.bold())
                Spacer()
                Button("Cancel") { showEditProfileSheet = false }
                    .buttonStyle(.plain)
            }

            ScrollView {
                VStack(spacing: 14) {
                    // Name & Folder
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("SESSION NAME")
                                .font(Theme.monoText(10, weight: .bold))
                                .foregroundStyle(.secondary)
                            TextField("e.g. Spine Switch 01", text: $editingProfileName)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("TARGET FOLDER")
                                .font(Theme.monoText(10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $editingProfileFolderId) {
                                Text("Root / Unfiled").tag(UUID?.none)
                                ForEach(state.terminalManager.folders) { f in
                                    Text(f.name).tag(UUID?.some(f.id))
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }

                    // Connection Protocol
                    VStack(alignment: .leading, spacing: 6) {
                        Text("PROTOCOL")
                            .font(Theme.monoText(10, weight: .bold))
                            .foregroundStyle(.secondary)
                        Picker("", selection: $editingProfileConnectionType) {
                            Text("SSHv2").tag("ssh")
                            Text("POSIX USB Serial").tag("serial")
                            Text("Local Shell").tag("localshell")
                        }
                        .pickerStyle(.segmented)
                    }

                    if editingProfileConnectionType == "ssh" {
                        // Host & Port & Username
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("HOST IP / FQDN")
                                    .font(Theme.monoText(10, weight: .bold))
                                    .foregroundStyle(.secondary)
                                TextField("192.168.1.1", text: $editingProfileHost)
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("PORT")
                                    .font(Theme.monoText(10, weight: .bold))
                                    .foregroundStyle(.secondary)
                                TextField("22", text: $editingProfilePort)
                                    .textFieldStyle(.roundedBorder)
                            }
                            .frame(width: 70)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("USERNAME")
                                    .font(Theme.monoText(10, weight: .bold))
                                    .foregroundStyle(.secondary)
                                TextField("admin", text: $editingProfileUsername)
                                    .textFieldStyle(.roundedBorder)
                            }
                            .frame(width: 110)
                        }

                        // Identity Key Path
                        VStack(alignment: .leading, spacing: 6) {
                            Text("SSH IDENTITY FILE (ED25519 / RSA)")
                                .font(Theme.monoText(10, weight: .bold))
                                .foregroundStyle(.secondary)
                            HStack {
                                TextField("~/.ssh/id_ed25519 or key path", text: $editingProfileIdentityFile)
                                    .textFieldStyle(.roundedBorder)
                                Button("Browse...") {
                                    let panel = NSOpenPanel()
                                    panel.allowsMultipleSelection = false
                                    panel.canChooseDirectories = false
                                    panel.canChooseFiles = true
                                    if panel.runModal() == .OK, let url = panel.url {
                                        editingProfileIdentityFile = url.path
                                    }
                                }
                            }
                        }

                        // Jump Host / Bastion ProxyJump
                        VStack(alignment: .leading, spacing: 6) {
                            Text("BASTION / JUMP HOST (OPTIONAL)")
                                .font(Theme.monoText(10, weight: .bold))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                TextField("jump.corp.net", text: $editingProfileJumpHost)
                                    .textFieldStyle(.roundedBorder)
                                TextField("22", text: $editingProfileJumpPort)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 60)
                                TextField("jumpuser", text: $editingProfileJumpUser)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 100)
                            }
                        }

                        Toggle("Enable Legacy SSH Ciphers (Cisco IOS 12/15, 3DES, DH-group1)", isOn: $editingProfileEnableLegacyCiphers)
                            .font(.system(size: 11))

                    } else if editingProfileConnectionType == "serial" {
                        // Serial port settings
                        VStack(alignment: .leading, spacing: 6) {
                            Text("SERIAL DEVICE PATH (/dev/cu.*)")
                                .font(Theme.monoText(10, weight: .bold))
                                .foregroundStyle(.secondary)
                            TextField("/dev/cu.usbserial-001", text: $editingProfileSerialPath)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("BAUD RATE")
                                .font(Theme.monoText(10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $editingProfileSerialBaud) {
                                ForEach(SerialDiscovery.standardBaudRates, id: \.self) { rate in
                                    Text("\(rate)").tag(rate)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }

                    // Tags
                    VStack(alignment: .leading, spacing: 6) {
                        Text("TAGS (COMMA-SEPARATED)")
                            .font(Theme.monoText(10, weight: .bold))
                            .foregroundStyle(.secondary)
                        TextField("Production, Spine, BGP, West-DC", text: $editingProfileTags)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Notes
                    VStack(alignment: .leading, spacing: 6) {
                        Text("NOTES / DOCUMENTATION")
                            .font(Theme.monoText(10, weight: .bold))
                            .foregroundStyle(.secondary)
                        TextEditor(text: $editingProfileNotes)
                            .font(Theme.monoText(11))
                            .frame(height: 50)
                            .background(Theme.surfaceBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.borderLight, lineWidth: 1))
                    }
                }
                .padding(14)
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .frame(maxHeight: 460)

            HStack {
                Spacer()
                Button("Save Changes") {
                    saveEditedProfile()
                    showEditProfileSheet = false
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.cyanPulse)
                .foregroundStyle(Color.black)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    // MARK: - Bookmark Session Modal

    private var bookmarkSessionModal: some View {
        VStack(spacing: 16) {
            HStack {
                Label("Save to Saved Sessions", systemImage: "star.fill")
                    .font(.headline.bold())
                Spacer()
                Button("Cancel") { showBookmarkSessionSheet = false }
                    .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("BOOKMARK NAME")
                        .font(Theme.monoText(10, weight: .bold))
                        .foregroundStyle(.secondary)
                    TextField("Session Name", text: $bookmarkNameInput)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("DESTINATION FOLDER")
                        .font(Theme.monoText(10, weight: .bold))
                        .foregroundStyle(.secondary)
                    Picker("", selection: $bookmarkFolderId) {
                        Text("Root / Unfiled").tag(UUID?.none)
                        ForEach(state.terminalManager.folders) { f in
                            Text(f.name).tag(UUID?.some(f.id))
                        }
                    }
                    .pickerStyle(.menu)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("TAGS (COMMA SEPARATED)")
                        .font(Theme.monoText(10, weight: .bold))
                        .foregroundStyle(.secondary)
                    TextField("e.g. Core, Live, Production", text: $bookmarkTagsInput)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("NOTES (OPTIONAL)")
                        .font(Theme.monoText(10, weight: .bold))
                        .foregroundStyle(.secondary)
                    TextField("Notes for this device or credentials...", text: $bookmarkNotesInput)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding(14)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                Spacer()
                Button("Save Session") {
                    if let s = sessionToBookmark {
                        let tags = bookmarkTagsInput.components(separatedBy: ",")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                        state.terminalManager.saveActiveSessionAsProfile(
                            session: s,
                            name: bookmarkNameInput,
                            folderId: bookmarkFolderId,
                            tags: tags,
                            notes: bookmarkNotesInput
                        )
                        copyToastMessage = "Saved '\(bookmarkNameInput)' to library"
                    }
                    showBookmarkSessionSheet = false
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.cyanPulse)
                .foregroundStyle(Color.black)
                .disabled(bookmarkNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func populateProfileEditor(with profile: TerminalProfile) {
        profileEditingId = profile.id
        editingProfileName = profile.name
        editingProfileFolderId = profile.folderId
        editingProfileHost = profile.host
        editingProfilePort = "\(profile.port)"
        editingProfileUsername = profile.username
        editingProfileIdentityFile = profile.identityFile ?? ""
        editingProfileConnectionType = profile.connectionType
        editingProfileSerialPath = profile.serialPath
        editingProfileSerialBaud = profile.serialBaud
        editingProfileJumpHost = profile.jumpHost ?? ""
        editingProfileJumpPort = "\(profile.jumpPort ?? 22)"
        editingProfileJumpUser = profile.jumpUser ?? "admin"
        editingProfileEnableLegacyCiphers = profile.enableLegacyCiphers
        editingProfileBadgeColorHex = profile.badgeColorHex
        editingProfileTags = profile.tags.joined(separator: ", ")
        editingProfileNotes = profile.notes
    }

    private func saveEditedProfile() {
        guard let id = profileEditingId else { return }
        let tags = editingProfileTags.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let folderName = state.terminalManager.folders.first(where: { $0.id == editingProfileFolderId })?.name ?? "General"
        let updated = TerminalProfile(
            id: id,
            name: editingProfileName,
            folder: folderName,
            folderId: editingProfileFolderId,
            host: editingProfileHost,
            port: Int(editingProfilePort) ?? 22,
            username: editingProfileUsername,
            identityFile: editingProfileIdentityFile.isEmpty ? nil : editingProfileIdentityFile,
            connectionType: editingProfileConnectionType,
            serialBaud: editingProfileSerialBaud,
            serialPath: editingProfileSerialPath,
            vendorPreset: "",
            autoConnect: false,
            badgeColorHex: editingProfileBadgeColorHex,
            jumpHost: editingProfileJumpHost.isEmpty ? nil : editingProfileJumpHost,
            jumpUser: editingProfileJumpUser.isEmpty ? nil : editingProfileJumpUser,
            jumpPort: Int(editingProfileJumpPort) ?? 22,
            enableLegacyCiphers: editingProfileEnableLegacyCiphers,
            tags: tags,
            notes: editingProfileNotes,
            lastConnected: nil
        )
        state.terminalManager.saveProfile(updated)
        copyToastMessage = "Updated '\(editingProfileName)'"
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
        session.isAwaitingPasswordPrompt
    }

    private func handleDirectKeyPress(_ press: KeyPress, session: TerminalSession) -> KeyPress.Result {
        // Cmd+V: Clipboard paste directly into active terminal
        if press.modifiers.contains(.command) && press.characters.lowercased() == "v" {
            pasteFromClipboard(to: session)
            return .handled
        }

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
            let terminator = session.isAwaitingPasswordPrompt ? "\n" : "\r"
            if state.terminalManager.isBroadcastEnabled {
                state.terminalManager.broadcastText(terminator)
            } else {
                session.sendRawString(terminator)
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
        case .pageUp:
            session.sendRawString("\u{1B}[5~")
            return .handled
        case .pageDown:
            session.sendRawString("\u{1B}[6~")
            return .handled
        case .home:
            session.sendRawString("\u{1B}[H")
            return .handled
        case .end:
            session.sendRawString("\u{1B}[F")
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
            var targetHost = sshHost.trimmingCharacters(in: .whitespacesAndNewlines)
            var targetUser = sshUser.trimmingCharacters(in: .whitespacesAndNewlines)
            var targetPort = Int(sshPort) ?? 22
            var pass = sshPassword.isEmpty ? nil : sshPassword

            if targetHost.contains("@") {
                let parts = targetHost.components(separatedBy: "@")
                targetUser = parts[0]
                targetHost = parts[1]
            }

            if targetUser.contains(":") {
                let uParts = targetUser.components(separatedBy: ":")
                targetUser = uParts[0]
                if pass == nil || pass?.isEmpty == true {
                    pass = uParts[1]
                }
            }

            if targetHost.contains(":") {
                let parts = targetHost.components(separatedBy: ":")
                targetHost = parts[0]
                if let p = Int(parts[1]) {
                    targetPort = p
                }
            }

            let key = sshKeyPath.isEmpty ? nil : sshKeyPath
            let jump: SSHJumpConfig? = (sshEnableJumpHost && !sshJumpHost.isEmpty) ?
                SSHJumpConfig(host: sshJumpHost, port: Int(sshJumpPort) ?? 22, username: sshJumpUser) : nil

            state.terminalManager.openSSHSession(
                host: targetHost,
                port: targetPort,
                username: targetUser,
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
        guard let session = activeSession else { return }
        let fSize = effectiveFontSize(for: session)
        let charWidth = max(1.0, fSize * 0.60)
        let charHeight = max(1.0, fSize * 1.35 + CGFloat(globalLineSpacing))
        let cols = max(80, Int(1000.0 / charWidth))
        let rows = max(24, Int(600.0 / charHeight))
        session.resize(cols: cols, rows: rows)
    }

    private func updatePTYDimensions(for session: TerminalSession, size: CGSize) {
        let fSize = effectiveFontSize(for: session)
        let charWidth = max(1.0, fSize * 0.60)
        let charHeight = max(1.0, fSize * 1.35 + CGFloat(globalLineSpacing))
        let cols = max(40, Int(size.width / charWidth))
        let rows = max(10, Int(size.height / charHeight))
        session.resize(cols: cols, rows: rows)
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

    private static let timestampFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        return df
    }()

    private func timestampString(for date: Date) -> String {
        "[\(Self.timestampFormatter.string(from: date))]"
    }

    private func timestampColumnWidth(for fontSize: CGFloat) -> CGFloat {
        let tsSize = max(9, fontSize - 1.5)
        // Format "[HH:mm:ss.SSS]" has 14 monospaced characters.
        // Advance per character is ~0.602 * tsSize. 14 * 0.602 = 8.43 * tsSize.
        // We allocate 9.0 * tsSize + 8 for comfortable padding and zero clipping.
        return ceil(tsSize * 9.0) + 8
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

    @ViewBuilder
    private func renderSpan(_ span: ANSISpan) -> some View {
        Text(span.text)
            .font(Theme.monoText(fontSize, weight: span.style.isBold ? .bold : .regular))
            .underline(span.style.isUnderline)
            .italic(span.style.isItalic)
            .foregroundStyle(colorForSpan(span.style))
            .background(backgroundColorForSpan(span.style))
    }

    // MARK: - MobaXterm Collapsible Session Tree & Quick Connect Sidebar

    private var sessionTreeSidebar: some View {
        VStack(spacing: 0) {
            // Top Header matching main workbench headerBar
            sidebarHeaderView
            Divider().overlay(Theme.borderLight)

            // Search Bar & Filter Strip
            sidebarFilterView
            Divider().overlay(Theme.borderLight)

            // Quick Connect Card
            quickConnectCard
            Divider().overlay(Theme.borderLight)

            // Dynamic Hierarchical Tree of Saved Folders & Sessions
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    if !sessionSearchQuery.isEmpty || selectedProtocolFilter != "ALL" {
                        searchResultsListView
                    } else {
                        folderHierarchyListView
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 6)
            }

            Divider().overlay(Theme.borderLight)

            // MobaXterm Bottom Utilities Strip
            sidebarBottomUtilitiesStrip
        }
        .background(Theme.surfaceBackground.opacity(0.95))
    }

    // MARK: - Sidebar Header View

    private var sidebarHeaderView: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.neonCyan)
            Text("Saved Sessions")
                .font(Theme.monoText(11, weight: .bold))
                .foregroundStyle(.primary)

            let totalSessions = state.terminalManager.savedProfiles.count
            Text("\(totalSessions)")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.neonCyan)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Theme.neonCyan.opacity(0.12))
                .clipShape(Capsule())

            Spacer()

            // New Folder Button
            Button(action: {
                folderEditingId = nil
                folderNameInput = ""
                folderParentIdInput = nil
                folderColorHexInput = "#F59E0B"
                showFolderEditorSheet = true
            }) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.solarAmber)
                    .frame(width: 22, height: 22)
                    .background(Theme.solarAmber.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.solarAmber.opacity(0.3), lineWidth: 0.75))
            }
            .buttonStyle(.plain)
            .help("Create New Folder")

            // New Connection Button
            Button(action: {
                showNewSessionSheet = true
            }) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.neonCyan)
                    .frame(width: 22, height: 22)
                    .background(Theme.neonCyan.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.neonCyan.opacity(0.3), lineWidth: 0.75))
            }
            .buttonStyle(.plain)
            .help("New Connection Wizard")

            // Library Options Menu (⋯)
            Menu {
                Button(action: { state.terminalManager.expandAllFolders() }) {
                    Label("Expand All Folders", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                Button(action: { state.terminalManager.collapseAllFolders() }) {
                    Label("Collapse All Folders", systemImage: "arrow.down.right.and.arrow.up.left")
                }
                Divider()
                Button(action: { exportSessionLibraryToClipboard() }) {
                    Label("Export Session Library (JSON)...", systemImage: "square.and.arrow.up")
                }
                Button(action: { importSessionLibraryFromClipboard() }) {
                    Label("Import Session Library (JSON)...", systemImage: "square.and.arrow.down")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(Theme.cardBackground.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.borderLight, lineWidth: 0.75))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 22, height: 22)
            .help("Library Options")
        }
        .frame(height: 28)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Theme.surfaceBackground)
    }

    // MARK: - Sidebar Search & Protocol Filter

    private var sidebarFilterView: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                TextField("Filter sessions (name, host, tag)...", text: $sessionSearchQuery)
                    .textFieldStyle(.plain)
                    .font(Theme.monoText(10))

                if !sessionSearchQuery.isEmpty {
                    Button(action: { sessionSearchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Theme.surfaceBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.borderLight, lineWidth: 1))

            // Protocol Chips
            HStack(spacing: 4) {
                ForEach(["ALL", "SSH", "SERIAL", "LOCAL"], id: \.self) { proto in
                    let isSelected = selectedProtocolFilter == proto
                    Button(action: { selectedProtocolFilter = proto }) {
                        Text(proto)
                            .font(.system(size: 8, weight: isSelected ? .bold : .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(isSelected ? Theme.neonCyan.opacity(0.2) : Theme.cardBackground.opacity(0.5))
                            .foregroundStyle(isSelected ? Theme.neonCyan : .secondary)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(isSelected ? Theme.neonCyan.opacity(0.5) : Theme.borderLight, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                if !sessionSearchQuery.isEmpty || selectedProtocolFilter != "ALL" {
                    Text("\(filteredProfiles.count) found")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
        .background(Theme.cardBackground.opacity(0.7))
    }

    // MARK: - Quick Connect Card

    private var quickConnectCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Quick Connect", systemImage: "bolt.fill")
                    .font(Theme.monoText(10, weight: .bold))
                    .foregroundStyle(Theme.neonCyan)
                Spacer()
            }

            HStack(spacing: 4) {
                TextField("ubuntu@170.75.170.64", text: $quickConnectInput)
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
        .padding(8)
        .background(Theme.cardBackground.opacity(0.4))
    }

    // MARK: - Filtered Search Results List

    private var filteredProfiles: [TerminalProfile] {
        let q = sessionSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return state.terminalManager.savedProfiles.filter { p in
            if selectedProtocolFilter != "ALL" {
                switch selectedProtocolFilter {
                case "SSH":
                    if p.connectionType.lowercased() != "ssh" { return false }
                case "SERIAL":
                    if p.connectionType.lowercased() != "serial" { return false }
                case "LOCAL":
                    if !["localshell", "shell", "local"].contains(p.connectionType.lowercased()) { return false }
                default: break
                }
            }
            if q.isEmpty { return true }
            return p.name.localizedCaseInsensitiveContains(q)
                || p.host.localizedCaseInsensitiveContains(q)
                || p.username.localizedCaseInsensitiveContains(q)
                || p.serialPath.localizedCaseInsensitiveContains(q)
                || p.folder.localizedCaseInsensitiveContains(q)
                || p.tags.contains(where: { $0.localizedCaseInsensitiveContains(q) })
                || p.notes.localizedCaseInsensitiveContains(q)
        }
    }

    @ViewBuilder
    private var searchResultsListView: some View {
        if filteredProfiles.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary.opacity(0.5))
                Text("No matching sessions")
                    .font(Theme.monoText(10))
                    .foregroundStyle(.secondary)
                Button("Clear Search") {
                    sessionSearchQuery = ""
                    selectedProtocolFilter = "ALL"
                }
                .font(.system(size: 10))
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else {
            ForEach(filteredProfiles) { profile in
                sessionProfileRow(profile: profile, level: 0, showFolderBadge: true)
            }
        }
    }

    // MARK: - Hierarchical Folder Tree View

    @ViewBuilder
    private var folderHierarchyListView: some View {
        // Root folders (parentId == nil)
        let rootFolders = state.terminalManager.folders.filter { $0.parentId == nil }
        ForEach(rootFolders) { folder in
            folderTreeRow(folder: folder, level: 0)
        }

        // Unfiled / Root Sessions (folderId == nil or not matching any existing folder)
        let knownFolderIds = Set(state.terminalManager.folders.map { $0.id })
        let unfiledProfiles = state.terminalManager.savedProfiles.filter { p in
            guard let fid = p.folderId else { return true }
            return !knownFolderIds.contains(fid)
        }
        if !unfiledProfiles.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "tray.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text("UNFILED")
                        .font(Theme.monoText(9, weight: .bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(unfiledProfiles.count)")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary.opacity(0.6))
                }
                .padding(.horizontal, 8)
                .padding(.top, 6)

                ForEach(unfiledProfiles) { profile in
                    sessionProfileRow(profile: profile, level: 0, showFolderBadge: false)
                }
            }
        }
    }

    // MARK: - Folder Row in Tree

    private func folderTreeRow(folder: SessionFolder, level: Int) -> AnyView {
        let childFolders = state.terminalManager.folders.filter { $0.parentId == folder.id }
        let directProfiles = state.terminalManager.savedProfiles.filter { $0.folderId == folder.id }

        return AnyView(
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    // Expand / Collapse Chevron
                    Button(action: {
                        state.terminalManager.toggleFolderExpansion(id: folder.id)
                    }) {
                        Image(systemName: folder.isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 14, height: 14)
                    }
                    .buttonStyle(.plain)

                    // Colored Folder Icon
                    Image(systemName: folder.isExpanded ? "folder.fill" : "folder")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: folder.iconColorHex ?? "#F59E0B"))

                    // Folder Title
                    Text(folder.name)
                        .font(Theme.monoText(10, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer()

                    // Session Count Badge
                    let count = directProfiles.count
                    Text("\(count)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary.opacity(0.8))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Theme.cardBackground)
                        .clipShape(Capsule())
                }
                .padding(.leading, CGFloat(level * 12 + 4))
                .padding(.trailing, 6)
                .padding(.vertical, 3)
                .background(Theme.cardBackground.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
                .contextMenu {
                    folderContextMenu(for: folder)
                }

                // Expanded Children
                if folder.isExpanded {
                    // Subfolders
                    ForEach(childFolders) { subfolder in
                        folderTreeRow(folder: subfolder, level: level + 1)
                    }

                    // Sessions inside this folder
                    ForEach(directProfiles) { profile in
                        sessionProfileRow(profile: profile, level: level + 1, showFolderBadge: false)
                    }
                }
            }
        )
    }

    // MARK: - Folder Context Menu

    @ViewBuilder
    private func folderContextMenu(for folder: SessionFolder) -> some View {
        Button(action: {
            state.terminalManager.connectAllInFolder(folderId: folder.id)
        }) {
            Label("Connect All in Tabs", systemImage: "play.fill")
        }

        Divider()

        Button(action: {
            newSessionTargetFolderId = folder.id
            showNewSessionSheet = true
        }) {
            Label("New Session Here...", systemImage: "plus.square")
        }

        Button(action: {
            folderEditingId = nil
            folderNameInput = ""
            folderParentIdInput = folder.id
            folderColorHexInput = "#F59E0B"
            showFolderEditorSheet = true
        }) {
            Label("New Subfolder...", systemImage: "folder.badge.plus")
        }

        Divider()

        Button(action: {
            folderEditingId = folder.id
            folderNameInput = folder.name
            folderParentIdInput = folder.parentId
            folderColorHexInput = folder.iconColorHex ?? "#F59E0B"
            showFolderEditorSheet = true
        }) {
            Label("Rename Folder...", systemImage: "pencil")
        }

        Menu("Folder Color") {
            Button("Emerald Green") { state.terminalManager.setFolderColor(id: folder.id, colorHex: "#10B981") }
            Button("Neon Cyan") { state.terminalManager.setFolderColor(id: folder.id, colorHex: "#00E5FF") }
            Button("Cobalt Blue") { state.terminalManager.setFolderColor(id: folder.id, colorHex: "#3B82F6") }
            Button("Electric Purple") { state.terminalManager.setFolderColor(id: folder.id, colorHex: "#8B5CF6") }
            Button("Cyber Pink") { state.terminalManager.setFolderColor(id: folder.id, colorHex: "#EC4899") }
            Button("Solar Amber") { state.terminalManager.setFolderColor(id: folder.id, colorHex: "#F59E0B") }
            Button("Crimson Red") { state.terminalManager.setFolderColor(id: folder.id, colorHex: "#EF4444") }
            Button("Slate Gray") { state.terminalManager.setFolderColor(id: folder.id, colorHex: "#64748B") }
        }

        Divider()

        Button(role: .destructive, action: {
            state.terminalManager.deleteFolder(id: folder.id, deleteContents: false)
        }) {
            Label("Delete Folder (Keep Sessions)", systemImage: "folder.badge.minus")
        }

        Button(role: .destructive, action: {
            state.terminalManager.deleteFolder(id: folder.id, deleteContents: true)
        }) {
            Label("Delete Folder & All Sessions", systemImage: "trash")
        }
    }

    // MARK: - Session Profile Row

    @ViewBuilder
    private func sessionProfileRow(profile: TerminalProfile, level: Int, showFolderBadge: Bool) -> some View {
        Button(action: {
            state.terminalManager.launchProfile(profile)
        }) {
            HStack(spacing: 6) {
                // Protocol Badge
                protocolBadgeView(type: profile.connectionType)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(profile.name)
                            .font(Theme.monoText(10, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if let last = profile.lastConnected {
                            Circle()
                                .fill(Theme.emeraldHealthy)
                                .frame(width: 4, height: 4)
                                .help("Last connected: \(last.formatted(date: .abbreviated, time: .shortened))")
                        }

                        if showFolderBadge {
                            Text(profile.folder)
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Theme.cardBackground)
                                .clipShape(Capsule())
                        }
                    }

                    // Subtitle
                    Text(sessionSubtitle(for: profile))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    // Tags
                    if !profile.tags.isEmpty {
                        HStack(spacing: 3) {
                            ForEach(profile.tags.prefix(3), id: \.self) { tag in
                                Text(tag)
                                    .font(.system(size: 7, weight: .medium))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Theme.neonCyan.opacity(0.12))
                                    .foregroundStyle(Theme.neonCyan)
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.top, 1)
                    }
                }

                Spacer()
            }
            .padding(.leading, CGFloat(level * 12 + 6))
            .padding(.trailing, 6)
            .padding(.vertical, 4)
            .background(Theme.cardBackground.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Theme.borderLight.opacity(0.4), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            sessionProfileContextMenu(for: profile)
        }
    }

    // MARK: - Session Profile Context Menu

    @ViewBuilder
    private func sessionProfileContextMenu(for profile: TerminalProfile) -> some View {
        Button(action: {
            state.terminalManager.launchProfile(profile)
        }) {
            Label("Connect", systemImage: "terminal.fill")
        }

        Button(action: {
            let session = state.terminalManager.launchProfile(profile)
            state.terminalManager.splitMode = .vertical
            state.terminalManager.secondarySessionId = session.id
        }) {
            Label("Connect in Split Right", systemImage: "rectangle.split.2x1")
        }

        Button(action: {
            let session = state.terminalManager.launchProfile(profile)
            state.terminalManager.splitMode = .horizontal
            state.terminalManager.secondarySessionId = session.id
        }) {
            Label("Connect in Split Down", systemImage: "rectangle.split.1x2")
        }

        Divider()

        Button(action: {
            populateProfileEditor(with: profile)
            showEditProfileSheet = true
        }) {
            Label("Edit Session Configuration...", systemImage: "pencil")
        }

        Button(action: {
            _ = state.terminalManager.duplicateProfile(id: profile.id)
            copyToastMessage = "Duplicated '\(profile.name)'"
        }) {
            Label("Duplicate Session", systemImage: "plus.square.on.square")
        }

        Menu("Move to Folder") {
            Button("Root / Unfiled") {
                state.terminalManager.moveProfile(id: profile.id, toFolderId: nil)
            }
            Divider()
            ForEach(state.terminalManager.folders) { f in
                Button(f.name) {
                    state.terminalManager.moveProfile(id: profile.id, toFolderId: f.id)
                }
            }
        }

        Divider()

        Button(action: {
            let cmd: String
            if profile.connectionType.lowercased() == "ssh" {
                cmd = "ssh -p \(profile.port) \(profile.username)@\(profile.host)"
            } else if profile.connectionType.lowercased() == "serial" {
                cmd = "screen \(profile.serialPath) \(profile.serialBaud)"
            } else {
                cmd = "zsh"
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(cmd, forType: .string)
            copyToastMessage = "Copied command to clipboard"
        }) {
            Label("Copy Connect Command", systemImage: "doc.on.doc")
        }

        Button(action: {
            let hostStr = profile.host.isEmpty ? profile.serialPath : profile.host
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(hostStr, forType: .string)
            copyToastMessage = "Copied: \(hostStr)"
        }) {
            Label("Copy Host / Device Path", systemImage: "network")
        }

        Divider()

        Button(role: .destructive, action: {
            state.terminalManager.deleteProfile(id: profile.id)
            copyToastMessage = "Deleted '\(profile.name)'"
        }) {
            Label("Delete Session", systemImage: "trash")
        }
    }

    // MARK: - Protocol Badge

    @ViewBuilder
    private func protocolBadgeView(type: String) -> some View {
        switch type.lowercased() {
        case "ssh":
            Text("SSH")
                .font(.system(size: 8, weight: .bold))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color(hex: "#10B981").opacity(0.2))
                .foregroundStyle(Color(hex: "#10B981"))
                .clipShape(RoundedRectangle(cornerRadius: 3))
        case "serial":
            Text("SER")
                .font(.system(size: 8, weight: .bold))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color(hex: "#F59E0B").opacity(0.2))
                .foregroundStyle(Color(hex: "#F59E0B"))
                .clipShape(RoundedRectangle(cornerRadius: 3))
        case "localshell", "shell", "local":
            Text("SH")
                .font(.system(size: 8, weight: .bold))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color(hex: "#8B5CF6").opacity(0.2))
                .foregroundStyle(Color(hex: "#8B5CF6"))
                .clipShape(RoundedRectangle(cornerRadius: 3))
        default:
            Text(type.prefix(3).uppercased())
                .font(.system(size: 8, weight: .bold))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Theme.neonCyan.opacity(0.2))
                .foregroundStyle(Theme.neonCyan)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
    }

    // MARK: - Sidebar Bottom Utilities Strip

    private var sidebarBottomUtilitiesStrip: some View {
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

    private func sessionSubtitle(for profile: TerminalProfile) -> String {
        switch profile.connectionType.lowercased() {
        case "serial":
            let path = profile.serialPath.components(separatedBy: "/").last ?? profile.serialPath
            return path.isEmpty ? "/dev/cu.usbserial (\(profile.serialBaud))" : "\(path) (\(profile.serialBaud))"
        case "localshell", "shell", "local":
            return "/bin/zsh (macOS)"
        default:
            return "\(profile.username)@\(profile.host):\(profile.port)"
        }
    }

    private func exportSessionLibraryToClipboard() {
        if let data = state.terminalManager.exportSessionLibrary(),
           let jsonStr = String(data: data, encoding: .utf8) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(jsonStr, forType: .string)
            copyToastMessage = "Exported \(state.terminalManager.savedProfiles.count) sessions to clipboard"
        }
    }

    private func importSessionLibraryFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string),
              let data = text.data(using: .utf8) else {
            copyToastMessage = "Clipboard does not contain valid JSON"
            return
        }
        do {
            let (f, p) = try state.terminalManager.importSessionLibrary(from: data)
            copyToastMessage = "Imported \(f) folders, \(p) sessions"
        } catch {
            copyToastMessage = "Import failed: invalid JSON envelope"
        }
    }

    private func performQuickConnect() {
        let input = quickConnectInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }

        var user = "ubuntu"
        var host = input
        var port = 22
        var pass: String? = nil

        if host.contains("@") {
            let parts = host.components(separatedBy: "@")
            user = parts[0]
            host = parts[1]
        }

        if user.contains(":") {
            let uParts = user.components(separatedBy: ":")
            user = uParts[0]
            pass = uParts[1]
        }

        if host.contains(":") {
            let parts = host.components(separatedBy: ":")
            host = parts[0]
            if let p = Int(parts[1]) {
                port = p
            }
        }

        // Check if there is an existing session with this host and user to preserve credentials
        if let existing = state.terminalManager.sessions.first(where: {
            if case .ssh(let h, _, let u, _, _, _, _) = $0.connectionType {
                return h == host && u == user
            }
            return false
        }), case .ssh(_, _, _, let key, let savedPass, let jump, let legacy) = existing.connectionType {
            state.terminalManager.openSSHSession(
                host: host,
                port: port,
                username: user,
                identityFile: key,
                password: pass ?? savedPass,
                jumpHost: jump,
                enableLegacyCiphers: legacy,
                autoConnect: true
            )
        } else {
            state.terminalManager.openSSHSession(
                host: host,
                port: port,
                username: user,
                password: pass,
                autoConnect: true
            )
        }
        quickConnectInput = ""
    }

    // MARK: - SSH Key Studio Modal (MobaKeyGen)

    private var localDiscoveredSSHKeys: [SSHKeyInfo] {
        state.terminalManager.keyStudio.discoverLocalKeys()
    }

    private var sshKeyStudioModal: some View {
        VStack(spacing: 16) {
            sshKeyStudioHeader

            Picker("Studio Mode", selection: $keyStudioTab) {
                Label("Keys & Generator", systemImage: "key.fill").tag(0)
                Label("Known Hosts Inspector", systemImage: "shield.lefthalf.filled").tag(1)
            }
            .pickerStyle(.segmented)

            if keyStudioTab == 0 {
                VStack(spacing: 16) {
                    sshKeyStudioDiscoveredKeys(localKeys: localDiscoveredSSHKeys)
                    Divider().overlay(Theme.borderLight)
                    sshKeyStudioGenerateForm
                    Divider().overlay(Theme.borderLight)
                    sshKeyStudioDeployForm(localKeys: localDiscoveredSSHKeys)
                }
            } else {
                sshKnownHostsInspectorView
            }
        }
        .padding(20)
        .frame(width: 640, height: 600)
        .onAppear {
            knownHostsList = state.terminalManager.keyStudio.loadKnownHosts()
        }
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

            HStack(spacing: 10) {
                Picker("Algorithm", selection: $newKeyType) {
                    Text("Ed25519 (Recommended)").tag("Ed25519")
                    Text("RSA 4096-bit (Legacy)").tag("RSA")
                }
                .pickerStyle(.segmented)

                TextField("Comment (e.g. user@mac)", text: $newKeyComment)
                    .textFieldStyle(.roundedBorder)

                SecureField("Passphrase (opt)", text: $newKeyPassphrase)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)

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
                newKey = try state.terminalManager.keyStudio.generateEd25519Key(passphrase: newKeyPassphrase, comment: newKeyComment)
            } else {
                newKey = try state.terminalManager.keyStudio.generateRSAKey(passphrase: newKeyPassphrase, comment: newKeyComment)
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

    // MARK: - Known Hosts Inspector View

    private var filteredKnownHosts: [KnownHostEntry] {
        if knownHostsSearch.trimmingCharacters(in: .whitespaces).isEmpty {
            return knownHostsList
        }
        let q = knownHostsSearch.lowercased()
        return knownHostsList.filter {
            $0.host.lowercased().contains(q) ||
            $0.keyType.lowercased().contains(q) ||
            $0.keySnippet.lowercased().contains(q)
        }
    }

    private var sshKnownHostsInspectorView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SSH KNOWN HOSTS INSPECTOR (~/.ssh/known_hosts)")
                        .font(Theme.monoText(10, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text("Inspect trusted server fingerprints and eliminate 'Host Key Verification Failed' collisions.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: {
                    knownHostsList = state.terminalManager.keyStudio.loadKnownHosts()
                    knownHostsStatusMsg = "Refreshed known_hosts (\(knownHostsList.count) entries)"
                }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.system(size: 10))
                }
                .buttonStyle(.bordered)
            }

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search host, IP address, or key algorithm...", text: $knownHostsSearch)
                    .textFieldStyle(.plain)
                if !knownHostsSearch.isEmpty {
                    Button(action: { knownHostsSearch = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(7)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.borderLight, lineWidth: 0.5))

            if let msg = knownHostsStatusMsg {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(Theme.neonCyan)
                    Text(msg)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.neonCyan)
                    Spacer()
                }
                .padding(6)
                .background(Theme.neonCyan.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            if filteredKnownHosts.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "shield.slash")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("No known hosts found")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(knownHostsList.isEmpty ?
                         "Your ~/.ssh/known_hosts file is empty or does not exist yet." :
                         "No entries match query '\(knownHostsSearch)'.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(filteredKnownHosts, id: \.id) { entry in
                            knownHostRow(entry: entry)
                        }
                    }
                }
            }
        }
    }

    private func knownHostRow(entry: KnownHostEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: entry.isHashed ? "number.square.fill" : "server.rack")
                .foregroundStyle(entry.isHashed ? Theme.solarAmber : Theme.neonCyan)
                .font(.system(size: 14))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.host)
                        .font(Theme.monoText(11, weight: .bold))
                        .foregroundStyle(Color.primary)
                    Text(entry.keyType)
                        .font(Theme.monoText(9, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Theme.borderLight)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .foregroundStyle(.secondary)
                    Text("Line \(entry.lineNumber)")
                        .font(Theme.monoText(9))
                        .foregroundStyle(.secondary)
                }
                Text(entry.keySnippet)
                    .font(Theme.monoText(9))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: {
                purgeKnownHost(entry)
            }) {
                HStack(spacing: 3) {
                    Image(systemName: "trash")
                    Text("Purge (ssh-keygen -R)")
                }
                .font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .tint(Theme.crimsonCritical)
            .help("Execute ssh-keygen -R to purge this host entry and fix host identification errors")
        }
        .padding(8)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.borderLight, lineWidth: 0.5))
    }

    private func purgeKnownHost(_ entry: KnownHostEntry) {
        do {
            let target = entry.isHashed ? (entry.rawLine.components(separatedBy: " ").first ?? "") : entry.host
            try state.terminalManager.keyStudio.removeKnownHost(target: target)
            knownHostsList = state.terminalManager.keyStudio.loadKnownHosts()
            knownHostsStatusMsg = "Purged '\(entry.host)' via ssh-keygen -R. Host identification reset."
        } catch {
            knownHostsStatusMsg = "Failed to purge: \(error.localizedDescription)"
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
        .onAppear {
            for tunnel in sshTunnels where tunnel.isActive {
                if let lat = state.terminalManager.tunnelManager.probeLocalPort(port: tunnel.localPort) {
                    tunnelLatencies[tunnel.id] = lat
                }
            }
        }
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

                                if let lat = tunnelLatencies[tunnel.id] {
                                    HStack(spacing: 3) {
                                        Circle().fill(Theme.emeraldHealthy).frame(width: 5, height: 5)
                                        Text(String(format: "%.1f ms", lat))
                                            .font(Theme.monoText(9, weight: .bold))
                                            .foregroundStyle(Theme.emeraldHealthy)
                                    }
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Theme.emeraldHealthy.opacity(0.12))
                                    .clipShape(Capsule())
                                    .help("Local forward socket response latency")
                                } else if tunnel.isActive {
                                    Button(action: {
                                        if let lat = state.terminalManager.tunnelManager.probeLocalPort(port: tunnel.localPort) {
                                            tunnelLatencies[tunnel.id] = lat
                                        }
                                    }) {
                                        HStack(spacing: 2) {
                                            Image(systemName: "waveform.path")
                                                .font(.system(size: 8))
                                            Text("Probe")
                                                .font(.system(size: 9))
                                        }
                                        .foregroundStyle(Theme.cyanPulse)
                                    }
                                    .buttonStyle(.plain)
                                }

                                if tunnel.isActive && tunnel.tunnelType == .localForward {
                                    Button(action: {
                                        state.terminalManager.tunnelManager.launchWebBrowser(for: tunnel)
                                    }) {
                                        Image(systemName: "globe")
                                            .font(.system(size: 11))
                                            .foregroundStyle(Theme.neonCyan)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Open Web GUI in Browser (http://localhost:\(tunnel.localPort))")
                                }

                                Button(tunnel.isActive ? "Stop" : "Start") {
                                    if tunnel.isActive {
                                        state.terminalManager.tunnelManager.stopTunnel(id: tunnel.id)
                                        tunnelLatencies.removeValue(forKey: tunnel.id)
                                    } else {
                                        try? state.terminalManager.tunnelManager.startTunnel(id: tunnel.id)
                                        if let lat = state.terminalManager.tunnelManager.probeLocalPort(port: tunnel.localPort) {
                                            tunnelLatencies[tunnel.id] = lat
                                        }
                                    }
                                }
                                .buttonStyle(.bordered)
                                .tint(tunnel.isActive ? Theme.crimsonCritical : Theme.emeraldHealthy)

                                Button(action: {
                                    state.terminalManager.tunnelManager.deleteTunnel(id: tunnel.id)
                                    tunnelLatencies.removeValue(forKey: tunnel.id)
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

    // MARK: - AttributedString & Line Rendering Engine

    @ViewBuilder
    private func renderTerminalLine(_ line: TerminalLine, session: TerminalSession) -> some View {
        let theme = effectiveTheme(for: session)
        let fSize = effectiveFontSize(for: session)
        let fFamily = effectiveFontFamily(for: session)

        if line.isCommandInput {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(">")
                    .font(Theme.terminalFont(family: fFamily, size: fSize, weight: .bold))
                    .foregroundStyle(Color(hex: theme.promptColorHex))
                Text(line.text)
                    .font(Theme.terminalFont(family: fFamily, size: fSize, weight: .semibold))
                    .foregroundStyle(Color(hex: theme.foregroundColorHex))
            }
        } else {
            Text(makeAttributedString(for: line, session: session))
                .textSelection(.enabled)
        }
    }

    private func makeAttributedString(for line: TerminalLine, session: TerminalSession) -> AttributedString {
        var result = AttributedString()
        let theme = effectiveTheme(for: session)
        let fSize = effectiveFontSize(for: session)
        let fFamily = effectiveFontFamily(for: session)
        let defaultFg = Color(hex: theme.foregroundColorHex)

        for span in line.spans {
            var attrSpan = AttributedString(span.text)
            attrSpan.font = Theme.terminalFont(
                family: fFamily,
                size: fSize,
                weight: span.style.isBold ? .bold : (span.style.isDim ? .light : .regular),
                isItalic: span.style.isItalic
            )
            if span.style.isUnderline {
                attrSpan.underlineStyle = .single
            }

            // Foreground color
            if let fg = span.style.foreground {
                let color = Color(red: Double(fg.r) / 255.0, green: Double(fg.g) / 255.0, blue: Double(fg.b) / 255.0)
                attrSpan.foregroundColor = color
            } else {
                attrSpan.foregroundColor = defaultFg
            }

            // Background color
            if let bg = span.style.background {
                let color = Color(red: Double(bg.r) / 255.0, green: Double(bg.g) / 255.0, blue: Double(bg.b) / 255.0)
                attrSpan.backgroundColor = color
            }

            // Inverse video
            if span.style.isInverse {
                let prevFg = attrSpan.foregroundColor ?? defaultFg
                let prevBg = attrSpan.backgroundColor ?? Color.clear
                attrSpan.foregroundColor = prevBg == Color.clear ? Color(hex: theme.backgroundColorHex) : prevBg
                attrSpan.backgroundColor = prevFg
            }

            result.append(attrSpan)
        }

        // Highlight search queries
        if !searchQuery.isEmpty {
            var searchStart = result.startIndex
            while searchStart < result.endIndex,
                  let range = result[searchStart...].range(of: searchQuery, options: .caseInsensitive) {
                result[range].backgroundColor = Theme.solarAmber.opacity(0.4)
                result[range].underlineStyle = .single
                searchStart = range.upperBound
            }
        }

        return result
    }

    // MARK: - Context Menus

    @ViewBuilder
    private func sessionTabContextMenu(for session: TerminalSession) -> some View {
        Button(action: { duplicateSession(session) }) {
            Label("Duplicate Session", systemImage: "plus.square.on.square")
        }
        Button(action: {
            state.terminalManager.splitMode = .vertical
            state.terminalManager.secondarySessionId = session.id
        }) {
            Label("Split Right", systemImage: "rectangle.split.2x1")
        }
        Button(action: {
            state.terminalManager.splitMode = .horizontal
            state.terminalManager.secondarySessionId = session.id
        }) {
            Label("Split Down", systemImage: "rectangle.split.1x2")
        }
        Divider()
        Button(action: {
            sessionToBookmark = session
            bookmarkNameInput = session.title
            bookmarkFolderId = state.terminalManager.folders.first?.id
            bookmarkTagsInput = ""
            bookmarkNotesInput = ""
            showBookmarkSessionSheet = true
        }) {
            Label("Save to Saved Sessions...", systemImage: "star.fill")
        }
        Divider()
        Button(action: {
            settingsTargetSessionId = session.id
            settingsScope = 1
            showTerminalSettingsSheet = true
        }) {
            Label("Fonts, Theme & Settings...", systemImage: "slider.horizontal.3")
        }
        Divider()
        Button(action: {
            session.disconnect()
            session.connect()
        }) {
            Label("Reconnect", systemImage: "arrow.clockwise")
        }
        Button(action: {
            state.terminalManager.closeSession(id: session.id)
        }) {
            Label("Close Tab", systemImage: "xmark")
        }
        Button(action: {
            closeOtherTabs(except: session.id)
        }) {
            Label("Close Other Tabs", systemImage: "xmark.circle")
        }
    }

    @ViewBuilder
    private func terminalCanvasContextMenu(session: TerminalSession) -> some View {
        Button(action: {
            copyAllTranscript(session)
        }) {
            Label("Copy All Transcript", systemImage: "doc.on.doc")
        }

        Button(action: {
            pasteFromClipboard(to: session)
        }) {
            Label("Paste", systemImage: "doc.on.clipboard")
        }

        Divider()

        Button(action: {
            session.clear()
        }) {
            Label("Clear Screen", systemImage: "trash")
        }

        Button(action: {
            session.disconnect()
            session.connect()
        }) {
            Label("Restart Session", systemImage: "arrow.clockwise")
        }

        Divider()

        Button(action: {
            settingsTargetSessionId = session.id
            settingsScope = 1
            showTerminalSettingsSheet = true
        }) {
            Label("Fonts, Theme & Cursor Settings...", systemImage: "slider.horizontal.3")
        }

        Divider()

        if case .ssh = session.connectionType {
            Button(action: {
                showFileTransferSheet = true
            }) {
                Label("SFTP / SCP File Transfer...", systemImage: "arrow.up.arrow.down.square")
            }
        }

        Button(action: {
            exportTranscript()
        }) {
            Label("Export Transcript to File...", systemImage: "square.and.arrow.up")
        }

        Button(action: {
            showPacedPasteSheet = true
        }) {
            Label("Run Paced Automation Script...", systemImage: "play.circle")
        }
    }

    // MARK: - Session Management & Clipboard

    private func duplicateSession(_ session: TerminalSession) {
        let newSession = TerminalSession(
            title: "\(session.title) (Copy)",
            connectionType: session.connectionType
        )
        newSession.showTimestamps = session.showTimestamps
        state.terminalManager.sessions.append(newSession)
        state.terminalManager.activeSessionId = newSession.id
        newSession.connect()
        showToast("Session duplicated")
    }

    private func closeOtherTabs(except keepId: UUID) {
        let others = state.terminalManager.sessions.filter { $0.id != keepId }
        for s in others {
            state.terminalManager.closeSession(id: s.id)
        }
    }

    private func copyAllTranscript(_ session: TerminalSession) {
        let transcript = session.exportSessionLog()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript, forType: .string)
        showToast("Transcript copied (\(session.lines.count) lines)")
    }

    private func pasteFromClipboard(to session: TerminalSession) {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        if state.terminalManager.isBroadcastEnabled {
            state.terminalManager.broadcastText(text)
        } else {
            session.sendRawString(text)
        }
    }

    private func showToast(_ message: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            copyToastMessage = message
        }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.3)) {
                    if copyToastMessage == message {
                        copyToastMessage = nil
                    }
                }
            }
        }
    }

    private func toggleRecording(for session: TerminalSession) {
        if session.isRecording {
            do {
                let url = try session.exportRecording()
                showToast("Asciinema recording saved: \(url.lastPathComponent)")
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                showToast("Failed to save recording: \(error.localizedDescription)")
            }
        } else {
            session.startRecording(cols: 80, rows: 24)
            showToast("Asciinema v2 recording started")
        }
    }

    // MARK: - Dual-Pane Interactive SFTP & SCP File Browser

    private var fileTransferModal: some View {
        VStack(spacing: 0) {
            // Modal Header Bar
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.arrow.down.square.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.cyanPulse)
                    Text("SFTP / SCP INTERACTIVE FILE EXPLORER")
                        .font(Theme.monoText(13, weight: .bold))
                        .foregroundStyle(.white)
                }

                Spacer()

                if let s = activeSession, case .ssh(let host, let port, let user, _, _, _, _) = s.connectionType {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Theme.emeraldHealthy)
                            .frame(width: 7, height: 7)
                        Text("\(user)@\(host):\(port)")
                            .font(Theme.monoText(11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.cardBackground)
                    .clipShape(Capsule())
                }

                Button(action: { showFileTransferSheet = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(Theme.surfaceBackground)

            Divider().overlay(Theme.borderLight)

            // Dual Panes Layout
            HStack(spacing: 0) {
                // LEFT PANE: LOCAL MAC FILES
                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Image(systemName: "laptopcomputer")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.solarAmber)
                        TextField("Local Path", text: $remoteFileBrowser.currentLocalPath)
                            .font(Theme.monoText(10))
                            .textFieldStyle(.plain)
                            .onSubmit {
                                remoteFileBrowser.refreshLocalDirectory()
                            }

                        Button(action: {
                            let parent = (remoteFileBrowser.currentLocalPath as NSString).deletingLastPathComponent
                            remoteFileBrowser.navigateLocal(to: parent)
                        }) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .help("Up to parent folder")

                        Button("Home") {
                            remoteFileBrowser.navigateLocal(to: FileManager.default.homeDirectoryForCurrentUser.path)
                        }
                        .font(.system(size: 10))
                        .buttonStyle(.bordered)
                    }
                    .padding(8)
                    .background(Theme.surfaceBackground.opacity(0.8))

                    Divider().overlay(Theme.borderLight)

                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(remoteFileBrowser.localItems) { item in
                                HStack {
                                    Image(systemName: item.iconName)
                                        .foregroundStyle(item.isDirectory ? Theme.solarAmber : .secondary)
                                        .frame(width: 16)

                                    Text(item.name)
                                        .font(Theme.monoText(11))
                                        .lineLimit(1)

                                    Spacer()

                                    Text(item.formattedSize)
                                        .font(Theme.monoText(10))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(remoteFileBrowser.selectedLocalItem?.id == item.id ? Theme.neonCyan.opacity(0.18) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    remoteFileBrowser.selectedLocalItem = item
                                }
                                .simultaneousGesture(TapGesture(count: 2).onEnded {
                                    if item.isDirectory {
                                        remoteFileBrowser.navigateLocal(to: item.path)
                                    }
                                })
                            }
                        }
                        .padding(6)
                    }
                }
                .frame(maxWidth: .infinity)

                Divider().overlay(Theme.borderLight)

                // MIDDLE PILLAR: ACTION BUTTONS
                VStack(spacing: 12) {
                    Spacer()

                    Button(action: uploadSelectedLocalFile) {
                        VStack(spacing: 3) {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 18))
                            Text("Upload")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .frame(width: 54, height: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.cyanPulse)
                    .foregroundStyle(.black)
                    .disabled(remoteFileBrowser.selectedLocalItem == nil || remoteFileBrowser.selectedLocalItem?.isDirectory == true || isTransferringFile)
                    .help("Upload selected local file to current remote folder")

                    Button(action: downloadSelectedRemoteFile) {
                        VStack(spacing: 3) {
                            Image(systemName: "arrow.left.circle.fill")
                                .font(.system(size: 18))
                            Text("Download")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .frame(width: 54, height: 48)
                    }
                    .buttonStyle(.bordered)
                    .disabled(remoteFileBrowser.selectedRemoteItem == nil || remoteFileBrowser.selectedRemoteItem?.isDirectory == true || isTransferringFile)
                    .help("Download selected remote file to current local folder")

                    Spacer()
                }
                .frame(width: 68)
                .background(Theme.surfaceBackground)

                Divider().overlay(Theme.borderLight)

                // RIGHT PANE: REMOTE SERVER FILES
                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.neonCyan)
                        TextField("Remote Path", text: $remoteFileBrowser.currentRemotePath)
                            .font(Theme.monoText(10))
                            .textFieldStyle(.plain)
                            .onSubmit {
                                refreshRemoteDir()
                            }

                        Button(action: {
                            let parent = (remoteFileBrowser.currentRemotePath as NSString).deletingLastPathComponent
                            remoteFileBrowser.currentRemotePath = parent.isEmpty ? "/" : parent
                            refreshRemoteDir()
                        }) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .help("Up to parent folder")

                        Button(action: { refreshRemoteDir() }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.plain)
                        .help("Refresh remote directory")

                        if let sel = remoteFileBrowser.selectedRemoteItem, !sel.isDirectory {
                            Button("Preview") {
                                if let s = activeSession, case .ssh(let h, let p, let u, let idFile, let pass, _, _) = s.connectionType {
                                    remoteFileBrowser.fetchRemoteFilePreview(item: sel, host: h, port: p, username: u, identityFile: idFile, password: pass)
                                }
                            }
                            .font(.system(size: 10))
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(8)
                    .background(Theme.surfaceBackground.opacity(0.8))

                    Divider().overlay(Theme.borderLight)

                    if remoteFileBrowser.isRemoteLoading {
                        VStack(spacing: 8) {
                            Spacer()
                            ProgressView()
                            Text("Loading remote directory...")
                                .font(Theme.monoText(11))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 2) {
                                ForEach(remoteFileBrowser.remoteItems) { item in
                                    HStack {
                                        Image(systemName: item.iconName)
                                            .foregroundStyle(item.isDirectory ? Theme.neonCyan : .secondary)
                                            .frame(width: 16)

                                        Text(item.name)
                                            .font(Theme.monoText(11))
                                            .lineLimit(1)

                                        Spacer()

                                        Text(item.permissions)
                                            .font(Theme.monoText(9))
                                            .foregroundStyle(Color.secondary.opacity(0.6))
                                            .frame(width: 75, alignment: .trailing)

                                        Text(item.formattedSize)
                                            .font(Theme.monoText(10))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 55, alignment: .trailing)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(remoteFileBrowser.selectedRemoteItem?.id == item.id ? Theme.neonCyan.opacity(0.18) : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        remoteFileBrowser.selectedRemoteItem = item
                                    }
                                    .simultaneousGesture(TapGesture(count: 2).onEnded {
                                        if item.isDirectory {
                                            remoteFileBrowser.currentRemotePath = item.path
                                            refreshRemoteDir()
                                        }
                                    })
                                }
                            }
                            .padding(6)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: 380)

            Divider().overlay(Theme.borderLight)

            // Status Bar & File Preview Area
            VStack(spacing: 8) {
                if let preview = remoteFileBrowser.previewFileContent {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Preview: \(remoteFileBrowser.previewFileName ?? "File")")
                                .font(Theme.monoText(11, weight: .bold))
                                .foregroundStyle(Theme.neonCyan)
                            Spacer()
                            Button("Close Preview") {
                                remoteFileBrowser.previewFileContent = nil
                            }
                            .font(.system(size: 10))
                        }
                        ScrollView {
                            Text(preview)
                                .font(Theme.monoText(10))
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }
                        .frame(height: 100)
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }

                if let msg = transferStatusMessage {
                    HStack(spacing: 6) {
                        if isTransferringFile {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: msg.contains("completed") ? "checkmark.circle.fill" : "info.circle.fill")
                                .foregroundStyle(msg.contains("completed") ? Theme.emeraldHealthy : Theme.neonCyan)
                        }
                        Text(msg)
                            .font(Theme.monoText(10))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
            .padding(10)
            .background(Theme.surfaceBackground)
        }
        .frame(width: 900, height: 520)
    }

    private func refreshRemoteDir() {
        if let s = activeSession, case .ssh(let host, let port, let user, let idFile, let pass, let jump, _) = s.connectionType {
            remoteFileBrowser.refreshRemoteDirectory(host: host, port: port, username: user, identityFile: idFile, password: pass, jumpHost: jump)
        }
    }

    private func uploadSelectedLocalFile() {
        guard let local = remoteFileBrowser.selectedLocalItem, let session = activeSession else { return }
        localFilePathToUpload = local.path
        let dest = remoteFileBrowser.currentRemotePath.hasSuffix("/") ? "\(remoteFileBrowser.currentRemotePath)\(local.name)" : "\(remoteFileBrowser.currentRemotePath)/\(local.name)"
        remoteUploadPath = dest
        performSCPTransfer(session: session, isUpload: true)
    }

    private func downloadSelectedRemoteFile() {
        guard let remote = remoteFileBrowser.selectedRemoteItem, let session = activeSession else { return }
        remoteUploadPath = remote.path
        let dest = remoteFileBrowser.currentLocalPath.hasSuffix("/") ? "\(remoteFileBrowser.currentLocalPath)\(remote.name)" : "\(remoteFileBrowser.currentLocalPath)/\(remote.name)"
        localFilePathToUpload = dest
        performSCPTransfer(session: session, isUpload: false)
    }

    private func selectLocalFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            localFilePathToUpload = url.path
        }
    }

    private func performSCPTransfer(session: TerminalSession, isUpload: Bool) {
        guard case .ssh(let host, let port, let username, let identityFile, let password, _, _) = session.connectionType else {
            transferStatusMessage = "Error: Current session is not an SSH connection."
            return
        }

        let localPath = localFilePathToUpload
        let remotePath = remoteUploadPath

        guard !localPath.isEmpty, !remotePath.isEmpty else {
            transferStatusMessage = "Please specify both local and remote paths."
            return
        }

        isTransferringFile = true
        transferStatusMessage = "Initiating file transfer..."

        Task.detached(priority: .userInitiated) {
            let process = Process()
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            var env = ProcessInfo.processInfo.environment
            env["LANG"] = "en_US.UTF-8"

            var args: [String] = [
                "-P", "\(port)",
                "-o", "StrictHostKeyChecking=accept-new",
                "-o", "ConnectTimeout=10"
            ]

            if let identity = identityFile, !identity.isEmpty {
                args.append(contentsOf: ["-i", identity])
            }

            let remoteTarget = "\(username)@\(host):\(remotePath)"

            if isUpload {
                args.append(localPath)
                args.append(remoteTarget)
            } else {
                args.append(remoteTarget)
                args.append(localPath)
            }

            let fileManager = FileManager.default
            let sshpassPath = fileManager.fileExists(atPath: "/opt/homebrew/bin/sshpass") ? "/opt/homebrew/bin/sshpass" :
                              (fileManager.fileExists(atPath: "/usr/local/bin/sshpass") ? "/usr/local/bin/sshpass" : nil)

            if let pass = password, !pass.isEmpty, let sshpass = sshpassPath {
                process.executableURL = URL(fileURLWithPath: sshpass)
                process.arguments = ["-p", pass, "/usr/bin/scp"] + args
            } else {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/scp")
                process.arguments = args
                if let pass = password, !pass.isEmpty {
                    env["SSHPASS"] = pass
                }
            }
            process.environment = env

            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""

                await MainActor.run {
                    isTransferringFile = false
                    if process.terminationStatus == 0 {
                        transferStatusMessage = "File transfer successfully completed!"
                        showToast("File transfer completed!")
                        remoteFileBrowser.refreshLocalDirectory()
                        refreshRemoteDir()
                    } else {
                        transferStatusMessage = "Transfer failed (code \(process.terminationStatus)): \(output)"
                    }
                }
            } catch {
                await MainActor.run {
                    isTransferringFile = false
                    transferStatusMessage = "Transfer error: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Hardware Serial Modem Signals Modal

    private var modemSignalModal: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Hardware Serial Modem Signals (RS-232 / UART)", systemImage: "waveform.path.ecg")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Button("Close") { showModemSignalSheet = false }
                    .buttonStyle(.plain)
            }

            if let s = activeSession, case .serial(let path, let baud, _, _, _) = s.connectionType {
                Text("Port: \(path) at \(baud) baud")
                    .font(Theme.monoText(11))
                    .foregroundStyle(.secondary)
            }

            Divider().overlay(Theme.borderLight)

            VStack(spacing: 12) {
                Text("LINE SIGNALS (INPUT / OUTPUT)")
                    .font(Theme.monoText(10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    modemSignalChip(name: "DTR (Data Terminal Ready)", isActive: modemStatus.dtr)
                    modemSignalChip(name: "RTS (Request to Send)", isActive: modemStatus.rts)
                    modemSignalChip(name: "CTS (Clear to Send)", isActive: modemStatus.cts)
                    modemSignalChip(name: "DSR (Data Set Ready)", isActive: modemStatus.dsr)
                    modemSignalChip(name: "DCD (Carrier Detect)", isActive: modemStatus.dcd)
                    modemSignalChip(name: "RI (Ring Indicator)", isActive: modemStatus.ri)
                }
            }
            .padding(12)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Divider().overlay(Theme.borderLight)

            VStack(alignment: .leading, spacing: 8) {
                Text("MANUAL LINE TOGGLES")
                    .font(Theme.monoText(10, weight: .bold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button("Toggle DTR (\(modemStatus.dtr ? "HIGH" : "LOW"))") {
                        let newDTR = !modemStatus.dtr
                        activeSession?.setModemSignal(dtr: newDTR)
                        modemStatus.dtr = newDTR
                    }
                    .buttonStyle(.bordered)
                    .tint(modemStatus.dtr ? Theme.emeraldHealthy : .secondary)

                    Button("Toggle RTS (\(modemStatus.rts ? "HIGH" : "LOW"))") {
                        let newRTS = !modemStatus.rts
                        activeSession?.setModemSignal(rts: newRTS)
                        modemStatus.rts = newRTS
                    }
                    .buttonStyle(.bordered)
                    .tint(modemStatus.rts ? Theme.emeraldHealthy : .secondary)

                    Spacer()

                    Button("Refresh Pins") {
                        if let s = activeSession, let st = s.queryModemStatus() {
                            modemStatus = st
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.cyanPulse)
                    .foregroundStyle(.black)
                }
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear {
            if let s = activeSession, let st = s.queryModemStatus() {
                modemStatus = st
            }
        }
    }

    private func modemSignalChip(name: String, isActive: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isActive ? Theme.emeraldHealthy : Color.secondary.opacity(0.3))
                .frame(width: 8, height: 8)
            Text(name)
                .font(Theme.monoText(9, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Terminal Typography & Session Customization Modal

    private var terminalSettingsModal: some View {
        let currentScopeIsTab = (settingsScope == 1 && targetSettingsSession != nil)
        let activeTab = targetSettingsSession

        // Effective values for bindings and live preview
        let currentFontFamily = currentScopeIsTab ? (activeTab?.fontFamilyOverride ?? globalFontFamily) : globalFontFamily
        let currentFontSize = currentScopeIsTab ? (activeTab?.fontSizeOverride ?? CGFloat(globalFontSize)) : CGFloat(globalFontSize)
        let currentTheme = currentScopeIsTab ? (activeTab?.themeOverride ?? (TerminalTheme(rawValue: globalThemeName) ?? .obsidian)) : (TerminalTheme(rawValue: globalThemeName) ?? .obsidian)
        let currentCursor = currentScopeIsTab ? (activeTab?.cursorStyleOverride ?? (TerminalCursorStyle(rawValue: globalCursorStyle) ?? .block)) : (TerminalCursorStyle(rawValue: globalCursorStyle) ?? .block)

        let fontFamilyBinding = Binding<String>(
            get: { currentFontFamily },
            set: { newFamily in
                if currentScopeIsTab {
                    activeTab?.fontFamilyOverride = newFamily
                } else {
                    globalFontFamily = newFamily
                }
            }
        )

        let fontSizeBinding = Binding<Double>(
            get: { Double(currentFontSize) },
            set: { newSize in
                if currentScopeIsTab {
                    activeTab?.fontSizeOverride = CGFloat(newSize)
                    if let s = activeTab { updatePTYDimensions(for: s, size: CGSize(width: 800, height: 500)) }
                } else {
                    globalFontSize = newSize
                    updatePTYDimensions()
                }
            }
        )

        let themeBinding = Binding<TerminalTheme>(
            get: { currentTheme },
            set: { newTheme in
                if currentScopeIsTab {
                    activeTab?.themeOverride = newTheme
                } else {
                    globalThemeName = newTheme.rawValue
                }
            }
        )

        let cursorStyleBinding = Binding<TerminalCursorStyle>(
            get: { currentCursor },
            set: { newCursor in
                if currentScopeIsTab {
                    activeTab?.cursorStyleOverride = newCursor
                } else {
                    globalCursorStyle = newCursor.rawValue
                }
            }
        )

        return VStack(spacing: 0) {
            // Modal Header
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Theme.cyanPulse.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.cyanPulse)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Terminal Display & Session Settings")
                        .font(.system(size: 15, weight: .bold))
                    Text("Configure monospace font family, size, line spacing, themes, and cursor styling")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Done") {
                    showTerminalSettingsSheet = false
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.cyanPulse)
                .foregroundStyle(Color.black)
                .controlSize(.small)
            }
            .padding(16)
            .background(Theme.cardBackground)

            Divider().overlay(Theme.borderLight)

            // Scope Selector Strip
            HStack(spacing: 12) {
                Picker("Target Scope", selection: $settingsScope) {
                    Text("Global Defaults (All Tabs)").tag(0)
                    if let tab = activeTab {
                        Text("Active Tab: \(tab.title)").tag(1)
                    }
                }
                .pickerStyle(.segmented)

                if currentScopeIsTab, let tab = activeTab {
                    let hasOverrides = tab.fontSizeOverride != nil || tab.fontFamilyOverride != nil || tab.themeOverride != nil || tab.cursorStyleOverride != nil
                    if hasOverrides {
                        Button(action: {
                            tab.fontSizeOverride = nil
                            tab.fontFamilyOverride = nil
                            tab.themeOverride = nil
                            tab.cursorStyleOverride = nil
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.counterclockwise")
                                Text("Reset to Global")
                            }
                            .font(.system(size: 10.5, weight: .semibold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Clear tab-specific overrides and revert to global preferences")
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.surfaceBackground)

            Divider().overlay(Theme.borderLight)

            // Main Settings Scrollable Body
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Section 1: Typography & Font Engine
                    VStack(alignment: .leading, spacing: 12) {
                        Label("TYPOGRAPHY & MONOSPACE ENGINE", systemImage: "textformat")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.neonCyan)

                        VStack(spacing: 10) {
                            // Font Family Picker
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Monospace Font Family")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text("Apple system monospace, macOS classic, or developer fonts")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Picker("", selection: fontFamilyBinding) {
                                    ForEach(TerminalFontFamily.allCases) { f in
                                        Text(f.rawValue).tag(f.rawValue)
                                    }
                                }
                                .frame(width: 200)
                            }

                            Divider().overlay(Theme.borderLight)

                            // Font Size Slider & Stepper
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Font Size")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text("Scales viewport columns/rows and PTY terminal grid")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                HStack(spacing: 10) {
                                    Slider(value: fontSizeBinding, in: 9...28, step: 1)
                                        .frame(width: 120)
                                    Text("\(Int(currentFontSize)) pt")
                                        .font(Theme.monoText(12, weight: .bold))
                                        .frame(width: 36, alignment: .trailing)
                                    Stepper("", value: fontSizeBinding, in: 9...28, step: 1)
                                        .labelsHidden()
                                }
                            }

                            // Quick Preset Size Pills
                            HStack(spacing: 6) {
                                Text("Quick Presets:")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.secondary)
                                ForEach([10, 11, 12, 13, 14, 16, 18, 20], id: \.self) { sz in
                                    Button(action: { fontSizeBinding.wrappedValue = Double(sz) }) {
                                        Text("\(sz)pt")
                                            .font(Theme.monoText(10, weight: Int(currentFontSize) == sz ? .bold : .regular))
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 3)
                                            .background(Int(currentFontSize) == sz ? Theme.neonCyan.opacity(0.2) : Theme.cardBackground)
                                            .foregroundStyle(Int(currentFontSize) == sz ? Theme.neonCyan : .primary)
                                            .clipShape(RoundedRectangle(cornerRadius: 5))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 5)
                                                    .stroke(Int(currentFontSize) == sz ? Theme.neonCyan.opacity(0.8) : Theme.borderLight, lineWidth: 1)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            Divider().overlay(Theme.borderLight)

                            // Line Spacing
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Line Spacing")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text("Vertical breathing room between terminal output lines")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Picker("", selection: $globalLineSpacing) {
                                    Text("Compact (0pt)").tag(0.0)
                                    Text("Standard (2pt)").tag(2.0)
                                    Text("Relaxed (4pt)").tag(4.0)
                                    Text("Spacious (6pt)").tag(6.0)
                                }
                                .frame(width: 170)
                            }
                        }
                        .padding(12)
                        .background(Theme.cardBackground)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderLight, lineWidth: 1))
                    }

                    // Section 2: Cursor & Interactive Styling
                    VStack(alignment: .leading, spacing: 12) {
                        Label("CURSOR APPEARANCE & ANIMATION", systemImage: "terminal")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.solarAmber)

                        VStack(spacing: 10) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Cursor Style")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text("Choose block glyph, vertical beam, or classic underline")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Picker("", selection: cursorStyleBinding) {
                                    ForEach(TerminalCursorStyle.allCases) { c in
                                        Text(c.rawValue).tag(c)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 220)
                            }

                            Divider().overlay(Theme.borderLight)

                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Blinking Cursor")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text("Pulse cursor cadence at 530ms interval during interactive input")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Toggle("", isOn: $globalCursorBlink)
                                    .toggleStyle(.switch)
                                    .controlSize(.small)
                            }
                        }
                        .padding(12)
                        .background(Theme.cardBackground)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderLight, lineWidth: 1))
                    }

                    // Section 3: Color Themes & Schemes
                    VStack(alignment: .leading, spacing: 12) {
                        Label("COLOR SCHEME & PALETTE", systemImage: "paintpalette.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.emeraldHealthy)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(TerminalTheme.allCases) { theme in
                                let isSelected = currentTheme == theme
                                Button(action: { themeBinding.wrappedValue = theme }) {
                                    HStack(spacing: 10) {
                                        // Preview swatch dots
                                        HStack(spacing: 3) {
                                            Circle()
                                                .fill(Color(hex: theme.backgroundColorHex))
                                                .frame(width: 14, height: 14)
                                                .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
                                            Circle()
                                                .fill(Color(hex: theme.foregroundColorHex))
                                                .frame(width: 14, height: 14)
                                            Circle()
                                                .fill(Color(hex: theme.promptColorHex))
                                                .frame(width: 14, height: 14)
                                        }

                                        Text(theme.rawValue)
                                            .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                                            .foregroundStyle(isSelected ? Theme.neonCyan : .primary)

                                        Spacer()

                                        if isSelected {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(Theme.neonCyan)
                                                .font(.system(size: 12))
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(Color(hex: theme.backgroundColorHex).opacity(0.6))
                                    .cornerRadius(6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(isSelected ? Theme.neonCyan : Theme.borderLight, lineWidth: isSelected ? 1.5 : 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Section 4: Scrollback Depth & Timestamp Prefixes
                    VStack(alignment: .leading, spacing: 12) {
                        Label("BUFFER & OUTPUT LOGGING", systemImage: "clock.arrow.circlepath")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.cyanPulse)

                        VStack(spacing: 10) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Scrollback History Limit")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text("Maximum lines retained per session buffer in RAM")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Picker("", selection: $globalMaxBuffer) {
                                    Text("1,000 lines").tag(1000)
                                    Text("5,000 lines").tag(5000)
                                    Text("10,000 lines").tag(10000)
                                    Text("50,000 lines").tag(50000)
                                }
                                .frame(width: 150)
                            }

                            if let tab = activeTab {
                                Divider().overlay(Theme.borderLight)

                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Prefix Millisecond Timestamps")
                                            .font(.system(size: 12, weight: .semibold))
                                        Text("Display [HH:mm:ss.SSS] alongside each terminal line")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Toggle("", isOn: Binding(
                                        get: { tab.showTimestamps },
                                        set: { tab.showTimestamps = $0 }
                                    ))
                                    .toggleStyle(.switch)
                                    .controlSize(.small)
                                }
                            }
                        }
                        .padding(12)
                        .background(Theme.cardBackground)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderLight, lineWidth: 1))
                    }

                    // Section 5: Live Interactive Terminal Preview
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("LIVE TERMINAL PREVIEW", systemImage: "play.tv.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Theme.neonCyan)
                            Spacer()
                            Text("\(currentFontFamily) @ \(Int(currentFontSize))pt — \(currentTheme.rawValue)")
                                .font(Theme.monoText(10))
                                .foregroundStyle(.secondary)
                        }

                        // Terminal Window Mockup
                        VStack(alignment: .leading, spacing: 0) {
                            // Top Window Controls
                            HStack(spacing: 6) {
                                Circle().fill(Color(hex: "#FF5F56")).frame(width: 10, height: 10)
                                Circle().fill(Color(hex: "#FFBD2E")).frame(width: 10, height: 10)
                                Circle().fill(Color(hex: "#27C93F")).frame(width: 10, height: 10)
                                Spacer()
                                Text("cisco-catalyst-core-01 — ssh -p 22 admin@10.0.10.1")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Color.secondary.opacity(0.8))
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.4))

                            // Terminal Body
                            VStack(alignment: .leading, spacing: CGFloat(globalLineSpacing)) {
                                HStack(spacing: 4) {
                                    Text("switch-core-01#")
                                        .font(Theme.terminalFont(family: currentFontFamily, size: currentFontSize, weight: .bold))
                                        .foregroundStyle(Color(hex: currentTheme.promptColorHex))
                                    Text("show ip interface brief")
                                        .font(Theme.terminalFont(family: currentFontFamily, size: currentFontSize, weight: .semibold))
                                        .foregroundStyle(Color(hex: currentTheme.foregroundColorHex))
                                }

                                Text("Interface              IP-Address      OK? Status                Protocol")
                                    .font(Theme.terminalFont(family: currentFontFamily, size: currentFontSize, weight: .bold))
                                    .foregroundStyle(Color(hex: currentTheme.foregroundColorHex).opacity(0.85))

                                Text("GigabitEthernet0/0/0   192.168.10.1    YES up                    up")
                                    .font(Theme.terminalFont(family: currentFontFamily, size: currentFontSize))
                                    .foregroundStyle(Color(hex: currentTheme.foregroundColorHex))

                                Text("GigabitEthernet0/0/1   10.0.0.2        YES up                    up")
                                    .font(Theme.terminalFont(family: currentFontFamily, size: currentFontSize))
                                    .foregroundStyle(Color(hex: currentTheme.foregroundColorHex))

                                Text("Loopback0              172.16.0.1      YES up                    up")
                                    .font(Theme.terminalFont(family: currentFontFamily, size: currentFontSize))
                                    .foregroundStyle(Color(hex: currentTheme.foregroundColorHex))

                                HStack(spacing: 4) {
                                    Text("switch-core-01#")
                                        .font(Theme.terminalFont(family: currentFontFamily, size: currentFontSize, weight: .bold))
                                        .foregroundStyle(Color(hex: currentTheme.promptColorHex))
                                    Text("ping 8.8.8.8")
                                        .font(Theme.terminalFont(family: currentFontFamily, size: currentFontSize))
                                        .foregroundStyle(Color(hex: currentTheme.foregroundColorHex))
                                }

                                Text("Sending 5, 100-byte ICMP Echos to 8.8.8.8, timeout is 2 seconds:\n!!!!!\nSuccess rate is 100 percent (5/5), round-trip min/avg/max = 1/2/4 ms")
                                    .font(Theme.terminalFont(family: currentFontFamily, size: currentFontSize))
                                    .foregroundStyle(Color(hex: currentTheme.foregroundColorHex))

                                HStack(spacing: 0) {
                                    Text("switch-core-01# ")
                                        .font(Theme.terminalFont(family: currentFontFamily, size: currentFontSize, weight: .bold))
                                        .foregroundStyle(Color(hex: currentTheme.promptColorHex))
                                    BlinkingCursorView(
                                        isFocused: true,
                                        color: Color(hex: currentTheme.promptColorHex),
                                        fontSize: currentFontSize,
                                        fontFamily: currentFontFamily,
                                        style: currentCursor,
                                        shouldBlink: globalCursorBlink
                                    )
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(hex: currentTheme.backgroundColorHex))
                        }
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderLight, lineWidth: 1))
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 650, height: 600)
        .background(Theme.surfaceBackground)
    }
}

private struct InlinePasswordBar: View {
    @Binding var inputCommand: String
    var onSend: () -> Void
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(Theme.solarAmber)
            SecureField("Enter password / passphrase...", text: $inputCommand)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
                .focused($isFieldFocused)
                .onSubmit {
                    onSend()
                }
            Button("Send") {
                onSend()
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.solarAmber)
        }
        .padding(8)
        .background(Theme.solarAmber.opacity(0.12))
        .cornerRadius(8)
        .padding(.top, 4)
        .onAppear {
            isFieldFocused = true
        }
    }
}

private struct BlinkingCursorView: View {
    let isFocused: Bool
    let color: Color
    let fontSize: CGFloat
    var fontFamily: String = "SF Mono (System)"
    var style: TerminalCursorStyle = .block
    var shouldBlink: Bool = true

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.53)) { (timeline: TimelineViewDefaultContext) in
            cursorContent(timeline: timeline)
        }
    }

    private func cursorContent(timeline: TimelineViewDefaultContext) -> some View {
        let isVisible = !shouldBlink || (Int(timeline.date.timeIntervalSinceReferenceDate / 0.53) % 2 == 0)
        return Text(style.cursorGlyph)
            .font(Theme.terminalFont(family: fontFamily, size: fontSize, weight: .bold))
            .foregroundStyle(isFocused ? color : color.opacity(0.35))
            .opacity(isFocused ? (isVisible ? 1.0 : 0.0) : 0.4)
    }
}


