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
public enum SerialParity: String, Sendable, CaseIterable, Identifiable, Codable {
    case none = "None (8N1)"
    case odd = "Odd"
    case even = "Even"

    public var id: String { rawValue }
}

/// Serial communication flow control
public enum SerialFlowControl: String, Sendable, CaseIterable, Identifiable, Codable {
    case none = "None"
    case rtsCts = "RTS/CTS (Hardware)"
    case xonXoff = "XON/XOFF (Software)"

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

// MARK: - ANSI Color & SGR Attributes

/// Standard 24-bit RGB representation of an ANSI color
public struct ANSIColor: Sendable, Hashable, Codable {
    public let r: UInt8
    public let g: UInt8
    public let b: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    public var hex: String {
        String(format: "#%02X%02X%02X", r, g, b)
    }
}

/// SGR graphic rendition attributes for a span of text
public struct ANSIStyle: Sendable, Hashable, Codable {
    public var foreground: ANSIColor?
    public var background: ANSIColor?
    public var isBold: Bool
    public var isDim: Bool
    public var isItalic: Bool
    public var isUnderline: Bool
    public var isInverse: Bool

    public init(
        foreground: ANSIColor? = nil,
        background: ANSIColor? = nil,
        isBold: Bool = false,
        isDim: Bool = false,
        isItalic: Bool = false,
        isUnderline: Bool = false,
        isInverse: Bool = false
    ) {
        self.foreground = foreground
        self.background = background
        self.isBold = isBold
        self.isDim = isDim
        self.isItalic = isItalic
        self.isUnderline = isUnderline
        self.isInverse = isInverse
    }

    public static let `default` = ANSIStyle()
}

/// A substring formatted with distinct ANSI colors and styles
public struct ANSISpan: Identifiable, Sendable, Hashable, Codable {
    public let id: UUID
    public let text: String
    public let style: ANSIStyle

    public init(id: UUID = UUID(), text: String, style: ANSIStyle = .default) {
        self.id = id
        self.text = text
        self.style = style
    }
}

/// Single rendered line of terminal output with styled ANSI spans and timestamp
public struct TerminalLine: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let text: String
    public let spans: [ANSISpan]
    public let isCommandInput: Bool
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        text: String,
        spans: [ANSISpan] = [],
        isCommandInput: Bool = false,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.spans = spans.isEmpty ? [ANSISpan(text: text)] : spans
        self.isCommandInput = isCommandInput
        self.timestamp = timestamp
    }
}

/// Curated high-contrast terminal color themes
public enum TerminalTheme: String, CaseIterable, Identifiable, Sendable, Codable {
    case obsidian = "Obsidian Cyber"
    case solarizedDark = "Solarized Dark"
    case monokaiPro = "Monokai Pro"
    case matrix = "Classic Matrix"

    public var id: String { rawValue }

    public var backgroundColorHex: String {
        switch self {
        case .obsidian: return "#0A0E14"
        case .solarizedDark: return "#002B36"
        case .monokaiPro: return "#2D2A2E"
        case .matrix: return "#051008"
        }
    }

    public var foregroundColorHex: String {
        switch self {
        case .obsidian: return "#B3C7D8"
        case .solarizedDark: return "#839496"
        case .monokaiPro: return "#FCFCFA"
        case .matrix: return "#00FF66"
        }
    }

    public var promptColorHex: String {
        switch self {
        case .obsidian: return "#00E5FF"
        case .solarizedDark: return "#268BD2"
        case .monokaiPro: return "#FFD866"
        case .matrix: return "#33FF33"
        }
    }

    public var selectionColorHex: String {
        switch self {
        case .obsidian: return "#1F334D"
        case .solarizedDark: return "#073642"
        case .monokaiPro: return "#403E41"
        case .matrix: return "#003B14"
        }
    }
}

/// Split mode for multi-pane terminal views
public enum TerminalSplitMode: String, Sendable, CaseIterable, Identifiable, Codable {
    case single = "Single Pane"
    case vertical = "Vertical Split (Side-by-Side)"
    case horizontal = "Horizontal Split (Stacked)"

    public var id: String { rawValue }
}

/// Persistent connection profile bookmark
public struct TerminalProfile: Identifiable, Sendable, Hashable, Codable {
    public let id: UUID
    public var name: String
    public var folder: String
    public var host: String
    public var port: Int
    public var username: String
    public var identityFile: String?
    public var connectionType: String
    public var serialBaud: Int
    public var serialPath: String
    public var vendorPreset: String
    public var autoConnect: Bool
    public var badgeColorHex: String

    public init(
        id: UUID = UUID(),
        name: String,
        folder: String = "General",
        host: String = "",
        port: Int = 22,
        username: String = "admin",
        identityFile: String? = nil,
        connectionType: String = "ssh",
        serialBaud: Int = 9600,
        serialPath: String = "",
        vendorPreset: String = "Catalyst 9300 Core",
        autoConnect: Bool = false,
        badgeColorHex: String = "#00E5FF"
    ) {
        self.id = id
        self.name = name
        self.folder = folder
        self.host = host
        self.port = port
        self.username = username
        self.identityFile = identityFile
        self.connectionType = connectionType
        self.serialBaud = serialBaud
        self.serialPath = serialPath
        self.vendorPreset = vendorPreset
        self.autoConnect = autoConnect
        self.badgeColorHex = badgeColorHex
    }
}

/// Multi-line configuration script runner settings
public struct PacedPasteConfig: Sendable, Hashable, Codable {
    public var lineDelayMs: Int
    public var stopOnError: Bool
    public var errorPatterns: [String]

    public init(lineDelayMs: Int = 50, stopOnError: Bool = true, errorPatterns: [String] = ["%", "Error:", "syntax error", "Invalid input"]) {
        self.lineDelayMs = lineDelayMs
        self.stopOnError = stopOnError
        self.errorPatterns = errorPatterns
    }
}

/// One-click quick CLI command macro for rapid network operations
public struct CommandMacro: Identifiable, Sendable, Hashable, Codable {
    public let id: UUID
    public var name: String
    public var command: String
    public var category: String

    public init(id: UUID = UUID(), name: String, command: String, category: String = "General") {
        self.id = id
        self.name = name
        self.command = command
        self.category = category
    }

    /// Expands parameterized variables like {ip}, {vlan}, {interface}
    public func expandCommand(with params: [String: String]) -> String {
        var result = command
        for (key, val) in params {
            result = result.replacingOccurrences(of: "{\(key)}", with: val)
        }
        return result
    }

    public static let defaultMacros: [CommandMacro] = [
        CommandMacro(name: "Interfaces", command: "show ip int br", category: "L3"),
        CommandMacro(name: "Routes", command: "show ip route", category: "L3"),
        CommandMacro(name: "BGP Summary", command: "show ip bgp summary", category: "Routing"),
        CommandMacro(name: "CDP Neig", command: "show cdp neighbors", category: "Discovery"),
        CommandMacro(name: "LLDP Neig", command: "show lldp neighbors", category: "Discovery"),
        CommandMacro(name: "Run Config", command: "show running-config", category: "Config"),
        CommandMacro(name: "MAC Table", command: "show mac address-table", category: "L2"),
        CommandMacro(name: "Version", command: "show version", category: "System"),
        CommandMacro(name: "Ping Quad9", command: "ping 9.9.9.9", category: "Diagnostics"),
        CommandMacro(name: "Save", command: "write memory", category: "Config")
    ]
}

