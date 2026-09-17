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
    public var folders: [SessionFolder] = []
    public var savedProfiles: [TerminalProfile] = []
    public var macros: [CommandMacro] = []

    public let keyStudio = SSHKeyStudio.shared
    public let tunnelManager = SSHTunnelManager.shared

    private let foldersStorageKey = "com.nexwave.terminal.session_folders_v1"
    private let profilesStorageKey = "com.nexwave.terminal.saved_profiles"
    private let macrosStorageKey = "com.nexwave.terminal.custom_macros"

    public init() {
        refreshSerialPorts()
        loadFolders()
        loadProfiles()
        loadMacros()
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
        // If an existing session to the same host/port/user exists, update its credentials and reconnect if requested
        if let existing = sessions.first(where: {
            if case .ssh(let h, let p, let u, _, _, _, _) = $0.connectionType {
                return h == host && p == port && u == username
            }
            return false
        }) {
            existing.title = "\(username)@\(host)"
            existing.connectionType = .ssh(
                host: host,
                port: port,
                username: username,
                identityFile: identityFile,
                password: password,
                jumpHost: jumpHost,
                enableLegacyCiphers: enableLegacyCiphers
            )
            activeSessionId = existing.id
            if autoConnect {
                existing.disconnect()
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

    /// Open an interactive Telnet / Raw TCP network terminal session
    @discardableResult
    public func openTelnetSession(host: String, port: Int = 23, autoConnect: Bool = true) -> TerminalSession {
        let session = TerminalSession(
            title: "telnet:\(host):\(port)",
            connectionType: .telnet(host: host, port: port)
        )
        sessions.append(session)
        activeSessionId = session.id
        if autoConnect {
            session.connect()
        }
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
        // Record last connected timestamp
        if let idx = savedProfiles.firstIndex(where: { $0.id == profile.id }) {
            savedProfiles[idx].lastConnected = Date()
            persistProfiles()
        }

        switch profile.connectionType.lowercased() {
        case "serial":
            let path = profile.serialPath.isEmpty ? (availableSerialPorts.first?.devicePath ?? "/dev/cu.usbserial-001") : profile.serialPath
            return openSerialSession(devicePath: path, baudRate: profile.serialBaud)
        case "telnet":
            return openTelnetSession(host: profile.host, port: profile.port)
        case "simulation":
            return openSimulatedSession(preset: profile.vendorPreset.isEmpty ? "Catalyst 9300 Core" : profile.vendorPreset)
        case "localshell", "shell", "local":
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
        if pane3SessionId == id {
            pane3SessionId = nil
        }
        if pane4SessionId == id {
            pane4SessionId = nil
        }
    }

    // MARK: - Broadcast Dispatch

    /// Broadcasts command text across all connected terminal sessions
    public func broadcastCommand(_ command: String) {
        for session in sessions where session.status == .connected {
            session.sendCommand(command)
        }
    }

    /// Broadcasts raw interactive text across all connected terminal sessions
    public func broadcastText(_ text: String) {
        for session in sessions where session.status == .connected {
            session.sendRawString(text)
        }
    }

    /// Broadcasts hardware serial break across all connected sessions
    public func broadcastBreak() {
        for session in sessions where session.status == .connected {
            session.sendBreak()
        }
    }

    // MARK: - Profile Vault & Folder Hierarchy Persistence

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

    public func duplicateProfile(id: UUID) -> TerminalProfile? {
        guard let original = savedProfiles.first(where: { $0.id == id }) else { return nil }
        let copy = TerminalProfile(
            name: "\(original.name) (Copy)",
            folder: original.folder,
            folderId: original.folderId,
            host: original.host,
            port: original.port,
            username: original.username,
            identityFile: original.identityFile,
            connectionType: original.connectionType,
            serialBaud: original.serialBaud,
            serialPath: original.serialPath,
            vendorPreset: original.vendorPreset,
            autoConnect: original.autoConnect,
            badgeColorHex: original.badgeColorHex,
            jumpHost: original.jumpHost,
            jumpUser: original.jumpUser,
            jumpPort: original.jumpPort,
            enableLegacyCiphers: original.enableLegacyCiphers,
            tags: original.tags,
            notes: original.notes,
            lastConnected: nil
        )
        savedProfiles.append(copy)
        persistProfiles()
        return copy
    }

    public func moveProfile(id: UUID, toFolderId: UUID?) {
        guard let idx = savedProfiles.firstIndex(where: { $0.id == id }) else { return }
        savedProfiles[idx].folderId = toFolderId
        if let toFolderId, let folder = folders.first(where: { $0.id == toFolderId }) {
            savedProfiles[idx].folder = folder.name
        } else {
            savedProfiles[idx].folder = "General"
        }
        persistProfiles()
    }

    public func connectAllInFolder(folderId: UUID) {
        let profiles = savedProfiles.filter { $0.folderId == folderId }
        for profile in profiles {
            launchProfile(profile)
        }
    }

    @discardableResult
    public func saveActiveSessionAsProfile(
        session: TerminalSession,
        name: String,
        folderId: UUID? = nil,
        tags: [String] = [],
        notes: String = ""
    ) -> TerminalProfile {
        let folderName = folders.first(where: { $0.id == folderId })?.name ?? "General"
        let profileName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? session.title : name

        var connType = "ssh"
        var host = ""
        var port = 22
        var user = "admin"
        var identityFile: String? = nil
        var jumpHost: String? = nil
        var jumpPort: Int? = nil
        var jumpUser: String? = nil
        var legacyCiphers = false
        var serialPath = ""
        var serialBaud = 9600
        var badgeColor = "#00E5FF"

        switch session.connectionType {
        case .ssh(let h, let p, let u, let idf, _, let jh, let lc):
            connType = "ssh"
            host = h
            port = p
            user = u
            identityFile = idf
            jumpHost = jh?.host
            jumpPort = jh?.port
            jumpUser = jh?.username
            legacyCiphers = lc
            badgeColor = "#10B981"
        case .serial(let path, let baud, _, _, _):
            connType = "serial"
            serialPath = path
            serialBaud = baud
            badgeColor = "#F59E0B"
        case .localShell:
            connType = "localshell"
            badgeColor = "#8B5CF6"
        case .simulation:
            connType = "simulation"
            badgeColor = "#3B82F6"
        case .telnet(let h, let p):
            connType = "telnet"
            host = h
            port = p
            badgeColor = "#06B6D4"
        }

        let profile = TerminalProfile(
            name: profileName,
            folder: folderName,
            folderId: folderId,
            host: host,
            port: port,
            username: user,
            identityFile: identityFile,
            connectionType: connType,
            serialBaud: serialBaud,
            serialPath: serialPath,
            vendorPreset: "",
            autoConnect: false,
            badgeColorHex: badgeColor,
            jumpHost: jumpHost,
            jumpUser: jumpUser,
            jumpPort: jumpPort,
            enableLegacyCiphers: legacyCiphers,
            tags: tags,
            notes: notes,
            lastConnected: Date()
        )
        saveProfile(profile)
        return profile
    }

    // MARK: - Folder Management

    @discardableResult
    public func createFolder(name: String, parentId: UUID? = nil, colorHex: String? = "#F59E0B") -> SessionFolder {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let folderName = trimmed.isEmpty ? "New Folder" : trimmed
        let folder = SessionFolder(
            name: folderName,
            parentId: parentId,
            isExpanded: true,
            iconColorHex: colorHex ?? "#F59E0B"
        )
        folders.append(folder)
        persistFolders()
        return folder
    }

    public func renameFolder(id: UUID, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let idx = folders.firstIndex(where: { $0.id == id }) else { return }
        let oldName = folders[idx].name
        folders[idx].name = trimmed
        for pIdx in savedProfiles.indices where savedProfiles[pIdx].folderId == id || savedProfiles[pIdx].folder == oldName {
            savedProfiles[pIdx].folder = trimmed
            savedProfiles[pIdx].folderId = id
        }
        persistFolders()
        persistProfiles()
    }

    public func deleteFolder(id: UUID, deleteContents: Bool = false) {
        guard let folder = folders.first(where: { $0.id == id }) else { return }

        // Find all descendant folder IDs recursively
        var toDeleteFolderIds = Set<UUID>([id])
        var addedMore = true
        while addedMore {
            addedMore = false
            for f in folders where !toDeleteFolderIds.contains(f.id) {
                if let pid = f.parentId, toDeleteFolderIds.contains(pid) {
                    toDeleteFolderIds.insert(f.id)
                    addedMore = true
                }
            }
        }

        if deleteContents {
            savedProfiles.removeAll { p in
                if let fid = p.folderId, toDeleteFolderIds.contains(fid) { return true }
                return false
            }
        } else {
            for idx in savedProfiles.indices {
                if let fid = savedProfiles[idx].folderId, toDeleteFolderIds.contains(fid) {
                    savedProfiles[idx].folderId = folder.parentId
                    if let pid = folder.parentId, let parentFolder = folders.first(where: { $0.id == pid }) {
                        savedProfiles[idx].folder = parentFolder.name
                    } else {
                        savedProfiles[idx].folder = "General"
                    }
                }
            }
            for idx in folders.indices {
                if folders[idx].parentId == id {
                    folders[idx].parentId = folder.parentId
                }
            }
        }

        folders.removeAll { toDeleteFolderIds.contains($0.id) }
        persistFolders()
        persistProfiles()
    }

    public func toggleFolderExpansion(id: UUID) {
        if let idx = folders.firstIndex(where: { $0.id == id }) {
            folders[idx].isExpanded.toggle()
            persistFolders()
        }
    }

    public func setFolderColor(id: UUID, colorHex: String) {
        if let idx = folders.firstIndex(where: { $0.id == id }) {
            folders[idx].iconColorHex = colorHex
            persistFolders()
        }
    }

    public func moveFolder(id: UUID, toParentId: UUID?) {
        // Prevent cyclical nesting: target parent cannot be the folder itself or any of its descendants
        var descendantIds: Set<UUID> = [id]
        var added = true
        while added {
            added = false
            for f in folders where !descendantIds.contains(f.id) {
                if let pid = f.parentId, descendantIds.contains(pid) {
                    descendantIds.insert(f.id)
                    added = true
                }
            }
        }
        if let target = toParentId, descendantIds.contains(target) {
            return
        }
        if let idx = folders.firstIndex(where: { $0.id == id }) {
            folders[idx].parentId = toParentId
            persistFolders()
        }
    }

    public func expandAllFolders() {
        for idx in folders.indices {
            folders[idx].isExpanded = true
        }
        persistFolders()
    }

    public func collapseAllFolders() {
        for idx in folders.indices {
            folders[idx].isExpanded = false
        }
        persistFolders()
    }

    // MARK: - Export & Import Library (JSON)

    public struct SessionLibraryEnvelope: Codable {
        public var version: Int = 1
        public var exportedAt: Date = Date()
        public var folders: [SessionFolder]
        public var profiles: [TerminalProfile]
    }

    public func exportSessionLibrary() -> Data? {
        let envelope = SessionLibraryEnvelope(
            version: 1,
            exportedAt: Date(),
            folders: folders,
            profiles: savedProfiles
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(envelope)
    }

    @discardableResult
    public func importSessionLibrary(from data: Data) throws -> (foldersAdded: Int, profilesAdded: Int) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(SessionLibraryEnvelope.self, from: data)

        var fCount = 0
        for f in envelope.folders {
            if !folders.contains(where: { $0.id == f.id }) {
                folders.append(f)
                fCount += 1
            }
        }

        var pCount = 0
        for p in envelope.profiles {
            if !savedProfiles.contains(where: { $0.id == p.id }) {
                savedProfiles.append(p)
                pCount += 1
            }
        }

        persistFolders()
        persistProfiles()
        return (fCount, pCount)
    }

    // MARK: - Private Persistence

    private func loadFolders() {
        if let data = UserDefaults.standard.data(forKey: foldersStorageKey),
           let decoded = try? JSONDecoder().decode([SessionFolder].self, from: data),
           !decoded.isEmpty {
            self.folders = decoded
        } else {
            // Default Enterprise Folders
            self.folders = [
                SessionFolder(name: "Cloud Servers", iconColorHex: "#10B981"),
                SessionFolder(name: "Data Center", iconColorHex: "#00E5FF"),
                SessionFolder(name: "WAN Edge", iconColorHex: "#3B82F6"),
                SessionFolder(name: "Lab Rack", iconColorHex: "#F59E0B"),
                SessionFolder(name: "Local Shell", iconColorHex: "#8B5CF6")
            ]
            persistFolders()
        }
    }

    private func persistFolders() {
        if let data = try? JSONEncoder().encode(folders) {
            UserDefaults.standard.set(data, forKey: foldersStorageKey)
        }
    }

    private func loadProfiles() {
        if let data = UserDefaults.standard.data(forKey: profilesStorageKey),
           let decoded = try? JSONDecoder().decode([TerminalProfile].self, from: data) {
            self.savedProfiles = decoded
            if !self.savedProfiles.contains(where: { $0.host == "170.75.170.64" }) {
                self.savedProfiles.insert(
                    TerminalProfile(
                        name: "Ubuntu Test VM",
                        folder: "Cloud Servers",
                        host: "170.75.170.64",
                        port: 22,
                        username: "ubuntu",
                        connectionType: "ssh",
                        badgeColorHex: "#10B981",
                        tags: ["Production", "Ubuntu", "Cloud"],
                        notes: "Public cloud test instance with full sudo privileges"
                    ),
                    at: 0
                )
            }
            if !self.savedProfiles.contains(where: { $0.connectionType.lowercased() == "telnet" }) {
                self.savedProfiles.append(
                    TerminalProfile(
                        name: "EVE-NG Lab Switch (Telnet)",
                        folder: "Lab Rack",
                        host: "192.168.1.100",
                        port: 32769,
                        username: "",
                        connectionType: "telnet",
                        badgeColorHex: "#06B6D4",
                        tags: ["Lab", "EVE-NG", "GNS3", "Telnet"],
                        notes: "Virtual lab router/switch console exposed over Telnet port 32769"
                    )
                )
            }
        } else {
            // Enterprise default templates (100% Real Network Endpoints)
            self.savedProfiles = [
                TerminalProfile(
                    name: "Ubuntu Test VM",
                    folder: "Cloud Servers",
                    host: "170.75.170.64",
                    port: 22,
                    username: "ubuntu",
                    connectionType: "ssh",
                    badgeColorHex: "#10B981",
                    tags: ["Production", "Ubuntu", "Cloud"],
                    notes: "Public cloud test instance with full sudo privileges"
                ),
                TerminalProfile(
                    name: "Core Spine 01 (Cisco)",
                    folder: "Data Center",
                    host: "10.100.1.1",
                    port: 22,
                    username: "admin",
                    connectionType: "ssh",
                    badgeColorHex: "#00E5FF",
                    tags: ["Spine", "BGP", "DataCenter"],
                    notes: "Primary BGP spine router in DC-West"
                ),
                TerminalProfile(
                    name: "WAN Edge Gateway",
                    folder: "WAN Edge",
                    host: "198.51.100.1",
                    port: 22,
                    username: "admin",
                    connectionType: "ssh",
                    badgeColorHex: "#3B82F6",
                    tags: ["SD-WAN", "Border"],
                    notes: "Edge border gateway router"
                ),
                TerminalProfile(
                    name: "Edge Switch USB Console",
                    folder: "Lab Rack",
                    host: "",
                    connectionType: "serial",
                    serialBaud: 9600,
                    serialPath: "/dev/cu.usbserial-001",
                    badgeColorHex: "#F59E0B",
                    tags: ["Console", "Serial", "Hardware"],
                    notes: "Direct RS-232 / USB serial console port"
                ),
                TerminalProfile(
                    name: "Local macOS Terminal",
                    folder: "Local Shell",
                    host: "localhost",
                    connectionType: "localshell",
                    badgeColorHex: "#8B5CF6",
                    tags: ["zsh", "Local"],
                    notes: "Local POSIX zsh terminal with full environment"
                ),
                TerminalProfile(
                    name: "EVE-NG Lab Switch (Telnet)",
                    folder: "Lab Rack",
                    host: "192.168.1.100",
                    port: 32769,
                    username: "",
                    connectionType: "telnet",
                    badgeColorHex: "#06B6D4",
                    tags: ["Lab", "EVE-NG", "GNS3", "Telnet"],
                    notes: "Virtual lab router/switch console exposed over Telnet port 32769"
                )
            ]
            persistProfiles()
        }

        // Migrate any profile with missing folderId
        var changed = false
        for idx in savedProfiles.indices {
            if savedProfiles[idx].folderId == nil {
                let folderName = savedProfiles[idx].folder
                if let match = folders.first(where: { $0.name.caseInsensitiveCompare(folderName) == .orderedSame }) {
                    savedProfiles[idx].folderId = match.id
                    savedProfiles[idx].folder = match.name
                    changed = true
                } else if !folderName.isEmpty {
                    let newFolder = SessionFolder(name: folderName)
                    folders.append(newFolder)
                    savedProfiles[idx].folderId = newFolder.id
                    changed = true
                }
            }
        }
        if changed {
            persistFolders()
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
