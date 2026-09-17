import Foundation
import Darwin

/// Manages interactive execution of CLI tools (ssh, screen, zsh) attached to a native POSIX pseudo-terminal (PTY)
public final class PTYProcessRunner: @unchecked Sendable {
    private var childPid: pid_t = -1
    private var processSource: DispatchSourceProcess?
    private var masterFd: Int32 = -1
    private var readThread: Thread?
    private var isRunning: Bool = false

    public var onOutput: (@Sendable (String) -> Void)?
    public var onTermination: (@Sendable (Int32) -> Void)?

    public init() {}

    deinit {
        terminate()
    }

    /// Launch a process within an allocated PTY using native forkpty and login_tty
    public func launch(
        executableURL: URL,
        arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        pendingPassword: String? = nil
    ) throws {
        terminate()
        self.pendingPassword = pendingPassword

        var master: Int32 = 0
        let pid = forkpty(&master, nil, nil, nil)
        guard pid >= 0 else {
            throw NSError(
                domain: "PTYProcessRunner",
                code: Int(errno),
                userInfo: [NSLocalizedDescriptionKey: "Failed to fork pseudo-terminal (errno: \(errno))"]
            )
        }

        if pid == 0 {
            // Child process: set environment and execute
            for (key, val) in environment {
                setenv(key, val, 1)
            }

            let allArgs = [executableURL.path] + arguments
            let cArgs = allArgs.map { strdup($0) } + [nil]
            execv(executableURL.path, cArgs)
            _exit(127)
        }

        // Parent process
        self.childPid = pid
        self.masterFd = master
        self.isRunning = true

        // Monitor child process exit via Grand Central Dispatch
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .global(qos: .utility))
        source.setEventHandler { [weak self] in
            var status: Int32 = 0
            waitpid(pid, &status, WNOHANG)
            let exitCode = (status >> 8) & 0xFF
            self?.isRunning = false
            self?.onTermination?(exitCode)
        }
        source.resume()
        self.processSource = source

        // Start non-blocking asynchronous reader thread on master descriptor
        startReaderLoop(fd: master)
    }

    private var pendingPassword: String?

    /// Launch standard SSH session with keepalive, optional identity file, Bastion ProxyJump, and legacy network ciphers
    public func launchSSH(
        host: String,
        port: Int = 22,
        username: String,
        identityFile: String? = nil,
        password: String? = nil,
        jumpHost: SSHJumpConfig? = nil,
        enableLegacyCiphers: Bool = false
    ) throws {
        var args = [
            "-p", "\(port)",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ServerAliveInterval=30",
            "-o", "ServerAliveCountMax=3"
        ]

        // If user specified password without identity file, prioritize password auth to skip rejected key attempts
        if password != nil && identityFile == nil {
            args.append(contentsOf: ["-o", "PreferredAuthentications=password,keyboard-interactive"])
        }

        // Legacy network hardware ciphers for older Cisco/Juniper/HP appliances
        if enableLegacyCiphers {
            args.append(contentsOf: [
                "-o", "PubkeyAcceptedKeyTypes=+ssh-rsa",
                "-o", "HostKeyAlgorithms=+ssh-rsa",
                "-o", "KexAlgorithms=+diffie-hellman-group14-sha1,diffie-hellman-group1-sha1,diffie-hellman-group-exchange-sha1",
                "-o", "Ciphers=+aes128-cbc,aes256-cbc,3des-cbc"
            ])
        }

        // Bastion / Jump Host (ProxyJump)
        if let jump = jumpHost, !jump.host.isEmpty {
            args.append("-J")
            args.append(jump.proxyJumpArgument)
        }

        if let key = identityFile, !key.isEmpty {
            args.append("-i")
            args.append(key)
        }

        args.append("\(username)@\(host)")

        let sshURL = URL(fileURLWithPath: "/usr/bin/ssh")
        try launch(executableURL: sshURL, arguments: args, pendingPassword: password)
    }

    /// Launch direct POSIX serial communication without screen wrapper
    public func launchDirectSerial(
        devicePath: String,
        baudRate: Int = 9600,
        dataBits: Int = 8,
        parity: SerialParity = .none,
        stopBits: Int = 1,
        flowControl: SerialFlowControl = .none
    ) throws {
        terminate()

        let fd = Darwin.open(devicePath, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else {
            throw NSError(
                domain: "PTYProcessRunner",
                code: Int(errno),
                userInfo: [NSLocalizedDescriptionKey: "Failed to open serial port \(devicePath) (errno: \(errno))"]
            )
        }

        var t = termios()
        if tcgetattr(fd, &t) == 0 {
            cfsetspeed(&t, speed_t(baudRate))

            // Character size
            t.c_cflag &= ~tcflag_t(CSIZE)
            t.c_cflag |= (dataBits == 7 ? tcflag_t(CS7) : tcflag_t(CS8))

            // Parity
            switch parity {
            case .none:
                t.c_cflag &= ~tcflag_t(PARENB)
            case .odd:
                t.c_cflag |= tcflag_t(PARENB | PARODD)
            case .even:
                t.c_cflag |= tcflag_t(PARENB)
                t.c_cflag &= ~tcflag_t(PARODD)
            }

            // Stop bits
            if stopBits == 2 {
                t.c_cflag |= tcflag_t(CSTOPB)
            } else {
                t.c_cflag &= ~tcflag_t(CSTOPB)
            }

            // Flow control
            switch flowControl {
            case .none:
                t.c_cflag &= ~tcflag_t(CRTSCTS)
                t.c_iflag &= ~tcflag_t(IXON | IXOFF | IXANY)
            case .rtsCts:
                t.c_cflag |= tcflag_t(CRTSCTS)
                t.c_iflag &= ~tcflag_t(IXON | IXOFF | IXANY)
            case .xonXoff:
                t.c_cflag &= ~tcflag_t(CRTSCTS)
                t.c_iflag |= tcflag_t(IXON | IXOFF | IXANY)
            }

            // Raw terminal mode
            t.c_cflag |= tcflag_t(CREAD | CLOCAL)
            t.c_lflag &= ~tcflag_t(ICANON | ECHO | ECHOE | ISIG)
            t.c_iflag &= ~tcflag_t(IGNBRK | BRKINT | PARMRK | ISTRIP | INLCR | IGNCR | ICRNL)
            t.c_oflag &= ~tcflag_t(OPOST)

            tcsetattr(fd, TCSANOW, &t)
        }

        self.childPid = -1
        self.masterFd = fd
        self.isRunning = true
        startReaderLoop(fd: fd)
    }

    /// Launch local interactive shell (zsh)
    public func launchLocalShell() throws {
        let shellURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh")
        try launch(executableURL: shellURL, arguments: ["-l"])
    }

    /// Synchronize PTY window dimensions (columns and rows)
    public func resize(cols: Int, rows: Int) {
        guard masterFd >= 0 else { return }
        var ws = winsize(
            ws_row: UInt16(clamping: max(1, rows)),
            ws_col: UInt16(clamping: max(1, cols)),
            ws_xpixel: 0,
            ws_ypixel: 0
        )
        _ = ioctl(masterFd, TIOCSWINSZ, &ws)
    }

    /// Send hardware serial break signal (e.g. 250-500ms space state for Cisco ROMMON recovery)
    public func sendBreak(durationMs: Int = 350) {
        guard masterFd >= 0 else { return }
        _ = tcsendbreak(masterFd, 0)
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

    /// Terminate process and clean up descriptors asynchronously without blocking the caller
    public func terminate() {
        isRunning = false
        pendingPassword = nil
        let pid = childPid
        childPid = -1
        let mFd = masterFd
        masterFd = -1
        processSource?.cancel()
        processSource = nil

        // Asynchronously terminate process and close file descriptor to prevent main-thread kernel lock
        DispatchQueue.global(qos: .utility).async {
            if pid > 0 {
                kill(pid, SIGTERM)
                usleep(50_000)
                var status: Int32 = 0
                if waitpid(pid, &status, WNOHANG) == 0 {
                    kill(pid, SIGKILL)
                    waitpid(pid, &status, 0)
                }
            }
            if mFd >= 0 {
                Darwin.close(mFd)
            }
        }
    }

    // MARK: - Background Read Loop

    private func startReaderLoop(fd: Int32) {
        let thread = Thread { [weak self] in
            var buffer = [UInt8](repeating: 0, count: 4096)

            var promptAccumulator = ""

            while let self = self, self.isRunning {
                var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                let pollRes = Darwin.poll(&pfd, 1, 200) // 200ms timeout prevents infinite kernel blocking
                guard self.isRunning else { break }

                if pollRes > 0 {
                    if (pfd.revents & Int16(POLLIN)) != 0 {
                        let bytesRead = Darwin.read(fd, &buffer, buffer.count)
                        if bytesRead > 0 {
                            let data = Data(buffer[0..<bytesRead])
                            if let string = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) {
                                // Check if SSH host is prompting for password and we have a pending credential
                                if let pass = self.pendingPassword, !pass.isEmpty {
                                    promptAccumulator += string
                                    let lower = promptAccumulator.lowercased()
                                    if lower.contains("password:") || lower.contains("password for") || lower.contains("passphrase:") || lower.contains("'s password") {
                                        self.pendingPassword = nil
                                        promptAccumulator = ""
                                        DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) { [weak self] in
                                            self?.send(text: "\(pass)\n")
                                        }
                                    }
                                }

                                self.onOutput?(string)
                            }
                        } else if bytesRead == 0 {
                            // EOF encountered
                            break
                        } else {
                            // Read error (EIO, EBADF upon termination)
                            break
                        }
                    } else if (pfd.revents & (Int16(POLLHUP) | Int16(POLLERR) | Int16(POLLNVAL))) != 0 {
                        // Remote end hung up or descriptor invalidated
                        break
                    }
                } else if pollRes < 0 {
                    if errno == EINTR { continue }
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
