import Foundation
import Observation
import NetworkCore

/// Coordinates multi-session tabs, split-screen layouts, broadcast dispatch, profile vault, and serial hardware discovery
@Observable
public final class TerminalManager: @unchecked Sendable {
    public var sessions: [TerminalSession] = []
    public var activeSessionId: UUID?
    public var secondarySessionId: UUID?
    public var pane3SessionId: UUID?
    public var pane4SessionId: UUID?
    public var splitMode: TerminalSplitMode = .single
    public var isBroadcastEnabled: Bool = false
    public var isSidebarExpanded: Bool = true
    public var isSyntaxHighlightingEnabled: Bool = true
    public var availableSerialPorts: [SerialPortInfo] = []
    public var savedProfiles: [TerminalProfile] = []
    public var macros: [CommandMacro] = []

    public let keyStudio = SSHKeyStudio.shared
    public let tunnelManager = SSHTunnelManager.shared

    private let profilesStorageKey = "com.nexwave.terminal.saved_profiles"
    private let macrosStorageKey = "com.nexwave.terminal.custom_macros"

    public init() {
        refreshSerialPorts()
        loadProfiles()
        loadMacros()

        // Pre-seed with a high-fidelity Cisco simulator session
        let defaultSim = openSimulatedSession(preset: "Catalyst 9300 Core")
        self.activeSessionId = defaultSim.id
    }

    public var activeSession: TerminalSession? {
        guard let id = activeSessionId else { return sessions.first }
        return sessions.first(where: { $0.id == id })
    }

    public var secondarySession: TerminalSession? {
        guard let id = secondarySessionId else { return sessions.dropFirst().first }
        return sessions.first(where: { $0.id == id })
    }

    public var pane3Session: TerminalSession? {
        guard let id = pane3SessionId else { return sessions.dropFirst(2).first }
        return sessions.first(where: { $0.id == id })
    }

    public var pane4Session: TerminalSession? {
        guard let id = pane4SessionId else { return sessions.dropFirst(3).first }
        return sessions.first(where: { $0.id == id })
    }

    /// Refresh hardware serial ports
    public func refreshSerialPorts() {
        self.availableSerialPorts = SerialDiscovery.shared.discoverPorts()
    }

    // MARK: - Session Creation

    /// Open a new SSH session tab
    @discardableResult
    public func openSSHSession(
        host: String,
        port: Int = 22,
        username: String = "admin",
        identityFile: String? = nil,
        password: String? = nil,
        jumpHost: SSHJumpConfig? = nil,
        enableLegacyCiphers: Bool = false,
        autoConnect: Bool = true
    ) -> TerminalSession {
        if let existing = sessions.first(where: {
            if case .ssh(let h, let p, let u, _, _, _, _) = $0.connectionType {
                return h == host && p == port && u == username
            }
            return false
        }) {
            activeSessionId = existing.id
            if autoConnect && existing.status == .disconnected {
                existing.connect()
            }
            return existing
        }

        let session = TerminalSession(
            title: "\(username)@\(host)",
            connectionType: .ssh(
                host: host,
                port: port,
                username: username,
                identityFile: identityFile,
                password: password,
                jumpHost: jumpHost,
                enableLegacyCiphers: enableLegacyCiphers
            )
        )
        sessions.append(session)
        activeSessionId = session.id

        if autoConnect {
            session.connect()
        }
        return session
    }

    /// Open a hardware USB Serial Console session tab
    @discardableResult
    public func openSerialSession(
        devicePath: String,
        baudRate: Int = 9600,
        dataBits: Int = 8,
        parity: SerialParity = .none,
        stopBits: Int = 1,
        flowControl: SerialFlowControl = .none,
        autoConnect: Bool = true
    ) -> TerminalSession {
        let shortName = devicePath.components(separatedBy: "/").last ?? devicePath
        let session = TerminalSession(
            title: "\(shortName) (\(baudRate))",
            connectionType: .serial(devicePath: devicePath, baudRate: baudRate, dataBits: dataBits, parity: parity, stopBits: stopBits)
        )
        sessions.append(session)
        activeSessionId = session.id

        if autoConnect {
            session.connect()
        }
        return session
    }

    /// Open a high-fidelity simulated CLI session
    @discardableResult
    public func openSimulatedSession(preset: String = "Catalyst 9300 Core") -> TerminalSession {
        let session = TerminalSession(
            title: preset,
            connectionType: .simulation(presetName: preset)
        )
        sessions.append(session)
        activeSessionId = session.id
        session.connect()
        return session
    }

    /// Open a local macOS shell session
    @discardableResult
    public func openLocalShell() -> TerminalSession {
        let session = TerminalSession(
            title: "Local Shell (zsh)",
            connectionType: .localShell
        )
        sessions.append(session)
        activeSessionId = session.id
        session.connect()
        return session
    }

    /// Launch a saved profile from the vault
    @discardableResult
    public func launchProfile(_ profile: TerminalProfile) -> TerminalSession {
        switch profile.connectionType.lowercased() {
        case "serial":
            return openSerialSession(devicePath: profile.serialPath, baudRate: profile.serialBaud)
        case "simulation":
            return openSimulatedSession(preset: profile.vendorPreset)
        case "localshell", "shell":
            return openLocalShell()
        default:
            let jump: SSHJumpConfig?
            if let jh = profile.jumpHost, !jh.isEmpty {
                jump = SSHJumpConfig(host: jh, port: profile.jumpPort ?? 22, username: profile.jumpUser ?? "admin")
            } else {
                jump = nil
            }
            return openSSHSession(
                host: profile.host,
                port: profile.port,
                username: profile.username,
                identityFile: profile.identityFile,
                jumpHost: jump,
                enableLegacyCiphers: profile.enableLegacyCiphers
            )
        }
    }

    /// Close a session tab and disconnect process
    public func closeSession(id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        let session = sessions[index]
        session.disconnect()
        sessions.remove(at: index)

        if activeSessionId == id {
            activeSessionId = sessions.last?.id
        }
        if secondarySessionId == id {
            secondarySessionId = nil
        }
    }

    // MARK: - Broadcast Dispatch

    /// Broadcasts command text across all connected terminal sessions
    public func broadcastCommand(_ command: String) {
        for session in sessions where session.status == .connected {
            session.sendCommand(command)
        }
    }

    /// Broadcasts hardware serial break across all connected sessions
    public func broadcastBreak() {
        for session in sessions where session.status == .connected {
            session.sendBreak()
        }
    }

    // MARK: - Profile Vault Persistence

    public func saveProfile(_ profile: TerminalProfile) {
        if let idx = savedProfiles.firstIndex(where: { $0.id == profile.id }) {
            savedProfiles[idx] = profile
        } else {
            savedProfiles.append(profile)
        }
        persistProfiles()
    }

    public func deleteProfile(id: UUID) {
        savedProfiles.removeAll { $0.id == id }
        persistProfiles()
    }

    private func loadProfiles() {
        if let data = UserDefaults.standard.data(forKey: profilesStorageKey),
           let decoded = try? JSONDecoder().decode([TerminalProfile].self, from: data) {
            self.savedProfiles = decoded
        } else {
            // Enterprise default templates
            self.savedProfiles = [
                TerminalProfile(
                    name: "Core Spine 01 (Cisco)",
                    folder: "Data Center",
                    host: "10.100.1.1",
                    port: 22,
                    username: "admin",
                    connectionType: "ssh",
                    badgeColorHex: "#00E5FF"
                ),
                TerminalProfile(
                    name: "Arista Spine Peer 02",
                    folder: "Data Center",
                    host: "10.100.1.2",
                    port: 22,
                    username: "admin",
                    connectionType: "simulation",
                    vendorPreset: "Arista 7050X Spine",
                    badgeColorHex: "#3B82F6"
                ),
                TerminalProfile(
                    name: "Campus Distro EX4300",
                    folder: "Campus Access",
                    host: "10.200.1.1",
                    port: 22,
                    username: "admin",
                    connectionType: "simulation",
                    vendorPreset: "Juniper EX4300",
                    badgeColorHex: "#8B5CF6"
                ),
                TerminalProfile(
                    name: "Edge Switch USB Console",
                    folder: "Lab Rack",
                    host: "",
                    connectionType: "serial",
                    serialBaud: 9600,
                    serialPath: "/dev/cu.usbserial-001",
                    badgeColorHex: "#F59E0B"
                )
            ]
            persistProfiles()
        }
    }

    private func persistProfiles() {
        if let data = try? JSONEncoder().encode(savedProfiles) {
            UserDefaults.standard.set(data, forKey: profilesStorageKey)
        }
    }

    // MARK: - Macro Management

    public func saveMacro(_ macro: CommandMacro) {
        if let idx = macros.firstIndex(where: { $0.id == macro.id }) {
            macros[idx] = macro
        } else {
            macros.append(macro)
        }
        persistMacros()
    }

    public func deleteMacro(id: UUID) {
        macros.removeAll { $0.id == id }
        persistMacros()
    }

    private func loadMacros() {
        if let data = UserDefaults.standard.data(forKey: macrosStorageKey),
           let decoded = try? JSONDecoder().decode([CommandMacro].self, from: data) {
            self.macros = decoded
        } else {
            self.macros = CommandMacro.defaultMacros
            persistMacros()
        }
    }

    private func persistMacros() {
        if let data = try? JSONEncoder().encode(macros) {
            UserDefaults.standard.set(data, forKey: macrosStorageKey)
        }
    }
}
