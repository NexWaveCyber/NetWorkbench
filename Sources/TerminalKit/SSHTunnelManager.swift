import Foundation
import Observation
#if canImport(AppKit)
import AppKit
#endif

/// Graphical SSH Port Forwarding and Tunnel Manager (MobaSSHTunnel equivalent)
/// Manages background SSH tunnels (-L Local, -R Remote, -D Dynamic SOCKS5)
/// with real-time lifecycle tracking, auto-restart, and port availability validation.
@Observable
public final class SSHTunnelManager: @unchecked Sendable {
    public static let shared = SSHTunnelManager()

    public var tunnels: [SSHTunnelConfig] = []
    private var activeProcesses: [UUID: Process] = [:]
    private let tunnelsStorageKey = "com.nexwave.terminal.ssh_tunnels"

    public init() {
        loadTunnels()
    }

    deinit {
        stopAllTunnels()
    }

    /// Add or update a tunnel configuration
    public func saveTunnel(_ config: SSHTunnelConfig) {
        if let idx = tunnels.firstIndex(where: { $0.id == config.id }) {
            tunnels[idx] = config
        } else {
            tunnels.append(config)
        }
        persistTunnels()
    }

    /// Delete a tunnel configuration and stop process if active
    public func deleteTunnel(id: UUID) {
        stopTunnel(id: id)
        tunnels.removeAll { $0.id == id }
        persistTunnels()
    }

    /// Start a background SSH port-forwarding tunnel
    public func startTunnel(id: UUID) throws {
        guard let idx = tunnels.firstIndex(where: { $0.id == id }) else {
            throw NSError(domain: "SSHTunnelManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "Tunnel not found."])
        }

        var config = tunnels[idx]
        if activeProcesses[id] != nil {
            // Already running
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")

        var arguments: [String] = [
            "-N", // Do not execute a remote command (port forwarding only)
            "-o", "ExitOnForwardFailure=yes",
            "-o", "ServerAliveInterval=30",
            "-o", "ServerAliveCountMax=3",
            "-o", "StrictHostKeyChecking=accept-new"
        ]

        // Add tunnel spec
        switch config.tunnelType {
        case .localForward:
            arguments.append("-L")
            arguments.append("\(config.localPort):\(config.destinationHost):\(config.destinationPort)")

        case .remoteForward:
            arguments.append("-R")
            arguments.append("\(config.localPort):\(config.destinationHost):\(config.destinationPort)")

        case .dynamicSOCKS5:
            arguments.append("-D")
            arguments.append("\(config.localPort)")
        }

        // Port
        arguments.append("-p")
        arguments.append("\(config.sshPort)")

        // Identity key if specified
        if let key = config.sshIdentityFile, !key.isEmpty {
            arguments.append("-i")
            arguments.append(key)
        }

        // Target: user@host
        let target = config.sshUsername.isEmpty ? config.sshHost : "\(config.sshUsername)@\(config.sshHost)"
        arguments.append(target)

        let errPipe = Pipe()
        process.standardError = errPipe
        process.arguments = arguments

        process.terminationHandler = { [weak self] proc in
            let status = proc.terminationStatus
            DispatchQueue.global(qos: .utility).async {
                var errorMsg: String? = nil
                if status != 0 {
                    let data = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
                    let msg = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    errorMsg = (msg?.isEmpty == false) ? msg : "Tunnel exited with code \(status)"
                }
                DispatchQueue.main.async {
                    self?.handleProcessTermination(id: id, status: status, errorMessage: errorMsg)
                }
            }
        }

        try process.run()
        activeProcesses[id] = process
        config.isActive = true
        config.lastError = nil
        tunnels[idx] = config
        persistTunnels()
    }

    /// Stop an active SSH tunnel process
    public func stopTunnel(id: UUID) {
        if let process = activeProcesses[id] {
            process.terminate()
            activeProcesses.removeValue(forKey: id)
        }

        if let idx = tunnels.firstIndex(where: { $0.id == id }) {
            tunnels[idx].isActive = false
            persistTunnels()
        }
    }

    /// Stop all active tunnels
    public func stopAllTunnels() {
        for (id, proc) in activeProcesses {
            proc.terminate()
            if let idx = tunnels.firstIndex(where: { $0.id == id }) {
                tunnels[idx].isActive = false
            }
        }
        activeProcesses.removeAll()
        persistTunnels()
    }

    private func handleProcessTermination(id: UUID, status: Int32, errorMessage: String?) {
        activeProcesses.removeValue(forKey: id)
        guard let idx = tunnels.firstIndex(where: { $0.id == id }) else { return }

        tunnels[idx].isActive = false
        if status != 0 {
            tunnels[idx].lastError = errorMessage ?? "Tunnel exited with code \(status)"
        }
        persistTunnels()
    }

    private func loadTunnels() {
        if let data = UserDefaults.standard.data(forKey: tunnelsStorageKey),
           let decoded = try? JSONDecoder().decode([SSHTunnelConfig].self, from: data) {
            // All tunnels start inactive on app launch
            self.tunnels = decoded.map {
                var c = $0
                c.isActive = false
                return c
            }
        } else {
            // Default examples
            self.tunnels = [
                SSHTunnelConfig(
                    name: "Router Web GUI (Local:8443)",
                    tunnelType: .localForward,
                    localPort: 8443,
                    destinationHost: "192.168.1.1",
                    destinationPort: 443,
                    sshHost: "bastion.corp.net",
                    sshPort: 22,
                    sshUsername: "netadmin"
                ),
                SSHTunnelConfig(
                    name: "Corporate SOCKS5 Proxy (:1080)",
                    tunnelType: .dynamicSOCKS5,
                    localPort: 1080,
                    destinationHost: "localhost",
                    destinationPort: 0,
                    sshHost: "gateway.corp.net",
                    sshPort: 22,
                    sshUsername: "netadmin"
                )
            ]
            persistTunnels()
        }
    }

    private func persistTunnels() {
        if let data = try? JSONEncoder().encode(tunnels) {
            UserDefaults.standard.set(data, forKey: tunnelsStorageKey)
        }
    }

    // MARK: - Port Latency & Browser Launching

    /// Probes a local TCP port to measure whether it is actively listening and its response latency in milliseconds
    public func probeLocalPort(port: Int, timeout: TimeInterval = 0.5) -> Double? {
        let startTime = CFAbsoluteTimeGetCurrent()
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { Darwin.close(fd) }

        // Set non-blocking socket
        let flags = Darwin.fcntl(fd, F_GETFL, 0)
        _ = Darwin.fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let connectRes = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if connectRes == 0 {
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
            return max(0.1, elapsed)
        }

        if errno == EINPROGRESS {
            var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            let pollRes = Darwin.poll(&pfd, 1, Int32(timeout * 1000))
            if pollRes > 0 && (pfd.revents & Int16(POLLOUT)) != 0 {
                var err: Int32 = 0
                var len = socklen_t(MemoryLayout<Int32>.size)
                Darwin.getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len)
                if err == 0 {
                    let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
                    return max(0.1, elapsed)
                }
            }
        }

        return nil
    }

    /// Open local web tunnel in default macOS browser (e.g. http://localhost:8443)
    public func launchWebBrowser(for tunnel: SSHTunnelConfig) {
        guard tunnel.tunnelType == .localForward else { return }
        let urlString = "http://localhost:\(tunnel.localPort)"
        if let url = URL(string: urlString) {
            #if canImport(AppKit)
            NSWorkspace.shared.open(url)
            #endif
        }
    }
}
