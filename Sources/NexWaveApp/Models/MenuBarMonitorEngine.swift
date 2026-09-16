import SwiftUI
import Foundation
import WiFiKit
import Darwin

public enum NetworkHealthStatus: String, Sendable {
    case optimal = "Optimal"
    case degraded = "Degraded"
    case offline = "Offline"

    public var colorHex: String {
        switch self {
        case .optimal:  return "#10B981" // Emerald
        case .degraded: return "#F59E0B" // Amber
        case .offline:  return "#EF4444" // Crimson
        }
    }
}

@Observable
public final class MenuBarMonitorEngine: @unchecked Sendable {
    public static let shared = MenuBarMonitorEngine()

    public var activeInterface: String = "en0"
    public var localIP: String = "127.0.0.1"
    public var defaultGateway: String = "127.0.0.1"
    public var dnsServer: String = "1.1.1.1"
    public var gatewayLatencyMs: Double? = nil
    public var internetLatencyMs: Double? = nil
    public var publicIP: String = "Resolving..."
    public var asnName: String = ""
    public var wifiLink: WiFiCurrentLink? = nil
    public var gatewaySamples: [Double] = []
    public var healthStatus: NetworkHealthStatus = .optimal
    public var lastFlushTimestamp: Date? = nil

    private var monitorTask: Task<Void, Never>? = nil
    private var lastPublicIPCheck: Date = .distantPast

    public init() {
        // Fast synchronous discovery of route, local IP, and DNS resolver
        let route = parseDefaultRoute()
        if !route.interface.isEmpty {
            self.activeInterface = route.interface
        }
        if !route.gateway.isEmpty {
            self.defaultGateway = route.gateway
        }
        let ip = queryLocalIP(interface: self.activeInterface)
        if !ip.isEmpty && ip != "127.0.0.1" {
            self.localIP = ip
        }
        let dns = parseSystemDNS()
        if !dns.isEmpty {
            self.dnsServer = dns
        }
    }

    public func startMonitoring() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.performMonitorCycle()
                try? await Task.sleep(nanoseconds: 2_500_000_000) // 2.5s tick
            }
        }
    }

    public func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    @MainActor
    public func performMonitorCycle() async {
        // 1. Detect default gateway and active interface
        let route = parseDefaultRoute()
        if !route.interface.isEmpty {
            self.activeInterface = route.interface
        }
        if !route.gateway.isEmpty {
            self.defaultGateway = route.gateway
        }

        // 2. Query local IP on active interface
        let ip = queryLocalIP(interface: self.activeInterface)
        if !ip.isEmpty && ip != "127.0.0.1" {
            self.localIP = ip
        }

        // 3. Query system DNS
        let dns = parseSystemDNS()
        if !dns.isEmpty {
            self.dnsServer = dns
        }

        // 4. Ping local default gateway
        let gwRTT = await pingHost(host: self.defaultGateway, timeoutMs: 800)
        self.gatewayLatencyMs = gwRTT
        if let rtt = gwRTT {
            self.gatewaySamples.append(rtt)
            if self.gatewaySamples.count > 24 {
                self.gatewaySamples.removeFirst(self.gatewaySamples.count - 24)
            }
        }

        // 5. Ping Internet (1.1.1.1)
        let inetRTT = await pingHost(host: "1.1.1.1", timeoutMs: 900)
        self.internetLatencyMs = inetRTT

        // 6. Evaluate Health Status
        if gwRTT == nil && inetRTT == nil {
            self.healthStatus = .offline
        } else if let gw = gwRTT, gw > 60.0 || inetRTT == nil {
            self.healthStatus = .degraded
        } else {
            self.healthStatus = .optimal
        }

        // 7. Wi-Fi status if interface is Wi-Fi
        if self.activeInterface.starts(with: "en0") {
            let link = await WiFiEngine.shared.fetchCurrentLink(interfaceName: self.activeInterface)
            self.wifiLink = link
        } else {
            self.wifiLink = nil
        }

        // 8. Refresh Public IP periodically (every 5 minutes)
        if Date().timeIntervalSince(lastPublicIPCheck) > 300 {
            lastPublicIPCheck = Date()
            Task {
                await fetchPublicIPDetails()
            }
        }
    }

    /// Performs an instantaneous ping probe using /sbin/ping
    public func pingHost(host: String, timeoutMs: Int = 800) async -> Double? {
        guard !host.isEmpty && host != "127.0.0.1" else { return 0.5 }
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/ping")
        process.arguments = ["-c", "1", "-W", "\(timeoutMs)", host]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return nil }
            return parsePingLatency(output: output)
        } catch {
            return nil
        }
    }

    /// Flushes the macOS DNS cache
    public func flushDNSCache() async -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/dscacheutil")
        process.arguments = ["-flushcache"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            self.lastFlushTimestamp = Date()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    public func fetchPublicIPDetails() async {
        guard let url = URL(string: "https://api.ipify.org?format=text") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3.0

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200,
               let ip = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                await MainActor.run {
                    self.publicIP = ip
                }
            }
        } catch {
            // Keep existing public IP or fallback
        }
    }

    // MARK: - Parsers

    public func parseDefaultRoute() -> (gateway: String, interface: String) {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/route")
        process.arguments = ["-n", "get", "default"]
        process.standardOutput = pipe
        process.standardError = Pipe()

        if let _ = try? process.run() {
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                let details = extractRouteDetails(from: output)
                if !details.gateway.isEmpty {
                    return details
                }
            }
        }

        // Fallback: parse netstat -rn -f inet
        let netstatPipe = Pipe()
        let netstatProc = Process()
        netstatProc.executableURL = URL(fileURLWithPath: "/usr/sbin/netstat")
        netstatProc.arguments = ["-rn", "-f", "inet"]
        netstatProc.standardOutput = netstatPipe
        netstatProc.standardError = Pipe()

        if let _ = try? netstatProc.run() {
            netstatProc.waitUntilExit()
            let data = netstatPipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                for line in output.components(separatedBy: .newlines) {
                    let parts = line.split(whereSeparator: \.isWhitespace)
                    if parts.count >= 4 && parts[0] == "default" {
                        let gw = String(parts[1])
                        let iface = parts.count >= 6 ? String(parts[3]) : (parts.count >= 4 ? String(parts[parts.count - 1]) : "en0")
                        if !gw.starts(with: "link#") {
                            return (gw, iface)
                        }
                    }
                }
            }
        }

        return ("", "en0")
    }

    public func extractRouteDetails(from output: String) -> (gateway: String, interface: String) {
        var gateway = ""
        var iface = ""
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.starts(with: "gateway:") {
                gateway = trimmed.replacingOccurrences(of: "gateway:", with: "").trimmingCharacters(in: .whitespaces)
            } else if trimmed.starts(with: "interface:") {
                iface = trimmed.replacingOccurrences(of: "interface:", with: "").trimmingCharacters(in: .whitespaces)
            }
        }
        return (gateway, iface)
    }

    public func queryLocalIP(interface: String) -> String {
        // 1. Try ipconfig getifaddr
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/ipconfig")
        process.arguments = ["getifaddr", interface]
        process.standardOutput = pipe
        process.standardError = Pipe()

        if let _ = try? process.run() {
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let ip = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !ip.isEmpty {
                return ip
            }
        }

        // 2. Darwin getifaddrs fallback
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return "127.0.0.1" }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let current = ptr {
            let name = String(cString: current.pointee.ifa_name)
            if (name == interface || interface.isEmpty) && current.pointee.ifa_addr != nil && current.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(current.pointee.ifa_addr, socklen_t(current.pointee.ifa_addr.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let ipStr = hostname.withUnsafeBufferPointer { buffer in
                        buffer.baseAddress.map { String(cString: $0) } ?? ""
                    }
                    if !ipStr.isEmpty && ipStr != "127.0.0.1" {
                        return ipStr
                    }
                }
            }
            ptr = current.pointee.ifa_next
        }

        return "127.0.0.1"
    }

    public func parseSystemDNS() -> String {
        if let content = try? String(contentsOfFile: "/etc/resolv.conf", encoding: .utf8) {
            for line in content.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.starts(with: "nameserver ") {
                    let ns = trimmed.replacingOccurrences(of: "nameserver ", with: "").trimmingCharacters(in: .whitespaces)
                    if !ns.isEmpty && !ns.contains(":") { // Prefer clean IPv4
                        return ns
                    }
                }
            }
            for line in content.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.starts(with: "nameserver ") {
                    let ns = trimmed.replacingOccurrences(of: "nameserver ", with: "").trimmingCharacters(in: .whitespaces)
                    if !ns.isEmpty { return ns }
                }
            }
        }
        return "1.1.1.1"
    }

    public func parsePingLatency(output: String) -> Double? {
        // e.g. "64 bytes from 172.16.16.1: icmp_seq=0 ttl=64 time=3.418 ms"
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            if line.contains("time=") {
                let parts = line.components(separatedBy: "time=")
                if parts.count > 1 {
                    let timePart = parts[1].components(separatedBy: " ")[0]
                    return Double(timePart)
                }
            }
        }
        return nil
    }
}
