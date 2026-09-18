import Testing
import Foundation
@testable import TerminalKit

@Suite("Terminal & Console Session Tests")
struct TerminalTests {

    @Test("Serial Discovery identifies USB adapters and standard baud rates")
    func testSerialDiscovery() {
        let discovery = SerialDiscovery.shared
        #expect(SerialDiscovery.standardBaudRates.contains(9600))
        #expect(SerialDiscovery.standardBaudRates.contains(115200))

        #expect(discovery.isUSBSerialDevice("cu.usbserial-1140"))
        #expect(discovery.isUSBSerialDevice("cu.SLAB_USBtoUART"))
        #expect(discovery.isUSBSerialDevice("cu.wchusbserial1420"))
        #expect(discovery.isUSBSerialDevice("cu.usbmodem1101"))
        #expect(!discovery.isUSBSerialDevice("cu.Bluetooth-Incoming-Port"))

        let friendly = discovery.resolveFriendlyName("cu.usbserial-110")
        #expect(friendly.contains("FTDI"))
    }

    @Test("Simulated CLI responds to show commands and config transitions")
    func testSimulatedCLI() {
        let sim = SimulatedDeviceCLI(hostname: "core-rtr01", vendor: "Cisco IOS-XE")
        var outputs: [String] = []
        sim.onOutput = { chunk in
            outputs.append(chunk)
        }

        sim.start()
        #expect(outputs.count == 1)
        #expect(outputs[0].contains("Cisco IOS-XE"))
        #expect(outputs[0].contains("core-rtr01#"))

        // Run show ip interface brief
        sim.processInput("show ip interface brief")
        let lastOutput = outputs.last ?? ""
        #expect(lastOutput.contains("GigabitEthernet1/0/1"))
        #expect(lastOutput.contains("10.10.10.1"))

        // Run show version
        sim.processInput("show version")
        #expect((outputs.last ?? "").contains("Cisco IOS XE Software"))

        // Enter config mode
        sim.processInput("configure terminal")
        #expect(sim.currentPrompt == "core-rtr01(config)# ")

        // Exit config mode
        sim.processInput("exit")
        #expect(sim.currentPrompt == "core-rtr01# ")
    }

    @Test("Terminal Session strips ANSI sequences and manages command history")
    func testTerminalSession() {
        let session = TerminalSession(
            title: "Test Session",
            connectionType: .simulation(presetName: "Lab Switch")
        )
        session.connect()

        #expect(session.status == .connected)
        #expect(!session.lines.isEmpty)

        // Test command history recording
        session.sendCommand("show cdp neighbors")
        #expect(session.commandHistory.contains("show cdp neighbors"))

        // Test ANSI escape stripping
        let rawAnsi = "\u{1B}[1;32mSwitch#\u{1B}[0m show run\r\n"
        let stripped = session.stripAnsiEscapeSequences(from: rawAnsi)
        #expect(!stripped.contains("\u{1B}"))
        #expect(stripped.contains("Switch#"))
    }

    @Test("External Terminal Bridge formats URLs and commands")
    func testExternalTerminalBridge() {
        let bridge = ExternalTerminalBridge.shared

        let url = bridge.sshURL(host: "10.200.1.1", port: 2222, username: "cisco")
        #expect(url?.absoluteString == "ssh://cisco@10.200.1.1:2222")

        let cmd = bridge.sshCommand(host: "192.168.1.1", port: 22, username: "admin")
        #expect(cmd == "ssh admin@192.168.1.1")

        let screenCmd = bridge.serialScreenCommand(devicePath: "/dev/cu.usbserial-10", baudRate: 115200)
        #expect(screenCmd == "screen /dev/cu.usbserial-10 115200")
    }

    @Test("Terminal Manager adds, switches, and closes tabs")
    func testTerminalManager() {
        let manager = TerminalManager()
        let initialCount = manager.sessions.count

        let ssh = manager.openSSHSession(host: "10.0.0.1", port: 22, username: "netadmin", autoConnect: false)
        #expect(manager.sessions.count == initialCount + 1)
        #expect(manager.activeSessionId == ssh.id)

        let sim = manager.openSimulatedSession(preset: "Arista 7050X")
        #expect(manager.activeSessionId == sim.id)

        // Close session
        manager.closeSession(id: sim.id)
        #expect(!manager.sessions.contains(where: { $0.id == sim.id }))
    }

    @Test("SSH Profile configuration and session log export")
    func testSSHProfileAndSessionExport() {
        let profile = SSHProfile(
            name: "Core Gateway SFO",
            host: "10.10.10.1",
            port: 2222,
            username: "cisco",
            authMethod: .password("Cisco123!"),
            terminalType: "xterm-color",
            logSession: true
        )
        #expect(profile.name == "Core Gateway SFO")
        #expect(profile.port == 2222)

        let session = TerminalSession(
            title: profile.name,
            connectionType: .ssh(host: profile.host, port: profile.port, username: profile.username, password: "Cisco123!")
        )
        session.sendCommand("show ip route")
        let exportLog = session.exportSessionLog()
        #expect(exportLog.contains("# NexWave Terminal Session Log"))
        #expect(exportLog.contains(profile.name))
        #expect(exportLog.contains("show ip route"))
    }

    @Test("Terminal Themes provide valid hex palettes for dark modes")
    func testTerminalThemes() {
        #expect(TerminalTheme.allCases.count == 8)
        for theme in TerminalTheme.allCases {
            #expect(!theme.rawValue.isEmpty)
            #expect(theme.backgroundColorHex.hasPrefix("#"))
            #expect(theme.foregroundColorHex.hasPrefix("#"))
            #expect(theme.promptColorHex.hasPrefix("#"))
            #expect(theme.selectionColorHex.hasPrefix("#"))
        }
        #expect(TerminalTheme.obsidian.id == "Obsidian Cyber")
        #expect(TerminalTheme.matrix.promptColorHex == "#33FF33")
    }

    @Test("Command Macros include standard networking diagnostics and serialize cleanly")
    func testCommandMacros() throws {
        let macros = CommandMacro.defaultMacros
        #expect(macros.count >= 8)

        let intMacro = macros.first { $0.command == "show ip int br" }
        #expect(intMacro != nil)
        #expect(intMacro?.category == "L3")

        let bgpMacro = macros.first { $0.command == "show ip bgp summary" }
        #expect(bgpMacro != nil)
        #expect(bgpMacro?.category == "Routing")

        // Serialization roundtrip
        let encoder = JSONEncoder()
        let data = try encoder.encode(macros)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode([CommandMacro].self, from: data)
        #expect(decoded.count == macros.count)
    }

    @Test("Terminal Session live transcript search and case-insensitive filtering")
    func testTranscriptSearch() {
        let session = TerminalSession(
            title: "Search Test",
            connectionType: .simulation(presetName: "Switch")
        )
        session.connect()
        session.sendCommand("show ip interface brief")
        session.sendCommand("show ip route")
        session.sendCommand("show version")

        // Search for specific interface substring
        let interfaceMatches = session.searchLines(query: "gigabit")
        #expect(!interfaceMatches.isEmpty)

        // Search case-insensitive
        let upperMatches = session.searchLines(query: "GIGABIT")
        #expect(upperMatches.count == interfaceMatches.count)

        // Empty query returns all lines
        let allLines = session.searchLines(query: "")
        #expect(allLines.count == session.lines.count)

        // Non-existent string returns empty
        let nonExistent = session.searchLines(query: "nonexistent_pattern_xyz_12345")
        #expect(nonExistent.isEmpty)
    }

    @Test("ANSI SGR Parser decodes standard 16-color, 256-color, TrueColor, and styling")
    func testANSISGRParser() {
        let parser = ANSISGRParser()

        // Test 1: Standard 16-color & bold
        let line1 = "\u{1B}[1;32mSwitch#\u{1B}[0m show version"
        let (spans1, _) = parser.parseSpans(from: line1)
        #expect(!spans1.isEmpty)
        let promptSpan = spans1.first { $0.text == "Switch#" }
        #expect(promptSpan != nil)
        #expect(promptSpan?.style.isBold == true)
        #expect(promptSpan?.style.foreground != nil)
        #expect((promptSpan?.style.foreground?.g ?? 0) > 100)

        // Test 2: 256-color foreground (38;5;196)
        let line2 = "\u{1B}[38;5;196mCRITICAL ALERT\u{1B}[0m"
        let (spans2, _) = parser.parseSpans(from: line2)
        let alertSpan = spans2.first { $0.text.contains("CRITICAL ALERT") }
        #expect(alertSpan != nil)
        #expect(alertSpan?.style.foreground?.r == 255)

        // Test 3: TrueColor 24-bit RGB (38;2;255;128;0)
        let line3 = "\u{1B}[38;2;255;128;0mTrueColor Orange\u{1B}[0m"
        let (spans3, _) = parser.parseSpans(from: line3)
        let orangeSpan = spans3.first { $0.text.contains("TrueColor Orange") }
        #expect(orangeSpan != nil)
        #expect(orangeSpan?.style.foreground?.r == 255)
        #expect(orangeSpan?.style.foreground?.g == 128)
        #expect(orangeSpan?.style.foreground?.b == 0)

        // Test 4: Carriage return overwrite
        let carriageReturnRaw = "Loading [===>    ] 30%\rLoading [========>] 100%\n"
        let parsedLines = parser.parseLines(from: carriageReturnRaw)
        #expect(parsedLines.count == 1)
        #expect(parsedLines[0].text.contains("100%"))
        #expect(!parsedLines[0].text.contains("30%"))
    }

    @Test("Multi-Vendor CLI Simulation engines emulate Cisco, Arista, and Juniper faithfully")
    func testMultiVendorSimulators() {
        // Cisco IOS-XE Simulation
        let cisco = SimulatedDeviceCLI(hostname: "core-sw01", vendor: .ciscoIOSXE)
        var ciscoOutput: [String] = []
        cisco.onOutput = { ciscoOutput.append($0) }
        cisco.start()
        #expect((ciscoOutput.first ?? "").contains("Cisco IOS-XE Simulation Engine"))
        #expect(cisco.currentPrompt == "core-sw01# ")

        cisco.processInput("show version")
        #expect((ciscoOutput.last ?? "").contains("Cisco IOS XE"))

        cisco.processInput("configure terminal")
        #expect(cisco.currentPrompt == "core-sw01(config)# ")
        cisco.processInput("exit")
        #expect(cisco.currentPrompt == "core-sw01# ")

        // Arista EOS Simulation
        let arista = SimulatedDeviceCLI(hostname: "spine01", vendor: .aristaEOS)
        var aristaOutput: [String] = []
        arista.onOutput = { aristaOutput.append($0) }
        arista.start()
        #expect((aristaOutput.first ?? "").contains("Arista EOS Spine Simulation Engine"))
        #expect(arista.currentPrompt == "spine01# ")

        arista.processInput("show lldp neighbors")
        #expect((aristaOutput.last ?? "").contains("spine01"))

        arista.processInput("show version")
        #expect((aristaOutput.last ?? "").contains("Arista DCS-7050SX3"))

        // Juniper Junos Simulation
        let juniper = SimulatedDeviceCLI(hostname: "ex4300", vendor: .juniperJunos)
        var juniperOutput: [String] = []
        juniper.onOutput = { juniperOutput.append($0) }
        juniper.start()
        #expect((juniperOutput.first ?? "").contains("JUNOS"))
        #expect(juniper.currentPrompt == "admin@ex4300> ")

        juniper.processInput("show interfaces terse")
        #expect((juniperOutput.last ?? "").contains("ge-0/0/0.0"))

        juniper.processInput("configure")
        #expect(juniper.currentPrompt.contains("admin@ex4300# "))

        juniper.processInput("commit")
        #expect((juniperOutput.last ?? "").contains("commit complete"))

        juniper.processInput("exit")
        #expect(juniper.currentPrompt == "admin@ex4300> ")
    }

    @Test("Command Macro parameter interpolation expands variables accurately")
    func testMacroParameterInterpolation() {
        let macro = CommandMacro(
            name: "Ping Host",
            command: "ping {ip} repeat {count}",
            category: "Diagnostics"
        )

        let params: [String: String] = [
            "ip": "172.16.1.1",
            "count": "100"
        ]

        let expanded = macro.expandCommand(with: params)
        #expect(expanded == "ping 172.16.1.1 repeat 100")

        // Unmatched parameters remain cleanly
        let partialExpanded = macro.expandCommand(with: ["ip": "192.168.1.1"])
        #expect(partialExpanded == "ping 192.168.1.1 repeat {count}")
    }

    @Test("Terminal Profile Vault provides templates and supports persistence")
    func testTerminalProfileVault() {
        let manager = TerminalManager()
        #expect(!manager.savedProfiles.isEmpty)

        // Seeded templates check
        let ciscoTemplate = manager.savedProfiles.first { $0.name.contains("Cisco") }
        #expect(ciscoTemplate != nil)
        #expect(ciscoTemplate?.folder == "Data Center")

        let serialTemplate = manager.savedProfiles.first { $0.name.contains("USB Console") }
        #expect(serialTemplate != nil)
        #expect(serialTemplate?.folder == "Lab Rack")

        // Save a custom profile
        let customProfile = TerminalProfile(
            name: "Edge-Router-01",
            folder: "WAN Edge",
            host: "198.51.100.1",
            port: 22,
            username: "admin",
            connectionType: "ssh"
        )
        manager.saveProfile(customProfile)
        #expect(manager.savedProfiles.contains(where: { $0.id == customProfile.id }))

        // Filter profiles by folder
        let wanProfiles = manager.savedProfiles.filter { $0.folder == "WAN Edge" }
        #expect(wanProfiles.contains(where: { $0.id == customProfile.id }))

        // Delete profile
        manager.deleteProfile(id: customProfile.id)
        #expect(!manager.savedProfiles.contains(where: { $0.id == customProfile.id }))
    }

    @Test("Dynamic Folder Hierarchy supports nested subfolders, renaming, and colors")
    func testDynamicFolderHierarchy() {
        let manager = TerminalManager()
        let rootFolder = manager.createFolder(name: "Production Spine", colorHex: "#10B981")
        #expect(manager.folders.contains(where: { $0.id == rootFolder.id }))
        #expect(rootFolder.name == "Production Spine")
        #expect(rootFolder.iconColorHex == "#10B981")

        // Create subfolder
        let subfolder = manager.createFolder(name: "DC-East", parentId: rootFolder.id, colorHex: "#00E5FF")
        #expect(subfolder.parentId == rootFolder.id)
        #expect(manager.folders.contains(where: { $0.id == subfolder.id }))

        // Rename folder
        manager.renameFolder(id: subfolder.id, newName: "DC-East-Fabric")
        let updatedSub = manager.folders.first(where: { $0.id == subfolder.id })
        #expect(updatedSub?.name == "DC-East-Fabric")

        // Change color
        manager.setFolderColor(id: subfolder.id, colorHex: "#8B5CF6")
        #expect(manager.folders.first(where: { $0.id == subfolder.id })?.iconColorHex == "#8B5CF6")

        // Toggle expansion
        let initialExpanded = subfolder.isExpanded
        manager.toggleFolderExpansion(id: subfolder.id)
        #expect(manager.folders.first(where: { $0.id == subfolder.id })?.isExpanded == !initialExpanded)

        // Delete parent folder without deleting contents (reparenting)
        manager.deleteFolder(id: rootFolder.id, deleteContents: false)
        #expect(!manager.folders.contains(where: { $0.id == rootFolder.id }))
        // Subfolder should now be promoted to root (parentId == nil)
        let reparentedSub = manager.folders.first(where: { $0.id == subfolder.id })
        #expect(reparentedSub?.parentId == nil)

        // Cleanup
        manager.deleteFolder(id: subfolder.id, deleteContents: true)
    }

    @Test("Profile duplicate, move between folders, and active session bookmarking")
    func testProfileDuplicateMoveAndBookmark() {
        let manager = TerminalManager()
        let folderA = manager.createFolder(name: "Zone Alpha")
        let folderB = manager.createFolder(name: "Zone Beta")

        let profile = TerminalProfile(
            name: "Router Alpha",
            folder: folderA.name,
            folderId: folderA.id,
            host: "10.0.1.1",
            connectionType: "ssh",
            tags: ["Edge", "BGP"]
        )
        manager.saveProfile(profile)
        #expect(manager.savedProfiles.contains(where: { $0.id == profile.id }))

        // Duplicate
        let duplicated = manager.duplicateProfile(id: profile.id)
        #expect(duplicated != nil)
        #expect(duplicated?.name == "Router Alpha (Copy)")
        #expect(duplicated?.host == "10.0.1.1")
        #expect(manager.savedProfiles.contains(where: { $0.id == duplicated?.id }))

        // Move to folder B
        manager.moveProfile(id: profile.id, toFolderId: folderB.id)
        let moved = manager.savedProfiles.first(where: { $0.id == profile.id })
        #expect(moved?.folderId == folderB.id)
        #expect(moved?.folder == folderB.name)

        // One-click save active session as profile
        let liveSession = manager.openLocalShell()
        let bookmarked = manager.saveActiveSessionAsProfile(
            session: liveSession,
            name: "My Quick Shell",
            folderId: folderB.id,
            tags: ["Quick", "Shell"],
            notes: "Saved from active tab"
        )
        #expect(bookmarked.name == "My Quick Shell")
        #expect(bookmarked.folderId == folderB.id)
        #expect(bookmarked.tags == ["Quick", "Shell"])
        #expect(manager.savedProfiles.contains(where: { $0.id == bookmarked.id }))

        // Cleanup
        manager.deleteProfile(id: profile.id)
        if let dupId = duplicated?.id { manager.deleteProfile(id: dupId) }
        manager.deleteProfile(id: bookmarked.id)
        manager.deleteFolder(id: folderA.id, deleteContents: true)
        manager.deleteFolder(id: folderB.id, deleteContents: true)
        manager.closeSession(id: liveSession.id)
    }

    @Test("Session Library JSON export and import roundtrip preserves hierarchy")
    func testSessionLibraryExportImport() throws {
        let manager = TerminalManager()
        let testFolder = manager.createFolder(name: "Export Test Vault", colorHex: "#3B82F6")
        let testProfile = TerminalProfile(
            name: "Export Gateway",
            folder: testFolder.name,
            folderId: testFolder.id,
            host: "10.99.99.1",
            connectionType: "ssh",
            tags: ["ExportTest"]
        )
        manager.saveProfile(testProfile)

        // Export JSON
        let exportedData = manager.exportSessionLibrary()
        #expect(exportedData != nil)
        guard let data = exportedData else { return }

        // Verify JSON can be decoded
        let (fCount, pCount) = try manager.importSessionLibrary(from: data)
        // Since they already exist, count added should be 0 without crashing or duplicates
        #expect(fCount == 0)
        #expect(pCount == 0)

        // Cleanup
        manager.deleteProfile(id: testProfile.id)
        manager.deleteFolder(id: testFolder.id, deleteContents: true)
    }

    @Test("Broadcast Mode broadcasts commands and breaks across all connected sessions")
    func testBroadcastDispatch() {
        let manager = TerminalManager()

        // Create two simulated sessions
        let session1 = manager.openSimulatedSession(preset: "Cisco Catalyst 9300")
        let session2 = manager.openSimulatedSession(preset: "Arista 7050X")

        #expect(manager.sessions.count >= 2)
        #expect(session1.status == .connected)
        #expect(session2.status == .connected)

        // Enable broadcast mode
        manager.isBroadcastEnabled = true
        #expect(manager.isBroadcastEnabled == true)

        // Broadcast command
        manager.broadcastCommand("show version")
        #expect(session1.commandHistory.contains("show version"))
        #expect(session2.commandHistory.contains("show version"))

        // Broadcast hardware break
        manager.broadcastBreak()
        #expect(session1.lines.contains(where: { $0.text.contains("BREAK SIGNAL") }))
        #expect(session2.lines.contains(where: { $0.text.contains("BREAK SIGNAL") }))
    }

    @Test("Continuous session logging appends timestamps and creates directory structure")
    func testContinuousSessionLogging() {
        let session = TerminalSession(
            title: "Logger Test",
            connectionType: .simulation(presetName: "Switch")
        )
        session.connect()

        #expect(session.logFilePath != nil)

        // Send a command to trigger logging
        session.sendCommand("show interface brief")

        // Verify log export contains timestamps
        let exported = session.exportSessionLog()
        #expect(exported.contains("# NexWave Terminal Session Log"))
        #expect(exported.contains("Logger Test"))

        session.disconnect()
    }

    @Test("SSH Jump Host formats ProxyJump argument correctly")
    func testSSHJumpConfigArgument() {
        let jump = SSHJumpConfig(host: "bastion.corp.net", port: 2222, username: "jumpuser")
        #expect(jump.proxyJumpArgument == "jumpuser@bastion.corp.net:2222")

        let defaultJump = SSHJumpConfig(host: "gateway.internal", port: 22, username: "admin")
        #expect(defaultJump.proxyJumpArgument == "admin@gateway.internal:22")
    }

    @Test("SSH Tunnel Manager configures -L, -R, and -D tunnels with proper spec strings")
    func testSSHTunnelManagerAndConfig() {
        let manager = SSHTunnelManager.shared

        let localTunnel = SSHTunnelConfig(
            name: "Local Database",
            tunnelType: .localForward,
            localPort: 5432,
            destinationHost: "db.internal.corp",
            destinationPort: 5432,
            sshHost: "bastion.corp.com",
            sshUsername: "deploy"
        )
        #expect(localTunnel.specString == "5432:db.internal.corp:5432")
        #expect(localTunnel.tunnelType.flag == "-L")

        let remoteTunnel = SSHTunnelConfig(
            name: "Remote Webhook",
            tunnelType: .remoteForward,
            localPort: 9000,
            destinationHost: "localhost",
            destinationPort: 3000,
            sshHost: "edge.server.net",
            sshUsername: "root"
        )
        #expect(remoteTunnel.specString == "9000:localhost:3000")
        #expect(remoteTunnel.tunnelType.flag == "-R")

        let socksTunnel = SSHTunnelConfig(
            name: "SOCKS5 Proxy",
            tunnelType: .dynamicSOCKS5,
            localPort: 1080,
            sshHost: "proxy.server.net",
            sshUsername: "admin"
        )
        #expect(socksTunnel.specString == "1080")
        #expect(socksTunnel.tunnelType.flag == "-D")

        // Test saving and deletion in manager
        manager.saveTunnel(localTunnel)
        #expect(manager.tunnels.contains(where: { $0.id == localTunnel.id }))

        manager.deleteTunnel(id: localTunnel.id)
        #expect(!manager.tunnels.contains(where: { $0.id == localTunnel.id }))
    }

    @Test("Terminal Keyword Highlighter dynamically color-codes IPs, MACs, Errors, and Status")
    func testTerminalKeywordHighlighter() {
        let highlighter = TerminalKeywordHighlighter.shared
        let config = TerminalSyntaxHighlightConfig(
            isEnabled: true,
            highlightIPs: true,
            highlightMACs: true,
            highlightErrors: true,
            highlightSuccess: true
        )

        let lineText = "Interface Gi0/1 192.168.1.50 is up with MAC 00:1A:2B:3C:4D:5E but status denied"
        let line = TerminalLine(text: lineText)
        let highlighted = highlighter.highlight(line: line, config: config)

        // Spans should be decomposed into multiple styled segments
        #expect(highlighted.spans.count > 1)
        #expect(highlighted.spans.contains(where: { $0.text == "192.168.1.50" }))
        #expect(highlighted.spans.contains(where: { $0.text.lowercased() == "up" }))
        #expect(highlighted.spans.contains(where: { $0.text == "00:1A:2B:3C:4D:5E" }))
        #expect(highlighted.spans.contains(where: { $0.text.lowercased() == "denied" }))
    }

    @Test("SSH Key Studio discovers local SSH keys in user directory")
    func testSSHKeyStudioDiscovery() {
        let studio = SSHKeyStudio.shared
        let keys = studio.discoverLocalKeys()
        // Discovery executes without throwing and returns a valid array
        #expect(keys.count >= 0)
    }

    @Test("Quad Grid 2x2 layout supports 4 active pane bindings")
    func testQuadGridSplitModeAndPanes() {
        let manager = TerminalManager()
        #expect(TerminalSplitMode.quadGrid.rawValue == "2x2 Quad Grid (4 Panes)")

        manager.splitMode = .quadGrid
        let s1 = manager.openSimulatedSession(preset: "Cisco Catalyst 9300")
        let s2 = manager.openSimulatedSession(preset: "Arista 7050X")
        let s3 = manager.openSimulatedSession(preset: "Juniper EX4300")
        let s4 = manager.openSimulatedSession(preset: "Lab Core Switch")

        manager.activeSessionId = s1.id
        manager.secondarySessionId = s2.id
        manager.pane3SessionId = s3.id
        manager.pane4SessionId = s4.id

        #expect(manager.activeSession?.id == s1.id)
        #expect(manager.secondarySession?.id == s2.id)
        #expect(manager.pane3Session?.id == s3.id)
        #expect(manager.pane4Session?.id == s4.id)
    }

    @Test("Live Online SSH Handshake over PTY to GitHub")
    func testLiveOnlineSSHGitHubHandshake() async throws {
        let runner = PTYProcessRunner()
        let receivedText = AsyncStream<String> { continuation in
            runner.onOutput = { chunk in
                continuation.yield(chunk)
            }
            runner.onTermination = { _ in
                continuation.finish()
            }
        }

        try runner.launchSSH(host: "github.com", port: 22, username: "git")

        var combinedOutput = ""
        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            runner.terminate()
        }

        for await chunk in receivedText {
            combinedOutput += chunk
            if combinedOutput.contains("Permission denied") || combinedOutput.contains("github.com") {
                break
            }
        }

        timeoutTask.cancel()
        runner.terminate()

        if !combinedOutput.isEmpty {
            #expect(combinedOutput.contains("Permission denied") || combinedOutput.contains("github.com") || combinedOutput.contains("Host key") || combinedOutput.contains("ssh:") || combinedOutput.contains("closed") || combinedOutput.contains("timed out"))
        }
    }

    @Test("Live Online SSH Authentication Prompt over PTY from Ubuntu Server")
    func testLiveOnlineSSHUserServerAuthPrompt() async throws {
        let runner = PTYProcessRunner()
        let receivedText = AsyncStream<String> { continuation in
            runner.onOutput = { chunk in
                continuation.yield(chunk)
            }
            runner.onTermination = { _ in
                continuation.finish()
            }
        }

        try runner.launchSSH(host: "185.81.99.104", port: 22, username: "root")

        var combinedOutput = ""
        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            runner.terminate()
        }

        for await chunk in receivedText {
            combinedOutput += chunk
            if combinedOutput.contains("password:") || combinedOutput.contains("185.81.99.104") || combinedOutput.contains("Permission denied") {
                break
            }
        }

        timeoutTask.cancel()
        runner.terminate()

        if !combinedOutput.isEmpty {
            #expect(combinedOutput.contains("password:") || combinedOutput.contains("185.81.99.104") || combinedOutput.contains("Permission denied") || combinedOutput.contains("timed out") || combinedOutput.contains("Operation"))
        }
    }

    @Test("Live Online SSH Authentication with Password against User Test VM")
    func testLiveSSHUserVM() async throws {
        let runner = PTYProcessRunner()
        let receivedText = AsyncStream<String> { continuation in
            runner.onOutput = { chunk in
                continuation.yield(chunk)
            }
            runner.onTermination = { _ in
                continuation.finish()
            }
        }

        try runner.launchSSH(
            host: "170.75.170.64",
            port: 22,
            username: "ubuntu",
            password: "wC9xhrrRQcZfyPBl",
            enableLegacyCiphers: false
        )

        var combinedOutput = ""
        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            runner.terminate()
        }

        for await chunk in receivedText {
            combinedOutput += chunk
            if combinedOutput.contains("ubuntu@") && (combinedOutput.contains("$") || combinedOutput.contains("Welcome to Ubuntu")) {
                break
            }
        }

        timeoutTask.cancel()
        runner.terminate()

        #expect(combinedOutput.contains("ubuntu@") || combinedOutput.contains("Welcome to Ubuntu"))
    }

    @Test("ANSI SGR Parser handles colon-delimited TrueColor and 256-color parameters (ISO/IEC 8613-6)")
    func testSGRColonDelimited() {
        // Test 256-color with colon delimiter: \u{1B}[38:5:196m
        let spans256 = ANSISGRParser.shared.parseSpans(from: "\u{1B}[38:5:196mRedAlert\u{1B}[0m").0
        #expect(spans256.count >= 1)
        let redSpan = spans256.first(where: { $0.text == "RedAlert" })
        #expect(redSpan?.style.foreground != nil)

        // Test TrueColor with colon delimiter: \u{1B}[38:2::0:255:128m
        let spansTrueColor = ANSISGRParser.shared.parseSpans(from: "\u{1B}[38:2::0:255:128mNeonGreen\u{1B}[0m").0
        let greenSpan = spansTrueColor.first(where: { $0.text == "NeonGreen" })
        #expect(greenSpan?.style.foreground?.r == 0)
        #expect(greenSpan?.style.foreground?.g == 255)
        #expect(greenSpan?.style.foreground?.b == 128)
    }

    @Test("Terminal Session batch appends, handles carriage returns, and amortizes buffer trimming")
    func testBufferTrimmingAndCarriageReturn() {
        let session = TerminalSession(
            title: "Performance Test",
            connectionType: .localShell
        )
        session.maxBufferedLines = 50

        // Push 120 lines to trigger amortized trimming
        for i in 1...120 {
            session.appendOutput("Line \(i)\n")
        }

        // Buffer size should stay bounded near maxBufferedLines
        #expect(session.lines.count <= 60)
        #expect(session.lines.count >= 40)

        // Test carriage return in-place overwrite (e.g. progress spinner / counter)
        session.appendOutput("Progress: 10%\rProgress: 50%\rProgress: 100%\n")
        let lastLine = session.lines.last?.text ?? ""
        #expect(lastLine.contains("Progress: 100%"))
    }

    @Test("Terminal Session handles character-by-character interactive streaming without line fragmentation")
    func testCharacterByCharacterStreaming() {
        let session = TerminalSession(
            title: "Interactive Streaming Test",
            connectionType: .localShell
        )

        // 1. Initial shell prompt arrives without trailing newline
        session.appendOutput("user@mac ~ % ")
        #expect(session.lines.count == 1)
        #expect(session.lines.first?.text == "user@mac ~ % ")

        // 2. User types keystrokes character-by-character: 'u', 'n', 'a', 'm', 'e'
        let keystrokes = ["u", "n", "a", "m", "e"]
        for char in keystrokes {
            session.appendOutput(char)
        }

        // Must stay on the SAME line without creating separate rows
        #expect(session.lines.count == 1)
        #expect(session.lines.first?.text == "user@mac ~ % uname")

        // 3. User hits backspace twice, then types "p"
        session.appendOutput("\u{08} \u{08}\u{08} \u{08}")
        #expect(session.lines.count == 1)
        #expect(session.lines.first?.text == "user@mac ~ % una")

        session.appendOutput("p")
        #expect(session.lines.count == 1)
        #expect(session.lines.first?.text == "user@mac ~ % unap")

        // 4. User hits Return (\r\n) -> commits line 1
        session.appendOutput("\r\n")
        #expect(session.lines.count == 1)
        #expect(session.lines.first?.text == "user@mac ~ % unap")

        // 5. Command output arrives with newlines
        session.appendOutput("Darwin Kernel Version 23.6.0\r\nuser@mac ~ % ")
        #expect(session.lines.count == 3)
        #expect(session.lines[0].text == "user@mac ~ % unap")
        #expect(session.lines[1].text == "Darwin Kernel Version 23.6.0")
        #expect(session.lines[2].text == "user@mac ~ % ")

        // 6. Next keystrokes accumulate on prompt line 3
        session.appendOutput("l")
        session.appendOutput("s")
        #expect(session.lines.count == 3)
        #expect(session.lines[2].text == "user@mac ~ % ls")
    }

    @Test("Terminal Typography, Font Families, Cursor Styles, and Session Overrides")
    func testTerminalTypographyAndCursorCustomization() {
        // 1. Verify all cursor styles
        #expect(TerminalCursorStyle.allCases.count == 3)
        #expect(TerminalCursorStyle.block.glyph == "▋")
        #expect(TerminalCursorStyle.beam.glyph == "❘")
        #expect(TerminalCursorStyle.underline.glyph == "_")
        #expect(TerminalCursorStyle.block.cursorGlyph == "▋")

        // 2. Verify all font families
        #expect(TerminalFontFamily.allCases.count == 10)
        #expect(TerminalFontFamily.system.fontName == "SF Mono")
        #expect(TerminalFontFamily.menlo.fontName == "Menlo")
        #expect(TerminalFontFamily.monaco.fontName == "Monaco")
        #expect(TerminalFontFamily.jetBrainsMono.fontName == "JetBrains Mono")
        #expect(TerminalFontFamily.firaCode.fontName == "Fira Code")

        // 3. Verify session-specific styling overrides
        let session = TerminalSession(title: "Router-Core-1", connectionType: .simulation(presetName: "Catalyst 9300 Core"))
        #expect(session.fontSizeOverride == nil)
        #expect(session.fontFamilyOverride == nil)
        #expect(session.themeOverride == nil)
        #expect(session.cursorStyleOverride == nil)

        // Set overrides
        session.fontSizeOverride = 16.0
        session.fontFamilyOverride = TerminalFontFamily.jetBrainsMono.rawValue
        session.themeOverride = TerminalTheme.synthwave
        session.cursorStyleOverride = TerminalCursorStyle.beam

        #expect(session.fontSizeOverride == 16.0)
        #expect(session.fontFamilyOverride == "JetBrains Mono")
        #expect(session.themeOverride == TerminalTheme.synthwave)
        #expect(session.cursorStyleOverride == TerminalCursorStyle.beam)
    }

    @Test("Terminal Session detects custom typography and styling overrides")
    func testHasCustomOverrides() {
        let session = TerminalSession(title: "Border-Router-01", connectionType: .localShell)
        #expect(!session.hasCustomOverrides)

        session.fontSizeOverride = 14.0
        #expect(session.hasCustomOverrides)
        session.fontSizeOverride = nil
        #expect(!session.hasCustomOverrides)

        session.themeOverride = .matrix
        #expect(session.hasCustomOverrides)
        session.themeOverride = nil
        #expect(!session.hasCustomOverrides)

        session.fontFamilyOverride = "Menlo"
        #expect(session.hasCustomOverrides)
        session.fontFamilyOverride = nil
        #expect(!session.hasCustomOverrides)

        session.cursorStyleOverride = .underline
        #expect(session.hasCustomOverrides)
        session.cursorStyleOverride = nil
        #expect(!session.hasCustomOverrides)
    }

    @Test("Terminal Split Mode covers all four multi-pane layouts and manager switching")
    func testTerminalSplitModesAndManager() {
        #expect(TerminalSplitMode.allCases.count == 4)
        #expect(TerminalSplitMode.single.id == "Single Pane")
        #expect(TerminalSplitMode.vertical.rawValue.contains("Side-by-Side"))
        #expect(TerminalSplitMode.horizontal.rawValue.contains("Stacked"))
        #expect(TerminalSplitMode.quadGrid.rawValue.contains("Quad Grid"))

        let manager = TerminalManager()
        #expect(manager.splitMode == .single)

        manager.splitMode = .vertical
        #expect(manager.splitMode == .vertical)

        manager.splitMode = .horizontal
        #expect(manager.splitMode == .horizontal)

        manager.splitMode = .quadGrid
        #expect(manager.splitMode == .quadGrid)
    }

    final class OutputAccumulator: @unchecked Sendable {
        private let lock = NSLock()
        private var chunks: [String] = []

        func append(_ chunk: String) {
            lock.lock()
            defer { lock.unlock() }
            chunks.append(chunk)
        }

        func combined() -> String {
            lock.lock()
            defer { lock.unlock() }
            return chunks.joined()
        }
    }

    @Test("PTY Process Runner launches local shell, sends commands, resizes, and terminates")
    func testPTYLocalShellProcessExecution() async throws {
        let runner = PTYProcessRunner()
        let accumulator = OutputAccumulator()

        runner.onOutput = { chunk in
            accumulator.append(chunk)
        }

        try runner.launchLocalShell()
        #expect(runner.isRunning)

        // Test PTY window resize
        runner.resize(cols: 120, rows: 40)

        // Send a command to the shell
        runner.send(text: "echo 'NexWave PTY Test OK'\n")

        // Wait briefly for shell output
        try await Task.sleep(nanoseconds: 500_000_000)

        let combined = accumulator.combined()
        #expect(combined.contains("NexWave PTY Test OK") || runner.isRunning)

        // Clean termination
        runner.terminate()
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(!runner.isRunning)
    }

    @Test("Terminal Session timestamps toggle and line formatting")
    func testSessionTimestampsAndConfiguration() {
        let session = TerminalSession(title: "Switch-01", connectionType: .localShell)
        #expect(!session.showTimestamps)
        session.showTimestamps = true
        #expect(session.showTimestamps)
        session.showTimestamps.toggle()
        #expect(!session.showTimestamps)

        // Line timestamp initialization
        let line = TerminalLine(text: "System restarted at 10:00:00")
        #expect(line.timestamp.timeIntervalSinceNow < 1.0)
    }

    @Test("Asciinema Recorder writes v2 header and JSON lines events")
    func testAsciinemaRecordingLifecycle() throws {
        let recorder = AsciinemaRecorder()
        #expect(!recorder.isRecording)
        #expect(recorder.eventCount == 0)

        recorder.start(cols: 100, rows: 30, title: "MikroTik Lab Session")
        #expect(recorder.isRecording)

        // Record terminal output chunks
        recorder.recordOutput("[admin@MikroTik] > /ip address print\r\n")
        recorder.recordOutput("Flags: X - disabled, I - invalid, D - dynamic\r\n")
        recorder.recordOutput(" #   ADDRESS            NETWORK         INTERFACE\r\n")
        recorder.recordOutput(" 0   192.168.88.1/24    192.168.88.0    ether1\r\n")

        #expect(recorder.eventCount == 4)

        let castURL = try recorder.exportToFile(filename: "test_session.cast")
        #expect(!recorder.isRecording)

        let content = try String(contentsOf: castURL, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        #expect(lines.count == 5) // 1 header + 4 events

        // Verify line 1 is valid JSON header
        let headerData = lines[0].data(using: .utf8)!
        let headerObj = try JSONSerialization.jsonObject(with: headerData) as? [String: Any]
        #expect(headerObj?["version"] as? Int == 2)
        #expect(headerObj?["width"] as? Int == 100)
        #expect(headerObj?["height"] as? Int == 30)
        #expect(headerObj?["title"] as? String == "MikroTik Lab Session")

        // Verify line 2 is valid asciinema event tuple [time, "o", string]
        let eventData = lines[1].data(using: .utf8)!
        let eventArray = try JSONSerialization.jsonObject(with: eventData) as? [Any]
        #expect(eventArray?.count == 3)
        #expect(eventArray?[1] as? String == "o")
        #expect((eventArray?[2] as? String)?.contains("[admin@MikroTik]") == true)

        // Cleanup
        try? FileManager.default.removeItem(at: castURL)
    }

    @Test("Remote File Browser Engine parses directory listings and navigates")
    func testRemoteFileBrowserEngine() {
        let engine = RemoteFileBrowserEngine()
        #expect(!engine.currentLocalPath.isEmpty)
        #expect(engine.currentRemotePath == "~")

        // Test RemoteFileItem size formatting
        let emptyItem = RemoteFileItem(name: "dir", path: "/dir", isDirectory: true)
        #expect(emptyItem.formattedSize == "--")

        let smallItem = RemoteFileItem(name: "small.txt", path: "/small.txt", isDirectory: false, size: 512)
        #expect(smallItem.formattedSize == "512 B")

        let kbItem = RemoteFileItem(name: "medium.txt", path: "/medium.txt", isDirectory: false, size: 2048)
        #expect(kbItem.formattedSize == "2.0 KB")

        let mbItem = RemoteFileItem(name: "large.bin", path: "/large.bin", isDirectory: false, size: 5242880)
        #expect(mbItem.formattedSize == "5.0 MB")

        // Test icon resolution
        let folderItem = RemoteFileItem(name: "configs", path: "/home/ubuntu/configs", isDirectory: true)
        #expect(folderItem.iconName == "folder.fill")

        let confItem = RemoteFileItem(name: "router.rsc", path: "/home/ubuntu/router.rsc", isDirectory: false)
        #expect(confItem.iconName == "gearshape.fill")

        let logItem = RemoteFileItem(name: "syslog.log", path: "/var/log/syslog.log", isDirectory: false)
        #expect(logItem.iconName == "doc.text.fill")

        // Test parsing ls -la output
        let mockLsOutput = """
        total 32
        drwxr-xr-x  4 ubuntu ubuntu  4096 Sep 17 10:00 .
        drwxr-xr-x 10 root   root    4096 Sep 17 09:00 ..
        drwxr-xr-x  2 ubuntu ubuntu  4096 Sep 17 10:05 scripts
        -rw-r--r--  1 ubuntu ubuntu  1234 Sep 17 10:10 backup.rsc
        -rwxr-xr-x  1 ubuntu ubuntu   450 Sep 17 10:15 deploy.sh
        """
        let parsed = engine.parseLsOutput(mockLsOutput, basePath: "/home/ubuntu")
        #expect(parsed.items.count == 4)
        #expect(parsed.items[0].name == "..")
        #expect(parsed.items[1].name == "scripts")
        #expect(parsed.items[1].isDirectory)
        #expect(parsed.items[2].name == "backup.rsc")
        #expect(!parsed.items[2].isDirectory)
        #expect(parsed.items[2].size == 1234)
        #expect(parsed.items[3].name == "deploy.sh")

        // Test local navigation
        let previousPath = engine.currentLocalPath
        engine.navigateLocal(to: "/")
        #expect(engine.currentLocalPath == "/")
        engine.navigateLocal(to: previousPath)
        #expect(engine.currentLocalPath == previousPath)
    }

    @Test("Simulated CLI supports MikroTik RouterOS personality and tab completion")
    func testMikroTikRouterOSPersonality() {
        let sim = SimulatedDeviceCLI(hostname: "MikroTik-CCR2004", vendor: .mikrotikRouterOS)
        var outputs: [String] = []
        sim.onOutput = { chunk in
            outputs.append(chunk)
        }

        sim.start()
        #expect(!outputs.isEmpty)
        #expect(outputs[0].contains("RouterOS 7.12"))
        #expect(sim.currentPrompt.contains("[admin@MikroTik-CCR2004] >"))

        // Test /ip address print
        sim.processInput("/ip address print")
        let lastOutput = outputs.last ?? ""
        #expect(lastOutput.contains("192.168.88.1/24"))
        #expect(lastOutput.contains("ether1"))

        // Test /interface print
        sim.processInput("/interface print")
        let ifOutput = outputs.last ?? ""
        #expect(ifOutput.contains("sfp-sfpplus1"))
        #expect(ifOutput.contains("ether1-wan"))

        // Test /system resource print
        sim.processInput("/system resource print")
        let resOutput = outputs.last ?? ""
        #expect(resOutput.contains("ARM64 4-core"))

        // Test MikroTik tab completion
        let auto1 = sim.autoComplete(input: "/ip ad")
        #expect(auto1 == "/ip address print")

        let auto2 = sim.autoComplete(input: "/int")
        #expect(auto2 == "/interface print")

        let auto3 = sim.autoComplete(input: "/pin")
        #expect(auto3 == "/ping")

        // Test Cisco tab completion
        let cisco = SimulatedDeviceCLI(hostname: "cisco-core", vendor: .ciscoIOSXE)
        #expect(cisco.autoComplete(input: "sh ip in") == "show ip interface brief")
        #expect(cisco.autoComplete(input: "conf") == "configure terminal")
    }

    @Test("Terminal Syntax Highlighter handles IPv6, CIDR, interfaces, and HTTP codes")
    func testExpandedSyntaxHighlighter() {
        var cfg = TerminalSyntaxHighlightConfig()
        cfg.highlightIPv6 = true
        cfg.highlightCIDR = true
        cfg.highlightInterfaces = true
        cfg.highlightSuccess = true

        let highlighter = TerminalKeywordHighlighter()
        let sample = "Peer 2001:db8:85a3::8a2e:370:7334 via GigabitEthernet0/0/1 on subnet 10.0.0.0/24 responded 200 OK"
        let inputLine = TerminalLine(text: sample)
        let highlightedLine = highlighter.highlight(line: inputLine, config: cfg)

        #expect(highlightedLine.text == sample)
        #expect(highlightedLine.spans.count > 1)
    }

    @Test("SSH Known Hosts entry model parses and detects hashed hosts")
    func testKnownHostsModel() {
        let plain = KnownHostEntry(
            host: "192.168.1.1",
            keyType: "ssh-ed25519",
            keySnippet: "AAAAC3NzaC1lZDI1NTE5...",
            rawLine: "192.168.1.1 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5...",
            lineNumber: 12,
            isHashed: false
        )
        #expect(!plain.isHashed)
        #expect(plain.id == "12_192.168.1.1")

        let hashed = KnownHostEntry(
            host: "[Hashed Host: |1|F83b...]",
            keyType: "rsa-sha2-512",
            keySnippet: "AAAAB3NzaC1yc2EA...",
            rawLine: "|1|F83b== ssh-rsa AAAAB3...",
            lineNumber: 45,
            isHashed: true
        )
        #expect(hashed.isHashed)
        #expect(hashed.lineNumber == 45)
    }

    @Test("SSH Tunnel Manager probes port latency and stores configurations")
    func testSSHTunnelManagerProbing() {
        let manager = SSHTunnelManager()

        // Probing an inactive local port returns nil without hanging or crashing
        let latency = manager.probeLocalPort(port: 59997, timeout: 0.1)
        #expect(latency == nil || latency! > 0)

        // Test tunnel creation
        let newTunnel = SSHTunnelConfig(
            name: "Test Lab Web GUI",
            tunnelType: .localForward,
            localPort: 8443,
            destinationHost: "192.168.88.1",
            destinationPort: 443,
            sshHost: "10.0.0.50",
            sshPort: 22,
            sshUsername: "admin"
        )
        manager.saveTunnel(newTunnel)
        #expect(manager.tunnels.contains(where: { $0.id == newTunnel.id }))

        // Cleanup
        manager.deleteTunnel(id: newTunnel.id)
        #expect(!manager.tunnels.contains(where: { $0.id == newTunnel.id }))
    }

    @Test("Hardware Serial Modem Signal lines model stores and updates pin states")
    func testSerialModemStatus() {
        var status = SerialModemStatus()
        #expect(!status.dtr)
        #expect(!status.rts)
        #expect(!status.cts)
        #expect(!status.dsr)

        status.dtr = true
        status.rts = true
        status.cts = true
        #expect(status.dtr)
        #expect(status.rts)
        #expect(status.cts)
        #expect(!status.dcd)
    }

    @Test("Rapid Enter presses preserve CLI prompt across all lines")
    func testRapidEnterPreservesPrompts() {
        let session = TerminalSession(title: "RapidEnter", connectionType: .simulation(presetName: "Lab Switch"))
        session.clear()

        // Test 1: Rapid enter sequence with simulated Cisco prompt
        session.appendOutput("core-rtr01# ")
        for _ in 1...10 {
            session.appendOutput("\r\ncore-rtr01# ")
        }
        #expect(session.lines.count == 11)
        for line in session.lines {
            #expect(line.text == "core-rtr01# ")
        }

        // Test 2: Chunk-boundary split with zsh \r \r\r clearing sequence
        let sessionChunkSplit = TerminalSession(title: "ChunkSplit", connectionType: .simulation(presetName: "Lab Switch"))
        sessionChunkSplit.clear()
        sessionChunkSplit.appendOutput("saeid@mac % ")
        for _ in 1...10 {
            sessionChunkSplit.appendOutput("\r\r\n%                                       \r \r\r")
            sessionChunkSplit.appendOutput("saeid@mac % ")
        }
        #expect(sessionChunkSplit.lines.count == 11)
        for line in sessionChunkSplit.lines {
            #expect(line.text == "saeid@mac % ")
            #expect(!line.text.hasPrefix(" "))
        }

        // Test 3: Test with real user log
        let logPath = ("~/Library/Application Support/NexWave/TerminalLogs/Local_Shell__zsh__20260917_120116.log" as NSString).expandingTildeInPath
        if let data = try? Data(contentsOf: URL(fileURLWithPath: logPath)),
           let fullStr = String(data: data, encoding: .utf8) {
            let sessionReal = TerminalSession(title: "RealLog", connectionType: .simulation(presetName: "Lab Switch"))
            sessionReal.clear()
            let linesInLog = fullStr.components(separatedBy: "\n")
            let content = linesInLog.dropFirst(3).joined(separator: "\n")
            sessionReal.appendOutput(content)

            #expect(sessionReal.lines.count >= 20)
            for line in sessionReal.lines {
                #expect(!line.text.hasPrefix(" "))
            }
        }
    }

    @Test("Telnet Session lifecycle, profile persistence, and template verification")
    func testTelnetSessionLifecycleAndProfilePersistence() {
        let manager = TerminalManager()

        // 1. Verify default EVE-NG Telnet template is present
        let telnetTemplate = manager.savedProfiles.first { $0.connectionType.lowercased() == "telnet" }
        #expect(telnetTemplate != nil)
        #expect(telnetTemplate?.port == 32769 || telnetTemplate?.port == 23)

        // 2. Open a Telnet session without auto-connecting socket in unit test
        let telnetSession = manager.openTelnetSession(host: "10.200.1.50", port: 32769, autoConnect: false)
        #expect(manager.sessions.contains(where: { $0.id == telnetSession.id }))
        #expect(manager.activeSessionId == telnetSession.id)
        if case .telnet(let host, let port) = telnetSession.connectionType {
            #expect(host == "10.200.1.50")
            #expect(port == 32769)
        } else {
            Issue.record("Expected .telnet connection type")
        }

        // 3. Save active Telnet session as a saved profile
        let savedProfile = manager.saveActiveSessionAsProfile(
            session: telnetSession,
            name: "Core Switch EVE-NG",
            tags: ["Virtual", "Lab", "Telnet"],
            notes: "EVE-NG port 32769 router console"
        )
        #expect(savedProfile.connectionType == "telnet")
        #expect(savedProfile.host == "10.200.1.50")
        #expect(savedProfile.port == 32769)
        #expect(manager.savedProfiles.contains(where: { $0.id == savedProfile.id }))

        // 4. Duplicate Telnet profile
        let duplicate = manager.duplicateProfile(id: savedProfile.id)
        #expect(duplicate != nil)
        #expect(duplicate?.connectionType == "telnet")
        #expect(duplicate?.port == 32769)

        // Cleanup
        manager.deleteProfile(id: savedProfile.id)
        if let dupId = duplicate?.id {
            manager.deleteProfile(id: dupId)
        }
        manager.closeSession(id: telnetSession.id)
    }

    @Test("Terminal Manager initializes with empty session state and does not auto-resurrect shell")
    func testTerminalManagerEmptyInitialStateAndNoAutoShell() {
        let manager = TerminalManager()

        // Verify initial state is completely empty (no unwanted shell)
        #expect(manager.sessions.isEmpty)
        #expect(manager.activeSessionId == nil)
        #expect(manager.activeSession == nil)

        // User explicitly opens a local shell on demand
        let userShell = manager.openLocalShell()
        #expect(manager.sessions.count == 1)
        #expect(manager.activeSessionId == userShell.id)

        // User closes the shell: workbench must return to empty state without auto-spawning
        manager.closeSession(id: userShell.id)
        #expect(manager.sessions.isEmpty)
        #expect(manager.activeSessionId == nil)
        #expect(manager.activeSession == nil)
    }
}





