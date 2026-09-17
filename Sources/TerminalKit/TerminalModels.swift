import Foundation
import NetworkCore

/// Authentication method for SSH session
public enum SSHAuthMethod: Sendable, Hashable, Codable {
    case password(String)
    case keyFile(path: String)
    case keychain(credentialId: String)
    case interactive
}

/// Configuration for connecting through an SSH Jump Host (Bastion/ProxyJump)
public struct SSHJumpConfig: Sendable, Hashable, Codable {
    public var host: String
    public var port: Int
    public var username: String
    public var identityFile: String?

    public init(host: String, port: Int = 22, username: String = "admin", identityFile: String? = nil) {
        self.host = host
        self.port = port
        self.username = username
        self.identityFile = identityFile
    }

    public var proxyJumpArgument: String {
        "\(username)@\(host):\(port)"
    }
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
    public var jumpHost: SSHJumpConfig?
    public var enableLegacyCiphers: Bool

    public init(
        id: UUID = UUID(),
        name: String = "",
        host: String,
        port: Int = 22,
        username: String,
        authMethod: SSHAuthMethod = .interactive,
        terminalType: String = "xterm-256color",
        logSession: Bool = false,
        jumpHost: SSHJumpConfig? = nil,
        enableLegacyCiphers: Bool = false
    ) {
        self.id = id
        self.name = name.isEmpty ? "\(username)@\(host)" : name
        self.host = host
        self.port = port
        self.username = username
        self.authMethod = authMethod
        self.terminalType = terminalType
        self.logSession = logSession
        self.jumpHost = jumpHost
        self.enableLegacyCiphers = enableLegacyCiphers
    }
}

/// Connection mode for a network engineering terminal session
public enum TerminalConnectionType: Sendable, Hashable {
    case ssh(
        host: String,
        port: Int = 22,
        username: String,
        identityFile: String? = nil,
        password: String? = nil,
        jumpHost: SSHJumpConfig? = nil,
        enableLegacyCiphers: Bool = false
    )
    case serial(devicePath: String, baudRate: Int = 9600, dataBits: Int = 8, parity: SerialParity = .none, stopBits: Int = 1)
    case telnet(host: String, port: Int = 23)
    case localShell
    case simulation(presetName: String)

    public var title: String {
        switch self {
        case .ssh(let host, _, let user, _, _, _, _):
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
    case synthwave = "Synthwave Neon"
    case solarizedDark = "Solarized Dark"
    case monokaiPro = "Monokai Pro"
    case matrix = "Classic Matrix"
    case phosphorGreen = "Phosphor Green"
    case highContrast = "High Contrast"
    case cleanLight = "Clean Light"

    public var id: String { rawValue }

    public var backgroundColorHex: String {
        switch self {
        case .obsidian: return "#0A0E14"
        case .synthwave: return "#1A102F"
        case .solarizedDark: return "#002B36"
        case .monokaiPro: return "#2D2A2E"
        case .matrix: return "#051008"
        case .phosphorGreen: return "#001100"
        case .highContrast: return "#000000"
        case .cleanLight: return "#F8F9FA"
        }
    }

    public var foregroundColorHex: String {
        switch self {
        case .obsidian: return "#B3C7D8"
        case .synthwave: return "#F92AAD"
        case .solarizedDark: return "#839496"
        case .monokaiPro: return "#FCFCFA"
        case .matrix: return "#00FF66"
        case .phosphorGreen: return "#33FF33"
        case .highContrast: return "#FFFFFF"
        case .cleanLight: return "#1E1E1E"
        }
    }

    public var promptColorHex: String {
        switch self {
        case .obsidian: return "#00E5FF"
        case .synthwave: return "#05D9E8"
        case .solarizedDark: return "#268BD2"
        case .monokaiPro: return "#FFD866"
        case .matrix: return "#33FF33"
        case .phosphorGreen: return "#66FF66"
        case .highContrast: return "#FFFF00"
        case .cleanLight: return "#0066CC"
        }
    }

    public var selectionColorHex: String {
        switch self {
        case .obsidian: return "#1F334D"
        case .synthwave: return "#3B2164"
        case .solarizedDark: return "#073642"
        case .monokaiPro: return "#403E41"
        case .matrix: return "#003B14"
        case .phosphorGreen: return "#003300"
        case .highContrast: return "#333333"
        case .cleanLight: return "#B4D5FE"
        }
    }
}

/// Terminal cursor display styles
public enum TerminalCursorStyle: String, CaseIterable, Identifiable, Sendable, Codable {
    case block = "Block (▋)"
    case beam = "Beam (❘)"
    case underline = "Underline (_)"

    public var id: String { rawValue }

    public var glyph: String {
        switch self {
        case .block: return "▋"
        case .beam: return "❘"
        case .underline: return "_"
        }
    }

    public var cursorGlyph: String { glyph }
}

/// Curated developer monospace font families
public enum TerminalFontFamily: String, CaseIterable, Identifiable, Sendable, Codable {
    case system = "SF Mono (System)"
    case menlo = "Menlo"
    case monaco = "Monaco"
    case courierNew = "Courier New"
    case courier = "Courier"
    case andaleMono = "Andale Mono"
    case ptMono = "PT Mono"
    case jetBrainsMono = "JetBrains Mono"
    case firaCode = "Fira Code"
    case sourceCodePro = "Source Code Pro"

    public var id: String { rawValue }

    public var fontName: String {
        switch self {
        case .system: return "SF Mono"
        case .menlo: return "Menlo"
        case .monaco: return "Monaco"
        case .courierNew: return "Courier New"
        case .courier: return "Courier"
        case .andaleMono: return "Andale Mono"
        case .ptMono: return "PT Mono"
        case .jetBrainsMono: return "JetBrains Mono"
        case .firaCode: return "Fira Code"
        case .sourceCodePro: return "Source Code Pro"
        }
    }
}


/// Split mode for multi-pane terminal views
public enum TerminalSplitMode: String, Sendable, CaseIterable, Identifiable, Codable {
    case single = "Single Pane"
    case vertical = "Vertical Split (Side-by-Side)"
    case horizontal = "Horizontal Split (Stacked)"
    case quadGrid = "2x2 Quad Grid (4 Panes)"

    public var id: String { rawValue }
}

/// Hierarchical folder for organizing saved connection sessions (MobaXterm / Royal TS style)
public struct SessionFolder: Identifiable, Sendable, Hashable, Codable {
    public let id: UUID
    public var name: String
    public var parentId: UUID?
    public var isExpanded: Bool
    public var iconColorHex: String?

    public init(
        id: UUID = UUID(),
        name: String,
        parentId: UUID? = nil,
        isExpanded: Bool = true,
        iconColorHex: String? = "#F59E0B"
    ) {
        self.id = id
        self.name = name
        self.parentId = parentId
        self.isExpanded = isExpanded
        self.iconColorHex = iconColorHex
    }
}

/// Persistent connection profile bookmark
public struct TerminalProfile: Identifiable, Sendable, Hashable, Codable {
    public let id: UUID
    public var name: String
    public var folder: String
    public var folderId: UUID?
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
    public var jumpHost: String?
    public var jumpUser: String?
    public var jumpPort: Int?
    public var enableLegacyCiphers: Bool
    public var tags: [String]
    public var notes: String
    public var lastConnected: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        folder: String = "General",
        folderId: UUID? = nil,
        host: String = "",
        port: Int = 22,
        username: String = "admin",
        identityFile: String? = nil,
        connectionType: String = "ssh",
        serialBaud: Int = 9600,
        serialPath: String = "",
        vendorPreset: String = "Catalyst 9300 Core",
        autoConnect: Bool = false,
        badgeColorHex: String = "#00E5FF",
        jumpHost: String? = nil,
        jumpUser: String? = nil,
        jumpPort: Int? = 22,
        enableLegacyCiphers: Bool = false,
        tags: [String] = [],
        notes: String = "",
        lastConnected: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.folder = folder
        self.folderId = folderId
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
        self.jumpHost = jumpHost
        self.jumpUser = jumpUser
        self.jumpPort = jumpPort
        self.enableLegacyCiphers = enableLegacyCiphers
        self.tags = tags
        self.notes = notes
        self.lastConnected = lastConnected
    }

    enum CodingKeys: String, CodingKey {
        case id, name, folder, folderId, host, port, username, identityFile, connectionType
        case serialBaud, serialPath, vendorPreset, autoConnect, badgeColorHex
        case jumpHost, jumpUser, jumpPort, enableLegacyCiphers, tags, notes, lastConnected
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Untitled Session"
        self.folder = try container.decodeIfPresent(String.self, forKey: .folder) ?? "General"
        self.folderId = try container.decodeIfPresent(UUID.self, forKey: .folderId)
        self.host = try container.decodeIfPresent(String.self, forKey: .host) ?? ""
        self.port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 22
        self.username = try container.decodeIfPresent(String.self, forKey: .username) ?? "admin"
        self.identityFile = try container.decodeIfPresent(String.self, forKey: .identityFile)
        self.connectionType = try container.decodeIfPresent(String.self, forKey: .connectionType) ?? "ssh"
        self.serialBaud = try container.decodeIfPresent(Int.self, forKey: .serialBaud) ?? 9600
        self.serialPath = try container.decodeIfPresent(String.self, forKey: .serialPath) ?? ""
        self.vendorPreset = try container.decodeIfPresent(String.self, forKey: .vendorPreset) ?? ""
        self.autoConnect = try container.decodeIfPresent(Bool.self, forKey: .autoConnect) ?? false
        self.badgeColorHex = try container.decodeIfPresent(String.self, forKey: .badgeColorHex) ?? "#00E5FF"
        self.jumpHost = try container.decodeIfPresent(String.self, forKey: .jumpHost)
        self.jumpUser = try container.decodeIfPresent(String.self, forKey: .jumpUser)
        self.jumpPort = try container.decodeIfPresent(Int.self, forKey: .jumpPort)
        self.enableLegacyCiphers = try container.decodeIfPresent(Bool.self, forKey: .enableLegacyCiphers) ?? false
        self.tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        self.notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        self.lastConnected = try container.decodeIfPresent(Date.self, forKey: .lastConnected)
    }
}

/// Information describing a local SSH public/private keypair (MobaKeyGen)
public struct SSHKeyInfo: Identifiable, Sendable, Hashable, Codable {
    public let id: UUID
    public var name: String
    public var privateKeyPath: String
    public var publicKeyPath: String
    public var keyType: String // "ed25519", "rsa", "ecdsa"
    public var fingerprint: String
    public var comment: String
    public var publicKeyString: String

    public init(
        id: UUID = UUID(),
        name: String,
        privateKeyPath: String,
        publicKeyPath: String,
        keyType: String,
        fingerprint: String = "",
        comment: String = "",
        publicKeyString: String = ""
    ) {
        self.id = id
        self.name = name
        self.privateKeyPath = privateKeyPath
        self.publicKeyPath = publicKeyPath
        self.keyType = keyType
        self.fingerprint = fingerprint
        self.comment = comment
        self.publicKeyString = publicKeyString
    }
}

/// Type of SSH tunnel (MobaSSHTunnel)
public enum SSHTunnelType: String, Sendable, CaseIterable, Identifiable, Codable {
    case localForward = "Local Port Forward (-L)"
    case remoteForward = "Remote Port Forward (-R)"
    case dynamicSOCKS5 = "Dynamic SOCKS5 Proxy (-D)"

    public var id: String { rawValue }
    public var flag: String {
        switch self {
        case .localForward: return "-L"
        case .remoteForward: return "-R"
        case .dynamicSOCKS5: return "-D"
        }
    }
}

/// Persistent configuration for an SSH Port Forwarding Tunnel (MobaSSHTunnel)
public struct SSHTunnelConfig: Identifiable, Sendable, Hashable, Codable {
    public let id: UUID
    public var name: String
    public var tunnelType: SSHTunnelType
    public var localPort: Int
    public var destinationHost: String
    public var destinationPort: Int
    public var sshHost: String
    public var sshPort: Int
    public var sshUsername: String
    public var sshIdentityFile: String?
    public var isActive: Bool
    public var lastError: String?

    public init(
        id: UUID = UUID(),
        name: String = "",
        tunnelType: SSHTunnelType = .localForward,
        localPort: Int = 8080,
        destinationHost: String = "localhost",
        destinationPort: Int = 80,
        sshHost: String = "",
        sshPort: Int = 22,
        sshUsername: String = "admin",
        sshIdentityFile: String? = nil,
        isActive: Bool = false,
        lastError: String? = nil
    ) {
        self.id = id
        self.name = name.isEmpty ? "\(tunnelType.flag) \(localPort):\(destinationHost):\(destinationPort)" : name
        self.tunnelType = tunnelType
        self.localPort = localPort
        self.destinationHost = destinationHost
        self.destinationPort = destinationPort
        self.sshHost = sshHost
        self.sshPort = sshPort
        self.sshUsername = sshUsername
        self.sshIdentityFile = sshIdentityFile
        self.isActive = isActive
        self.lastError = lastError
    }

    public var specString: String {
        switch tunnelType {
        case .localForward, .remoteForward:
            return "\(localPort):\(destinationHost):\(destinationPort)"
        case .dynamicSOCKS5:
            return "\(localPort)"
        }
    }
}

/// Configuration for live terminal keyword and syntax highlighting (MobaXterm Syntax Coloring)
public struct TerminalSyntaxHighlightConfig: Sendable, Hashable, Codable {
    public var isEnabled: Bool
    public var highlightIPs: Bool
    public var highlightIPv6: Bool
    public var highlightCIDR: Bool
    public var highlightMACs: Bool
    public var highlightInterfaces: Bool
    public var highlightErrors: Bool
    public var highlightSuccess: Bool

    public init(
        isEnabled: Bool = true,
        highlightIPs: Bool = true,
        highlightIPv6: Bool = true,
        highlightCIDR: Bool = true,
        highlightMACs: Bool = true,
        highlightInterfaces: Bool = true,
        highlightErrors: Bool = true,
        highlightSuccess: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.highlightIPs = highlightIPs
        self.highlightIPv6 = highlightIPv6
        self.highlightCIDR = highlightCIDR
        self.highlightMACs = highlightMACs
        self.highlightInterfaces = highlightInterfaces
        self.highlightErrors = highlightErrors
        self.highlightSuccess = highlightSuccess
    }
}

// MARK: - Remote SFTP / SCP File Explorer Models

/// Represents a remote or local file or folder item for visual dual-pane file management
public struct RemoteFileItem: Identifiable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let path: String
    public let isDirectory: Bool
    public let size: Int64
    public let permissions: String
    public let modifiedDate: String
    public let isSymlink: Bool

    public init(
        name: String,
        path: String,
        isDirectory: Bool,
        size: Int64 = 0,
        permissions: String = "",
        modifiedDate: String = "",
        isSymlink: Bool = false
    ) {
        self.id = path
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.size = size
        self.permissions = permissions
        self.modifiedDate = modifiedDate
        self.isSymlink = isSymlink
    }

    public var iconName: String {
        if isDirectory { return "folder.fill" }
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "conf", "cfg", "config", "ini", "yaml", "yml", "json", "rsc":
            return "gearshape.fill"
        case "log", "txt":
            return "doc.text.fill"
        case "sh", "py", "bash", "zsh":
            return "terminal.fill"
        case "tar", "gz", "zip", "tgz":
            return "archivebox.fill"
        case "bin", "iso", "img":
            return "memorychip.fill"
        case "key", "pem", "pub", "crt":
            return "key.fill"
        default:
            return "doc.fill"
        }
    }

    public var formattedSize: String {
        if isDirectory { return "--" }
        if size < 1024 { return "\(size) B" }
        if size < 1024 * 1024 { return String(format: "%.1f KB", Double(size) / 1024.0) }
        return String(format: "%.1f MB", Double(size) / (1024.0 * 1024.0))
    }
}

// MARK: - Asciinema v2 Recording Models

/// Header object for standard Asciinema v2 session recording files (.cast)
public struct AsciinemaCastHeader: Codable, Sendable {
    public let version: Int
    public let width: Int
    public let height: Int
    public let timestamp: Int
    public let title: String
    public let env: [String: String]

    public init(
        width: Int = 80,
        height: Int = 24,
        timestamp: Int = Int(Date().timeIntervalSince1970),
        title: String = "NexWave Terminal Session"
    ) {
        self.version = 2
        self.width = width
        self.height = height
        self.timestamp = timestamp
        self.title = title
        self.env = ["TERM": "xterm-256color", "SHELL": "/bin/zsh"]
    }
}

// MARK: - SSH Known Hosts Models

/// Parsed entry from user's ~/.ssh/known_hosts file
public struct KnownHostEntry: Identifiable, Sendable, Hashable {
    public let id: String
    public let host: String
    public let keyType: String
    public let keySnippet: String
    public let rawLine: String
    public let lineNumber: Int
    public let isHashed: Bool

    public init(
        host: String,
        keyType: String,
        keySnippet: String,
        rawLine: String,
        lineNumber: Int,
        isHashed: Bool = false
    ) {
        self.id = "\(lineNumber)_\(host)"
        self.host = host
        self.keyType = keyType
        self.keySnippet = keySnippet
        self.rawLine = rawLine
        self.lineNumber = lineNumber
        self.isHashed = isHashed
    }
}

// MARK: - Hardware Serial Modem Status Signals

/// Status of hardware serial modem control lines (RS-232 / UART)
public struct SerialModemStatus: Sendable, Hashable {
    public var dtr: Bool
    public var rts: Bool
    public var cts: Bool
    public var dsr: Bool
    public var dcd: Bool
    public var ri: Bool

    public init(
        dtr: Bool = false,
        rts: Bool = false,
        cts: Bool = false,
        dsr: Bool = false,
        dcd: Bool = false,
        ri: Bool = false
    ) {
        self.dtr = dtr
        self.rts = rts
        self.cts = cts
        self.dsr = dsr
        self.dcd = dcd
        self.ri = ri
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

