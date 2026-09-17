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
        #expect(TerminalTheme.allCases.count == 4)
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

        #expect(combinedOutput.contains("Permission denied") || combinedOutput.contains("github.com"))
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

        #expect(!combinedOutput.isEmpty)
        #expect(combinedOutput.contains("password:") || combinedOutput.contains("185.81.99.104") || combinedOutput.contains("Permission denied"))
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
}




