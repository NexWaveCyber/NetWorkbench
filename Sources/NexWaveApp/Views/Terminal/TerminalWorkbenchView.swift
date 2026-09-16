import SwiftUI
import TerminalKit
import CommandLibrary
import AppKit

/// Integrated tabbed SSH, USB Serial Console, and Simulated CLI terminal environment
public struct TerminalWorkbenchView: View {
    @Bindable var state: AppState
    @State private var inputCommand: String = ""
    @State private var showNewSessionSheet: Bool = false
    @State private var fontSize: CGFloat = 12
    @State private var autoScroll: Bool = true
    @State private var historyIndex: Int = -1

    // New Session Form States
    @State private var newSessionType: Int = 0 // 0: SSH, 1: Serial, 2: Simulation, 3: Local Shell
    @State private var sshHost: String = "192.168.1.1"
    @State private var sshPort: String = "22"
    @State private var sshUser: String = "admin"
    @State private var sshPassword: String = ""
    @State private var sshKeyPath: String = ""
    @State private var selectedSerialPort: String = ""
    @State private var selectedBaudRate: Int = 9600
    @State private var selectedSimPreset: String = "Catalyst 9300 Core"

    public init(state: AppState) {
        self.state = state
    }

    private var activeSession: TerminalSession? {
        state.terminalManager.activeSession
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerBar

            Divider().overlay(Theme.borderLight)

            // Session Tab Strip
            sessionTabBar

            Divider().overlay(Theme.borderLight)

            // Quick Command Macro Snippets Strip
            commandSnippetsBar

            Divider().overlay(Theme.borderLight)

            // Main Terminal Canvas & Input
            if let session = activeSession {
                terminalConsoleView(session: session)
            } else {
                emptySessionPlaceholder
            }
        }
        .background(Theme.surfaceBackground)
        .sheet(isPresented: $showNewSessionSheet) {
            newSessionModal
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
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                    HUDStatusBadge(
                        title: activeSession?.status.rawValue ?? "No Session",
                        color: Color(hex: activeSession?.status.badgeColorHex ?? "#8E8E93"),
                        icon: activeSession?.status == .connected ? "antenna.radiowaves.left.and.right" : nil
                    )
                }
                Text("Direct PTY SSH, RS-232 / USB Serial Console, and Cisco/Arista Command Runner")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Header Utilities
            HStack(spacing: 8) {
                // Font Size Adjuster
                HStack(spacing: 4) {
                    Button(action: { if fontSize > 10 { fontSize -= 1 } }) {
                        Image(systemName: "textformat.size.smaller")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)

                    Text("\(Int(fontSize))pt")
                        .font(Theme.monoText(10))
                        .foregroundStyle(.secondary)
                        .frame(width: 28)

                    Button(action: { if fontSize < 18 { fontSize += 1 } }) {
                        Image(systemName: "textformat.size.larger")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                // External Terminal Launch Menu
                Menu {
                    if let session = activeSession, case .ssh(let host, let port, let user, _, _) = session.connectionType {
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
                    Label("External App", systemImage: "arrow.up.forward.app")
                        .font(.system(size: 11))
                }
                .menuStyle(.borderedButton)

                // Export Transcript
                Button(action: exportTranscript) {
                    Label("Export Log", systemImage: "square.and.arrow.up")
                        .font(.system(size: 11))
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
        .padding(.vertical, 10)
        .background(Theme.surfaceBackground)
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

    // MARK: - Quick Command Snippets Bar

    private var commandSnippetsBar: some View {
        HStack(spacing: 8) {
            Text("MACROS:")
                .font(Theme.monoText(9, weight: .bold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    macroChip("show ip int br")
                    macroChip("show version")
                    macroChip("show cdp neighbors")
                    macroChip("show lldp neighbors")
                    macroChip("show running-config")
                    macroChip("show mac address-table")
                    macroChip("show ip route")
                    macroChip("write memory")
                    macroChip("ping 1.1.1.1")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .background(Theme.surfaceBackground.opacity(0.8))
    }

    private func macroChip(_ command: String) -> some View {
        Button(action: {
            activeSession?.sendCommand(command)
        }) {
            Text(command)
                .font(Theme.monoText(10, weight: .medium))
                .foregroundStyle(Theme.cyanPulse)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Theme.cyanPulse.opacity(0.08))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Theme.cyanPulse.opacity(0.2), lineWidth: 0.75))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Terminal Console & Input

    private func terminalConsoleView(session: TerminalSession) -> some View {
        VStack(spacing: 0) {
            // Screen output
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(session.lines) { line in
                            if line.isCommandInput {
                                HStack(spacing: 6) {
                                    Text(">")
                                        .font(Theme.monoText(fontSize, weight: .bold))
                                        .foregroundStyle(Theme.cyanPulse)
                                    Text(line.text)
                                        .font(Theme.monoText(fontSize, weight: .semibold))
                                        .foregroundStyle(Color.white)
                                }
                                .padding(.vertical, 1)
                            } else {
                                Text(line.text)
                                    .font(Theme.monoText(fontSize))
                                    .foregroundStyle(terminalOutputColor(for: line.text))
                                    .textSelection(.enabled)
                            }
                        }
                        Color.clear
                            .frame(height: 1)
                            .id("bottomAnchor")
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(red: 0.05, green: 0.06, blue: 0.08))
                .onChange(of: session.lines.count) { _, _ in
                    if autoScroll {
                        proxy.scrollTo("bottomAnchor", anchor: .bottom)
                    }
                }
            }

            Divider().overlay(Theme.borderLight)

            // Input Bar
            HStack(spacing: 8) {
                Text("\(session.title) #")
                    .font(Theme.monoText(11, weight: .bold))
                    .foregroundStyle(Theme.cyanPulse)

                TextField("Enter command (e.g. show ip route, ping, conf t)...", text: $inputCommand)
                    .font(Theme.monoText(12))
                    .textFieldStyle(.plain)
                    .onSubmit {
                        submitCommand()
                    }

                // Quick keys
                HStack(spacing: 4) {
                    Button("Enter") {
                        submitCommand()
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

                    Button("Tab") {
                        session.sendControl(0x09)
                    }
                    .buttonStyle(.bordered)
                    .font(.system(size: 11))
                    .help("Send Tab Autocomplete")
                }
            }
            .padding(10)
            .background(Theme.cardBackground)
        }
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
            Text("Open an SSH session, connect a USB serial console cable, or launch a simulated router.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            Button(action: { showNewSessionSheet = true }) {
                Label("New Terminal Session", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.cyanPulse)
            .foregroundStyle(Color.black)
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

                    VStack(alignment: .leading, spacing: 6) {
                        Text("OPTIONAL IDENTITY KEY PATH")
                            .font(Theme.monoText(10, weight: .bold))
                            .foregroundStyle(.secondary)
                        TextField("~/.ssh/id_rsa (leave empty for password)", text: $sshKeyPath)
                            .textFieldStyle(.roundedBorder)
                    }


                } else if newSessionType == 1 {
                    // USB Serial Form
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

                    VStack(alignment: .leading, spacing: 6) {
                        Text("BAUD RATE (8-N-1)")
                            .font(Theme.monoText(10, weight: .bold))
                            .foregroundStyle(.secondary)
                        Picker("Baud", selection: $selectedBaudRate) {
                            ForEach(SerialDiscovery.standardBaudRates, id: \.self) { rate in
                                Text("\(rate) bps \(rate == 9600 ? "(Cisco/Juniper Default)" : rate == 115200 ? "(Arista Default)" : "")").tag(rate)
                            }
                        }
                    }

                } else if newSessionType == 2 {
                    // Simulated CLI
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SIMULATED NETWORK EQUIPMENT")
                            .font(Theme.monoText(10, weight: .bold))
                            .foregroundStyle(.secondary)
                        Picker("Preset", selection: $selectedSimPreset) {
                            Text("Catalyst 9300 Core Switch (Cisco IOS-XE)").tag("Catalyst 9300 Core")
                            Text("Arista 7050X Spine Switch (EOS)").tag("Arista 7050X Spine")
                            Text("Juniper EX4300 Distribution (Junos)").tag("Juniper EX4300")
                        }
                        Text("Fully interactive offline CLI responding to show version, show ip int br, show cdp neigh, and ping.")
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

    // MARK: - Actions

    private func submitCommand() {
        guard !inputCommand.isEmpty else { return }
        let cmd = inputCommand
        inputCommand = ""
        activeSession?.sendCommand(cmd)
    }

    private func launchConfiguredSession() {
        showNewSessionSheet = false

        switch newSessionType {
        case 0:
            let portInt = Int(sshPort) ?? 22
            let key = sshKeyPath.isEmpty ? nil : sshKeyPath
            let pass = sshPassword.isEmpty ? nil : sshPassword
            state.terminalManager.openSSHSession(
                host: sshHost,
                port: portInt,
                username: sshUser,
                identityFile: key,
                password: pass
            )
        case 1:
            let path = selectedSerialPort.isEmpty ? "/dev/cu.usbserial-001" : selectedSerialPort
            state.terminalManager.openSerialSession(devicePath: path, baudRate: selectedBaudRate)
        case 2:
            state.terminalManager.openSimulatedSession(preset: selectedSimPreset)
        default:
            state.terminalManager.openLocalShell()
        }
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


    private func terminalOutputColor(for line: String) -> Color {
        let lower = line.lowercased()
        if lower.contains("error") || lower.contains("fail") || lower.contains("down") || lower.contains("critical") {
            return Theme.crimsonCritical.opacity(0.9)
        } else if lower.contains("up") || lower.contains("success") || lower.contains("connected") || lower.contains("[ok]") {
            return Theme.signalEmerald.opacity(0.9)
        } else if lower.contains("warning") || lower.contains("timeout") {
            return Theme.solarAmber.opacity(0.9)
        }
        return Color(red: 0.82, green: 0.86, blue: 0.90)
    }
}
