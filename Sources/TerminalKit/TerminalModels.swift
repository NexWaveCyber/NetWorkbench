import Foundation
import NetworkCore

/// Authentication method for SSH session
public enum SSHAuthMethod: Sendable, Hashable, Codable {
    case password(String)
    case keyFile(path: String)
    case keychain(credentialId: String)
    case interactive
}

/// Profile configuration for connecting to remote network devices via SSH
public struct SSHProfile: Identifiable, Sendable, Hashable, Codable {
    public let id: UUID
    public var name: String
    public var host: String
    public var port: Int
    public var username: String
    public var authMethod: SSHAuthMethod
    public var terminalType: String
    public var logSession: Bool

    public init(
        id: UUID = UUID(),
        name: String = "",
        host: String,
        port: Int = 22,
        username: String,
        authMethod: SSHAuthMethod = .interactive,
        terminalType: String = "xterm-256color",
        logSession: Bool = false
    ) {
        self.id = id
        self.name = name.isEmpty ? "\(username)@\(host)" : name
        self.host = host
        self.port = port
        self.username = username
        self.authMethod = authMethod
        self.terminalType = terminalType
        self.logSession = logSession
    }
}

/// Connection mode for a network engineering terminal session
public enum TerminalConnectionType: Sendable, Hashable {
    case ssh(host: String, port: Int = 22, username: String, identityFile: String? = nil, password: String? = nil)
    case serial(devicePath: String, baudRate: Int = 9600, dataBits: Int = 8, parity: SerialParity = .none, stopBits: Int = 1)
    case telnet(host: String, port: Int = 23)
    case localShell
    case simulation(presetName: String)

    public var title: String {
        switch self {
        case .ssh(let host, _, let user, _, _):
            return "\(user)@\(host)"
        case .serial(let path, let baud, _, _, _):
            let shortName = path.components(separatedBy: "/").last ?? path
            return "\(shortName) (\(baud))"
        case .telnet(let host, let port):
            return "telnet:\(host):\(port)"
        case .localShell:
            return "Local Shell"
        case .simulation(let preset):
            return "Sim: \(preset)"
        }
    }

    public var iconName: String {
        switch self {
        case .ssh: return "lock.shield.fill"
        case .serial: return "cable.connector"
        case .telnet: return "network"
        case .localShell: return "terminal.fill"
        case .simulation: return "cpu"
        }
    }
}


/// Serial communication parity options
public enum SerialParity: String, Sendable, CaseIterable, Identifiable {
    case none = "None (8N1)"
    case odd = "Odd"
    case even = "Even"

    public var id: String { rawValue }
}

/// Metadata describing a discovered hardware serial / console device
public struct SerialPortInfo: Identifiable, Sendable, Hashable {
    public let id: String
    public let devicePath: String
    public let friendlyName: String
    public let isUSB: Bool

    public init(devicePath: String, friendlyName: String, isUSB: Bool) {
        self.id = devicePath
        self.devicePath = devicePath
        self.friendlyName = friendlyName
        self.isUSB = isUSB
    }
}

/// Lifecycle status of an active or background terminal session
public enum SessionStatus: Sendable, Equatable {
    case disconnected
    case connecting(String)
    case connected
    case terminated(exitCode: Int32)
    case error(String)

    public var rawValue: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting(let msg): return msg
        case .connected: return "Connected"
        case .terminated(let code): return "Terminated (Exit \(code))"
        case .error(let err): return "Error: \(err)"
        }
    }

    public var badgeColorHex: String {
        switch self {
        case .connected: return "#00E5FF" // Cyan
        case .connecting: return "#FFAA00" // Amber
        case .disconnected, .terminated: return "#8E8E93" // Gray
        case .error: return "#FF453A" // Red
        }
    }
}

/// Single rendered line of terminal output with timestamp and prompt indicator
public struct TerminalLine: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let text: String
    public let isCommandInput: Bool
    public let timestamp: Date

    public init(id: UUID = UUID(), text: String, isCommandInput: Bool = false, timestamp: Date = Date()) {
        self.id = id
        self.text = text
        self.isCommandInput = isCommandInput
        self.timestamp = timestamp
    }
}
