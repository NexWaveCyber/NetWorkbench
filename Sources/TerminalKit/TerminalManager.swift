import Foundation
import Observation
import NetworkCore

/// Coordinates multi-session tabs, serial port discovery, and terminal routing
@Observable
public final class TerminalManager: @unchecked Sendable {
    public var sessions: [TerminalSession] = []
    public var activeSessionId: UUID?
    public var availableSerialPorts: [SerialPortInfo] = []

    public init() {
        refreshSerialPorts()
        // Pre-seed with a high-fidelity Cisco simulator session
        let defaultSim = openSimulatedSession(preset: "Catalyst 9300 Core")
        self.activeSessionId = defaultSim.id
    }

    public var activeSession: TerminalSession? {
        guard let id = activeSessionId else { return sessions.first }
        return sessions.first(where: { $0.id == id })
    }

    /// Refresh hardware serial ports
    public func refreshSerialPorts() {
        self.availableSerialPorts = SerialDiscovery.shared.discoverPorts()
    }

    /// Open a new SSH session tab
    @discardableResult
    public func openSSHSession(
        host: String,
        port: Int = 22,
        username: String = "admin",
        identityFile: String? = nil,
        autoConnect: Bool = true
    ) -> TerminalSession {
        // Check if an identical session already exists
        if let existing = sessions.first(where: {
            if case .ssh(let h, let p, let u, _) = $0.connectionType {
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
            connectionType: .ssh(host: host, port: port, username: username, identityFile: identityFile)
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
        autoConnect: Bool = true
    ) -> TerminalSession {
        let shortName = devicePath.components(separatedBy: "/").last ?? devicePath
        let session = TerminalSession(
            title: "\(shortName) (\(baudRate))",
            connectionType: .serial(devicePath: devicePath, baudRate: baudRate)
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

    /// Close a session tab and disconnect process
    public func closeSession(id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        let session = sessions[index]
        session.disconnect()
        sessions.remove(at: index)

        if activeSessionId == id {
            activeSessionId = sessions.last?.id
        }
    }
}
