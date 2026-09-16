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
}

