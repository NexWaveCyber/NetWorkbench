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
    public var fontSizeOverride: CGFloat? = nil
    public var fontFamilyOverride: String? = nil
    public var themeOverride: TerminalTheme? = nil
    public var cursorStyleOverride: TerminalCursorStyle? = nil

    public var hasCustomOverrides: Bool {
        fontSizeOverride != nil || fontFamilyOverride != nil || themeOverride != nil || cursorStyleOverride != nil
    }

    public var maxBufferedLines: Int = 5000
    public let recorder: AsciinemaRecorder = AsciinemaRecorder()
    private var ptyRunner: PTYProcessRunner?
    private var simulatedCLI: SimulatedDeviceCLI?
    private let logQueue = DispatchQueue(label: "com.nexwave.terminal.logging", qos: .utility)
    public var isLastLineOpen: Bool = false
    private var activeANSIStyle: ANSIStyle = .default
    private var pendingCR: Bool = false
    private static let crlfSequenceRegex = try! NSRegularExpression(pattern: "\\r+\\n")

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
                    self?.appendOutput("\n[Telnet session disconnected (exit code: \(code))]\n")
                }
            }

            do {
                try runner.launchTelnet(host: host, port: port)
                self.status = .connected
                let hasTelnetBin = FileManager.default.fileExists(atPath: "/opt/homebrew/bin/telnet")
                    || FileManager.default.fileExists(atPath: "/usr/local/bin/telnet")
                    || FileManager.default.fileExists(atPath: "/usr/bin/telnet")
                let driver = hasTelnetBin ? "Standard Telnet (RFC 854)" : "Raw TCP Stream Engine"
                appendOutput("[Connected to \(host):\(port) via \(driver)]\n")
            } catch {
                self.status = .error(error.localizedDescription)
                appendOutput("[Telnet connection error: \(error.localizedDescription)]\n")
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

    /// Indicates whether the session is actively prompting for a password or passphrase
    public var isAwaitingPasswordPrompt: Bool {
        guard simulatedCLI == nil else { return false }
        for line in lines.suffix(4).reversed() {
            let trimmed = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            let lower = trimmed.lowercased()
            if lower.contains("[verified]") { return false }
            if lower.hasSuffix("password:") || lower.hasSuffix("passphrase:") || lower.contains("'s password:") || lower.hasSuffix("password") {
                return true
            }
            break
        }
        return false
    }

    /// Send a user input line or command to the session
    public func sendCommand(_ command: String) {
        let trimmed = command.trimmingCharacters(in: .newlines)
        let isPassword = isAwaitingPasswordPrompt

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
            let terminator = isPassword ? "\n" : "\r"
            runner.send(text: "\(trimmed)\(terminator)")
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

    /// Query hardware serial modem status lines (DTR, RTS, CTS, DSR, CD, RI)
    public func queryModemStatus() -> SerialModemStatus? {
        ptyRunner?.queryModemStatus()
    }

    /// Set or clear DTR / RTS hardware control lines
    public func setModemSignal(dtr: Bool? = nil, rts: Bool? = nil) {
        ptyRunner?.setModemSignal(dtr: dtr, rts: rts)
    }

    /// Inject raw hexadecimal byte sequence
    public func sendHexBytes(_ bytes: [UInt8]) {
        ptyRunner?.sendHexBytes(bytes)
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
        isLastLineOpen = false
        activeANSIStyle = .default
        pendingCR = false
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

    // MARK: - Asciinema Session Recording

    public var isRecording: Bool {
        recorder.isRecording
    }

    public func startRecording(cols: Int = 80, rows: Int = 24) {
        recorder.start(cols: cols, rows: rows, title: title)
    }

    public func stopRecording() -> String {
        recorder.stop()
    }

    public func exportRecording() throws -> URL {
        let safeName = title.replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression)
        return try recorder.exportToFile(filename: "\(safeName)_\(Int(Date().timeIntervalSince1970)).cast")
    }

    // MARK: - Output Buffering & Streaming ANSI Parser

    public func appendOutput(_ chunk: String) {
        // Continuous session logging
        writeToLogFile(chunk)
        if recorder.isRecording {
            recorder.recordOutput(chunk)
        }
        guard !chunk.isEmpty else { return }

        var raw = chunk

        var hadPendingCR = false

        // Handle CR split across chunk boundary: if previous chunk ended with \r
        if pendingCR {
            pendingCR = false
            // Strip any additional \r that precedes a \n across the chunk boundary
            var testRaw = raw
            while testRaw.hasPrefix("\r") {
                testRaw.removeFirst()
            }
            if testRaw.hasPrefix("\n") {
                // The pending \r (and any further \r) followed by \n formed a newline!
                testRaw.removeFirst()
                raw = testRaw
                if isLastLineOpen {
                    isLastLineOpen = false
                } else {
                    appendEmptyLine()
                }
                guard !raw.isEmpty else { return }
            } else {
                // Standalone carriage return across chunk boundary:
                // The cursor returned to column 0 at the end of the previous chunk.
                // The first line segment of this incoming chunk must overwrite from column 0!
                hadPendingCR = true
            }
        }

        // Check if current chunk ends with one or more trailing \r that might form \r+\n in next chunk
        var trailingCR = 0
        while raw.hasSuffix("\r") {
            trailingCR += 1
            raw.removeLast()
        }
        if trailingCR > 0 {
            pendingCR = true
            if raw.isEmpty { return }
        }

        // Normalize any \r+\n sequence into a single \n newline.
        // In network, PTY, and serial streams, any sequence of CRs followed by LF is a single line break.
        if raw.contains("\r\n") || raw.contains("\r") {
            raw = Self.crlfSequenceRegex.stringByReplacingMatches(
                in: raw,
                range: NSRange(location: 0, length: raw.utf16.count),
                withTemplate: "\n"
            )
        }

        let endsInNewline = raw.hasSuffix("\n")
        var rawComponents = raw.components(separatedBy: "\n")

        if endsInNewline && !rawComponents.isEmpty && rawComponents.last == "" {
            rawComponents.removeLast()
        }
        guard !rawComponents.isEmpty else {
            if endsInNewline {
                if isLastLineOpen {
                    isLastLineOpen = false
                } else {
                    appendEmptyLine()
                }
            }
            return
        }

        for (index, rawComp) in rawComponents.enumerated() {
            let isTerminated = (index < rawComponents.count - 1) || endsInNewline
            let isFirstSegmentAfterPendingCR = (index == 0 && hadPendingCR)
            processLineSegment(rawComp, isTerminated: isTerminated, isFirstSegmentAfterPendingCR: isFirstSegmentAfterPendingCR)
        }

        // Amortized trimming: trim excess in proportional batches to eliminate O(N) shifts on every line
        let excessThreshold = max(20, min(200, maxBufferedLines / 10))
        if lines.count > maxBufferedLines + excessThreshold {
            lines.removeFirst(lines.count - maxBufferedLines)
        }
    }

    private func processLineSegment(_ rawComp: String, isTerminated: Bool, isFirstSegmentAfterPendingCR: Bool = false) {
        var comp = rawComp.replacingOccurrences(of: "\u{08} \u{08}", with: "\u{08}")

        // Check for carriage return within segment or carried over from chunk boundary
        let hasCR = comp.contains("\r") || isFirstSegmentAfterPendingCR
        if comp.contains("\r") {
            // In terminal output, \r returns cursor to column 0.
            // If the segment has text overwritten via multiple \r (e.g., "%   \r \r\rsaeid@mac % "),
            // we resolve to the last non-empty segment, discarding pure-whitespace erase tokens before \r.
            let parts = comp.components(separatedBy: "\r")
            let nonEmpties = parts.filter { !$0.isEmpty }
            if let last = nonEmpties.last {
                if last.trimmingCharacters(in: .whitespaces).isEmpty && nonEmpties.count > 1 {
                    comp = ""
                } else {
                    comp = last
                }
            } else {
                comp = ""
            }
        }

        let (leadingBackspaces, resolvedText) = resolveBackspaces(in: comp)

        if isLastLineOpen && !lines.isEmpty {
            let lastIndex = lines.count - 1
            let existingLine = lines[lastIndex]

            // If existing line only contains erase/placeholder whitespace (e.g. " " from zsh \r \r),
            // or if a carriage return occurred: overwrite from column 0!
            let isExistingOnlyWhitespace = existingLine.text.trimmingCharacters(in: .whitespaces).isEmpty && !existingLine.text.isEmpty
            let shouldOverwriteFromCol0 = hasCR || isExistingOnlyWhitespace

            if shouldOverwriteFromCol0 && !resolvedText.isEmpty {
                // Standalone \r or carriage return reset followed by new text: overwrite line from column 0
                let (newSpans, updatedStyle) = ANSISGRParser.shared.parseSpans(from: resolvedText, initialStyle: .default)
                self.activeANSIStyle = updatedStyle
                let plainText = newSpans.map(\.text).joined()
                let updatedLine = TerminalLine(
                    id: existingLine.id,
                    text: plainText,
                    spans: newSpans,
                    isCommandInput: existingLine.isCommandInput,
                    timestamp: existingLine.timestamp
                )
                let highlighted = syntaxHighlightConfig.isEnabled ?
                    TerminalKeywordHighlighter.shared.highlight(line: updatedLine, config: syntaxHighlightConfig) : updatedLine
                lines[lastIndex] = highlighted
            } else if shouldOverwriteFromCol0 && resolvedText.isEmpty {
                // Standalone \r without new text: cursor returns to column 0, leaving existing text intact
            } else {
                var currentText = existingLine.text
                var currentSpans = existingLine.spans
                if leadingBackspaces > 0 {
                    let removeCount = min(leadingBackspaces, currentText.count)
                    currentText = String(currentText.dropLast(removeCount))
                    currentSpans = trimSpans(currentSpans, count: removeCount)
                }

                if !resolvedText.isEmpty {
                    let (newSpans, updatedStyle) = ANSISGRParser.shared.parseSpans(from: resolvedText, initialStyle: activeANSIStyle)
                    self.activeANSIStyle = updatedStyle
                    let mergedSpans = mergeSpans(existing: currentSpans, appending: newSpans)
                    let updatedText = currentText + newSpans.map(\.text).joined()
                    let updatedLine = TerminalLine(
                        id: existingLine.id,
                        text: updatedText,
                        spans: mergedSpans,
                        isCommandInput: existingLine.isCommandInput,
                        timestamp: existingLine.timestamp
                    )
                    let highlighted = syntaxHighlightConfig.isEnabled ?
                        TerminalKeywordHighlighter.shared.highlight(line: updatedLine, config: syntaxHighlightConfig) : updatedLine
                    lines[lastIndex] = highlighted
                } else if leadingBackspaces > 0 {
                    let updatedLine = TerminalLine(
                        id: existingLine.id,
                        text: currentText,
                        spans: currentSpans,
                        isCommandInput: existingLine.isCommandInput,
                        timestamp: existingLine.timestamp
                    )
                    lines[lastIndex] = updatedLine
                }
            }

            if isTerminated {
                isLastLineOpen = false
            }
        } else {
            // New line
            if resolvedText.isEmpty && !isTerminated && lines.isEmpty {
                return
            }

            let (spans, updatedStyle) = ANSISGRParser.shared.parseSpans(from: resolvedText, initialStyle: activeANSIStyle)
            self.activeANSIStyle = updatedStyle
            let plainText = spans.map(\.text).joined()
            let newLine = TerminalLine(text: plainText, spans: spans)
            let highlighted = syntaxHighlightConfig.isEnabled ?
                TerminalKeywordHighlighter.shared.highlight(line: newLine, config: syntaxHighlightConfig) : newLine
            lines.append(highlighted)

            isLastLineOpen = !isTerminated
        }
    }

    private func appendEmptyLine() {
        let emptyLine = TerminalLine(text: "", spans: [ANSISpan(text: "")])
        lines.append(emptyLine)
        isLastLineOpen = false
    }

    private func mergeSpans(existing: [ANSISpan], appending newSpans: [ANSISpan]) -> [ANSISpan] {
        guard !newSpans.isEmpty else { return existing }
        guard !existing.isEmpty else { return newSpans }

        var result = existing
        for newSpan in newSpans {
            guard !newSpan.text.isEmpty else { continue }
            if let last = result.last, last.style == newSpan.style {
                result[result.count - 1] = ANSISpan(
                    id: last.id,
                    text: last.text + newSpan.text,
                    style: last.style
                )
            } else {
                result.append(newSpan)
            }
        }
        return result
    }

    private func trimSpans(_ spans: [ANSISpan], count: Int) -> [ANSISpan] {
        var toRemove = count
        var result = spans

        while toRemove > 0 && !result.isEmpty {
            let last = result.removeLast()
            if last.text.count <= toRemove {
                toRemove -= last.text.count
            } else {
                let newText = String(last.text.dropLast(toRemove))
                result.append(ANSISpan(id: last.id, text: newText, style: last.style))
                toRemove = 0
            }
        }
        return result
    }

    private func resolveBackspaces(in text: String) -> (leadingBackspaces: Int, resolvedText: String) {
        var leading = 0
        var chars: [Character] = []
        for ch in text {
            if ch == "\u{08}" || ch == "\u{7F}" {
                if !chars.isEmpty {
                    chars.removeLast()
                } else {
                    leading += 1
                }
            } else {
                chars.append(ch)
            }
        }
        return (leading, String(chars))
    }

    public func appendLine(_ line: TerminalLine) {
        let processed = syntaxHighlightConfig.isEnabled ?
            TerminalKeywordHighlighter.shared.highlight(line: line, config: syntaxHighlightConfig) : line
        lines.append(processed)
        isLastLineOpen = false
        let excessThreshold = max(20, min(200, maxBufferedLines / 10))
        if lines.count > maxBufferedLines + excessThreshold {
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
