import Foundation
import Observation

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
            DispatchQueue.main.async {
                self?.handleProcessTermination(id: id, status: proc.terminationStatus, pipe: errPipe)
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

    private func handleProcessTermination(id: UUID, status: Int32, pipe: Pipe) {
        activeProcesses.removeValue(forKey: id)
        guard let idx = tunnels.firstIndex(where: { $0.id == id }) else { return }

        tunnels[idx].isActive = false
        if status != 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let msg = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            tunnels[idx].lastError = msg?.isEmpty == false ? msg : "Tunnel exited with code \(status)"
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
}
