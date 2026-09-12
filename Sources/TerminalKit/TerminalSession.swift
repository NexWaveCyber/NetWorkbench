import Foundation
import NetworkCore

/// Represents an active interactive terminal session tab with line buffering and ANSI handling
@Observable
public final class TerminalSession: Identifiable, @unchecked Sendable {
    public let id: UUID
    public var title: String
    public let connectionType: TerminalConnectionType
    public var status: SessionStatus = .disconnected
    public var lines: [TerminalLine] = []
    public var commandHistory: [String] = []

    private let maxBufferedLines: Int = 3000
    private var ptyRunner: PTYProcessRunner?
    private var simulatedCLI: SimulatedDeviceCLI?

    public init(
        id: UUID = UUID(),
        title: String? = nil,
        connectionType: TerminalConnectionType
    ) {
        self.id = id
        self.connectionType = connectionType
        self.title = title ?? connectionType.title
    }

    /// Start the connection session
    public func connect() {
        guard status == .disconnected || status == .terminated(exitCode: 0) else { return }
        status = .connecting("Establishing connection...")

        switch connectionType {
        case .ssh(let host, let port, let username, let identityFile):
            let runner = PTYProcessRunner()
            self.ptyRunner = runner

            runner.onOutput = { [weak self] chunk in
                self?.appendOutput(chunk)
            }
            runner.onTermination = { [weak self] code in
                DispatchQueue.main.async {
                    self?.status = .terminated(exitCode: code)
                    self?.appendOutput("\n[Session ended with exit code \(code)]\n")
                }
            }

            do {
                try runner.launchSSH(host: host, port: port, username: username, identityFile: identityFile)
                self.status = .connected
                appendOutput("[Connected to \(username)@\(host):\(port)]\n")
            } catch {
                self.status = .error(error.localizedDescription)
                appendOutput("[Failed to start SSH session: \(error.localizedDescription)]\n")
            }

        case .serial(let path, let baud, _, _, _):
            let runner = PTYProcessRunner()
            self.ptyRunner = runner

            runner.onOutput = { [weak self] chunk in
                self?.appendOutput(chunk)
            }
            runner.onTermination = { [weak self] code in
                DispatchQueue.main.async {
                    self?.status = .terminated(exitCode: code)
                }
            }

            do {
                // On macOS, `/usr/bin/screen <path> <baud>` is the standard POSIX console wrapper
                let screenURL = URL(fileURLWithPath: "/usr/bin/screen")
                try runner.launch(executableURL: screenURL, arguments: [path, "\(baud)"])
                self.status = .connected
                appendOutput("[Serial console session opened on \(path) at \(baud) baud]\n")
            } catch {
                self.status = .error(error.localizedDescription)
                appendOutput("[Serial error: \(error.localizedDescription)]\n")
            }

        case .telnet(let host, let port):
            let runner = PTYProcessRunner()
            self.ptyRunner = runner

            runner.onOutput = { [weak self] chunk in
                self?.appendOutput(chunk)
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
                self?.appendOutput(chunk)
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
            let sim = SimulatedDeviceCLI(hostname: preset.lowercased().replacingOccurrences(of: " ", with: "-"))
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
        if !trimmed.isEmpty {
            commandHistory.append(trimmed)
            // Log command visually with marker
            appendLine(TerminalLine(text: trimmed, isCommandInput: true))
        }

        if let sim = simulatedCLI {
            sim.processInput(trimmed)
        } else if let runner = ptyRunner {
            runner.send(text: "\(trimmed)\r")
        }
    }

    /// Send raw character (e.g. Ctrl+C = 0x03)
    public func sendControl(_ charCode: UInt8) {
        if charCode == 0x03 { // Ctrl+C
            appendLine(TerminalLine(text: "^C", isCommandInput: true))
            if let sim = simulatedCLI {
                sim.processInput("")
            }
        }
        ptyRunner?.sendControlCharacter(charCode)
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

    /// Export whole session transcript to string
    public func exportTranscript() -> String {
        lines.map { $0.text }.joined(separator: "\n")
    }

    // MARK: - Output Buffering & Parsing

    private func appendOutput(_ chunk: String) {
        // Strip ANSI cursor control characters while preserving lines
        let clean = stripAnsiEscapeSequences(from: chunk)
        let splitLines = clean.components(separatedBy: "\n")

        for line in splitLines {
            let sanitized = line.replacingOccurrences(of: "\r", with: "")
            if !sanitized.isEmpty {
                appendLine(TerminalLine(text: sanitized))
            }
        }
    }

    private func appendLine(_ line: TerminalLine) {
        lines.append(line)
        if lines.count > maxBufferedLines {
            lines.removeFirst(lines.count - maxBufferedLines)
        }
    }

    /// Clean ANSI escape sequences for smooth rendering
    public func stripAnsiEscapeSequences(from input: String) -> String {
        // Matches standard CSI escape codes: ESC [ ... [a-zA-Z]
        let regex = #"\x1B\[[0-9;]*[a-zA-Z]"#
        return input.replacingOccurrences(of: regex, with: "", options: .regularExpression)
    }
}
