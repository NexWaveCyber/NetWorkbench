import Foundation
import Darwin

/// Manages interactive execution of CLI tools (ssh, screen, zsh) attached to a native POSIX pseudo-terminal (PTY)
public final class PTYProcessRunner: @unchecked Sendable {
    private var process: Process?
    private var masterFd: Int32 = -1
    private var slaveFd: Int32 = -1
    private var masterHandle: FileHandle?
    private var readThread: Thread?
    private var isRunning: Bool = false

    public var onOutput: (@Sendable (String) -> Void)?
    public var onTermination: (@Sendable (Int32) -> Void)?

    public init() {}

    deinit {
        terminate()
    }

    /// Launch a process within an allocated PTY
    public func launch(
        executableURL: URL,
        arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws {
        terminate()

        var master: Int32 = 0
        var slave: Int32 = 0

        // Allocate master/slave pseudo-terminal pair
        guard openpty(&master, &slave, nil, nil, nil) == 0 else {
            throw NSError(
                domain: "PTYProcessRunner",
                code: Int(errno),
                userInfo: [NSLocalizedDescriptionKey: "Failed to allocate pseudo-terminal (errno: \(errno))"]
            )
        }

        self.masterFd = master
        self.slaveFd = slave

        let slaveHandle = FileHandle(fileDescriptor: slave, closeOnDealloc: true)
        let masterHandle = FileHandle(fileDescriptor: master, closeOnDealloc: true)
        self.masterHandle = masterHandle

        let proc = Process()
        proc.executableURL = executableURL
        proc.arguments = arguments
        proc.environment = environment
        proc.standardInput = slaveHandle
        proc.standardOutput = slaveHandle
        proc.standardError = slaveHandle

        proc.terminationHandler = { [weak self] p in
            let status = p.terminationStatus
            self?.isRunning = false
            self?.onTermination?(status)
        }

        try proc.run()
        self.process = proc
        self.isRunning = true

        // Start non-blocking asynchronous reader thread on master descriptor
        startReaderLoop(fd: master)
    }

    /// Launch standard SSH session
    public func launchSSH(host: String, port: Int = 22, username: String, identityFile: String? = nil) throws {
        var args = [
            "-p", "\(port)",
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-o", "LogLevel=ERROR",
            "\(username)@\(host)"
        ]
        if let key = identityFile, !key.isEmpty {
            args.insert(contentsOf: ["-i", key], at: 0)
        }

        let sshURL = URL(fileURLWithPath: "/usr/bin/ssh")
        try launch(executableURL: sshURL, arguments: args)
    }

    /// Launch local interactive shell (zsh)
    public func launchLocalShell() throws {
        let shellURL = URL(fileURLWithPath: "/bin/zsh")
        try launch(executableURL: shellURL, arguments: ["-l"])
    }

    /// Write raw user input string to the terminal master handle
    public func send(text: String) {
        guard let data = text.data(using: .utf8), masterFd >= 0 else { return }
        data.withUnsafeBytes { rawBuffer in
            if let ptr = rawBuffer.baseAddress {
                _ = Darwin.write(masterFd, ptr, rawBuffer.count)
            }
        }
    }

    /// Send standard control key combination (e.g. Ctrl+C = 0x03)
    public func sendControlCharacter(_ charCode: UInt8) {
        guard masterFd >= 0 else { return }
        var byte = charCode
        _ = Darwin.write(masterFd, &byte, 1)
    }

    /// Terminate process and clean up descriptors
    public func terminate() {
        isRunning = false
        if let proc = process, proc.isRunning {
            proc.terminate()
        }
        process = nil

        if masterFd >= 0 {
            close(masterFd)
            masterFd = -1
        }
        if slaveFd >= 0 {
            close(slaveFd)
            slaveFd = -1
        }
        masterHandle = nil
    }

    // MARK: - Background Read Loop

    private func startReaderLoop(fd: Int32) {
        let thread = Thread { [weak self] in
            var buffer = [UInt8](repeating: 0, count: 4096)

            while let self = self, self.isRunning {
                let bytesRead = Darwin.read(fd, &buffer, buffer.count)
                if bytesRead > 0 {
                    let data = Data(buffer[0..<bytesRead])
                    if let string = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) {
                        DispatchQueue.main.async {
                            self.onOutput?(string)
                        }
                    }
                } else if bytesRead == 0 {
                    // EOF encountered
                    break
                } else {
                    // Read error (EIO or EBADF upon termination)
                    break
                }
            }
        }
        thread.name = "PTYProcessReader"
        thread.qualityOfService = .userInteractive
        thread.start()
        self.readThread = thread
    }
}
