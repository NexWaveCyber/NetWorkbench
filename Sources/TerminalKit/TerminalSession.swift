import Foundation
import NetworkCore

/// Represents an active interactive terminal session tab with streaming ANSI SGR rendition and PTY control
@Observable
public final class TerminalSession: Identifiable, @unchecked Sendable {
    public let id: UUID
    public var title: String
    public var connectionType: TerminalConnectionType
    public var status: SessionStatus = .disconnected
    public var lines: [TerminalLine] = []
    public var commandHistory: [String] = []
    public var logFilePath: URL? = nil
    public var showTimestamps: Bool = false
    public var syntaxHighlightConfig: TerminalSyntaxHighlightConfig = TerminalSyntaxHighlightConfig()

    private let maxBufferedLines: Int = 4000
    private var ptyRunner: PTYProcessRunner?
    private var simulatedCLI: SimulatedDeviceCLI?
    private let logQueue = DispatchQueue(label: "com.nexwave.terminal.logging", qos: .utility)

    public init(
        id: UUID = UUID(),
        title: String? = nil,
        connectionType: TerminalConnectionType
    ) {
        self.id = id
        self.connectionType = connectionType
        self.title = title ?? connectionType.title
    }

    /// Start or reconnect the connection session
    public func connect() {
        switch status {
        case .connected, .connecting:
            return
        default:
            break
        }

        ptyRunner?.terminate()
        ptyRunner = nil
        simulatedCLI = nil

        if !lines.isEmpty {
            appendOutput("\n[Reconnecting to \(title)...]\n")
        }
        status = .connecting("Establishing connection...")
        initSessionLogFile()

        switch connectionType {
        case .ssh(let host, let port, let username, let identityFile, let password, let jumpHost, let enableLegacyCiphers):
            let runner = PTYProcessRunner()
            self.ptyRunner = runner

            runner.onOutput = { [weak self] chunk in
                if Thread.isMainThread {
                    self?.appendOutput(chunk)
                } else {
                    DispatchQueue.main.async {
                        self?.appendOutput(chunk)
                    }
                }
            }
            runner.onTermination = { [weak self] code in
                DispatchQueue.main.async {
                    self?.status = .terminated(exitCode: code)
                    self?.appendOutput("\n[Session ended with exit code \(code)]\n")
                    self?.diagnoseTermination(exitCode: code)
                }
            }

            do {
                if let jump = jumpHost, !jump.host.isEmpty {
                    appendOutput("[Routing via Bastion Jump Host: \(jump.proxyJumpArgument)]\n")
                }
                if enableLegacyCiphers {
                    appendOutput("[Legacy Network Hardware Ciphers Active: ssh-rsa, diffie-hellman-group14-sha1]\n")
                }
                try runner.launchSSH(
                    host: host,
                    port: port,
                    username: username,
                    identityFile: identityFile,
                    password: password,
                    jumpHost: jumpHost,
                    enableLegacyCiphers: enableLegacyCiphers
                )
                self.status = .connected
                appendOutput("[Connected to \(username)@\(host):\(port)]\n")
            } catch {
                self.status = .error(error.localizedDescription)
                appendOutput("[Failed to start SSH session: \(error.localizedDescription)]\n")
            }

        case .serial(let path, let baud, let dataBits, let parity, let stopBits):
            let runner = PTYProcessRunner()
            self.ptyRunner = runner

            runner.onOutput = { [weak self] chunk in
                if Thread.isMainThread {
                    self?.appendOutput(chunk)
                } else {
                    DispatchQueue.main.async {
                        self?.appendOutput(chunk)
                    }
                }
            }
            runner.onTermination = { [weak self] code in
                DispatchQueue.main.async {
                    self?.status = .terminated(exitCode: code)
                }
            }

            do {
                // Try direct POSIX serial communication first
                try runner.launchDirectSerial(
                    devicePath: path,
                    baudRate: baud,
                    dataBits: dataBits,
                    parity: parity,
                    stopBits: stopBits
                )
                self.status = .connected
                appendOutput("[Direct POSIX serial session opened on \(path) at \(baud) bps (\(dataBits)\(parity.rawValue.prefix(1))\(stopBits))]\n")
            } catch {
                // Fallback to /usr/bin/screen if direct opening fails
                do {
                    let screenURL = URL(fileURLWithPath: "/usr/bin/screen")
                    try runner.launch(executableURL: screenURL, arguments: [path, "\(baud)"])
                    self.status = .connected
                    appendOutput("[Serial console session opened via screen on \(path) at \(baud) baud]\n")
                } catch {
                    self.status = .error(error.localizedDescription)
                    appendOutput("[Serial error: \(error.localizedDescription)]\n")
                }
            }

        case .telnet(let host, let port):
            let runner = PTYProcessRunner()
            self.ptyRunner = runner

            runner.onOutput = { [weak self] chunk in
                if Thread.isMainThread {
                    self?.appendOutput(chunk)
                } else {
                    DispatchQueue.main.async {
                        self?.appendOutput(chunk)
                    }
                }
            }
            runner.onTermination = { [weak self] code in
                DispatchQueue.main.async {
                    self?.status = .terminated(exitCode: code)
                }
            }

            do {
                let telnetURL = URL(fileURLWithPath: "/usr/bin/nc")
                try runner.launch(executableURL: telnetURL, arguments: [host, "\(port)"])
                self.status = .connected
                appendOutput("[Connected to \(host):\(port) via raw TCP/Telnet]\n")
            } catch {
                self.status = .error(error.localizedDescription)
            }

        case .localShell:
            let runner = PTYProcessRunner()
            self.ptyRunner = runner

            runner.onOutput = { [weak self] chunk in
                if Thread.isMainThread {
                    self?.appendOutput(chunk)
                } else {
                    DispatchQueue.main.async {
                        self?.appendOutput(chunk)
                    }
                }
            }
            runner.onTermination = { [weak self] code in
                DispatchQueue.main.async {
                    self?.status = .terminated(exitCode: code)
                }
            }

            do {
                try runner.launchLocalShell()
                self.status = .connected
            } catch {
                self.status = .error(error.localizedDescription)
            }

        case .simulation(let preset):
            let sim = SimulatedDeviceCLI(presetName: preset)
            self.simulatedCLI = sim

            sim.onOutput = { [weak self] chunk in
                self?.appendOutput(chunk)
            }
            self.status = .connected
            sim.start()
        }
    }

    /// Send a user input line or command to the session
    public func sendCommand(_ command: String) {
        let trimmed = command.trimmingCharacters(in: .newlines)
        let isPassword = lines.last?.text.lowercased().contains("password:") == true ||
                         lines.last?.text.lowercased().contains("password for") == true ||
                         lines.last?.text.lowercased().contains("passphrase:") == true

        if !trimmed.isEmpty {
            if !isPassword {
                commandHistory.append(trimmed)
                // Log command visually with marker
                appendLine(TerminalLine(text: trimmed, isCommandInput: true))
            }
        }

        if let sim = simulatedCLI {
            sim.processInput(trimmed)
        } else if let runner = ptyRunner {
            runner.send(text: "\(trimmed)\r")
        }
    }

    /// Send raw character directly (character-by-character interactive mode)
    public func sendRawCharacter(_ char: Character) {
        let text = String(char)
        if let sim = simulatedCLI {
            if char == "\n" || char == "\r" {
                sim.processInput("")
            } else if char == "?" {
                sim.processInput("?")
            }
        } else if let runner = ptyRunner {
            runner.send(text: text)
        }
    }

    /// Send raw string directly to PTY or simulator without command line formatting
    public func sendRawString(_ text: String) {
        if simulatedCLI != nil {
            for char in text {
                sendRawCharacter(char)
            }
        } else if let runner = ptyRunner {
            runner.send(text: text)
        }
    }

    /// Send raw byte sequence
    public func sendRawBytes(_ bytes: [UInt8]) {
        guard let runner = ptyRunner else { return }
        for b in bytes {
            runner.sendControlCharacter(b)
        }
    }

    /// Send standard control key combination (e.g. Ctrl+C = 0x03, Ctrl+Z = 0x1A)
    public func sendControl(_ charCode: UInt8) {
        if charCode == 0x03 { // Ctrl+C
            appendLine(TerminalLine(text: "^C", isCommandInput: true))
            if let sim = simulatedCLI {
                sim.processInput("")
            }
        }
        ptyRunner?.sendControlCharacter(charCode)
    }

    /// Send hardware serial break signal to trigger Cisco ROMMON mode or loader prompt
    public func sendBreak(durationMs: Int = 350) {
        appendLine(TerminalLine(text: "[>>> SENDING SERIAL HARDWARE BREAK SIGNAL (ROMMON) <<<]", isCommandInput: true))
        ptyRunner?.sendBreak(durationMs: durationMs)
    }

    /// Inform PTY of updated column and row geometry
    public func resize(cols: Int, rows: Int) {
        ptyRunner?.resize(cols: cols, rows: rows)
    }

    /// Disconnect session and release handles
    public func disconnect() {
        ptyRunner?.terminate()
        ptyRunner = nil
        simulatedCLI = nil
        status = .disconnected
        appendOutput("\n[Session disconnected]\n")
    }

    /// Clear output buffer
    public func clear() {
        lines.removeAll()
    }

    /// Filter and search transcript lines by query
    public func searchLines(query: String) -> [TerminalLine] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return lines }
        return lines.filter { $0.text.localizedCaseInsensitiveContains(trimmed) }
    }

    /// Export whole session transcript to plain string
    public func exportTranscript() -> String {
        lines.map { $0.text }.joined(separator: "\n")
    }

    /// Export formatted session log with timestamps and session header
    public func exportSessionLog() -> String {
        let formatter = ISO8601DateFormatter()
        var log = "# NexWave Terminal Session Log\n"
        log += "# Title: \(title)\n"
        log += "# Mode: \(connectionType.title)\n"
        log += "# Exported: \(formatter.string(from: Date()))\n"
        log += "# ------------------------------------------------------------\n\n"
        for line in lines {
            log += "[\(formatter.string(from: line.timestamp))] \(line.text)\n"
        }
        return log
    }

    // MARK: - Output Buffering & Streaming ANSI Parser

    private func appendOutput(_ chunk: String) {
        // Continuous session logging
        writeToLogFile(chunk)

        // Parse chunk into styled lines preserving ANSI SGR color attributes
        let parsed = ANSISGRParser.shared.parseLines(from: chunk)
        for line in parsed {
            appendLine(line)
        }
    }

    private func appendLine(_ line: TerminalLine) {
        let processedLine = TerminalKeywordHighlighter.shared.highlight(line: line, config: syntaxHighlightConfig)
        lines.append(processedLine)
        if lines.count > maxBufferedLines {
            lines.removeFirst(lines.count - maxBufferedLines)
        }
    }

    /// Strip ANSI escape sequences for plain-text search and exports
    public func stripAnsiEscapeSequences(from input: String) -> String {
        let regex = #"\x1B\[[0-9;]*[a-zA-Z]"#
        return input.replacingOccurrences(of: regex, with: "", options: .regularExpression)
    }

    private func diagnoseTermination(exitCode: Int32) {
        guard exitCode != 0 else { return }
        let recentText = lines.suffix(20).map { $0.text }.joined(separator: "\n")
        
        if recentText.contains("Connection refused") {
            appendOutput("[Troubleshooting: Connection refused on port. If connecting to a Linux/Ubuntu server, fail2ban or firewall rate-limiting may have temporarily blocked your IP, or the SSH service is not running on this port.]\n")
        } else if recentText.contains("Permission denied (publickey,password)") || recentText.contains("Permission denied (publickey)") {
            appendOutput("[Troubleshooting: Authentication failed. Modern Ubuntu servers default to 'PermitRootLogin prohibit-password' in /etc/ssh/sshd_config, which disallows root password login. Use SSH Key Studio to generate and deploy an SSH public key, or connect as a standard user.]\n")
        } else if recentText.contains("Could not resolve hostname") {
            appendOutput("[Troubleshooting: Could not resolve hostname. Please verify the host address or domain name.]\n")
        } else if recentText.contains("Operation timed out") || recentText.contains("Connection timed out") {
            appendOutput("[Troubleshooting: Connection timed out. Verify network connectivity and check firewall/security group rules on the server.]\n")
        } else if recentText.contains("Bad key types") {
            appendOutput("[Troubleshooting: OpenSSH rejected incompatible key or cipher flags. Please disable 'Enable Legacy Network Ciphers' when connecting to standard modern Linux servers.]\n")
        }
    }

    // MARK: - Continuous Session Logging

    private func initSessionLogFile() {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let logsDir = appSupport.appendingPathComponent("NexWave/TerminalLogs", isDirectory: true)

        try? fm.createDirectory(at: logsDir, withIntermediateDirectories: true)

        let safeTitle = title.replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression)
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = df.string(from: Date())

        let fileURL = logsDir.appendingPathComponent("\(safeTitle)_\(timestamp).log")
        self.logFilePath = fileURL

        let header = "# NexWave Terminal Session Log Started: \(ISO8601DateFormatter().string(from: Date()))\n# Target: \(title)\n# ------------------------------------------------------------\n"
        try? header.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func writeToLogFile(_ chunk: String) {
        guard let url = logFilePath, let data = chunk.data(using: .utf8) else { return }
        logQueue.async {
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                handle.write(data)
            }
        }
    }
}
