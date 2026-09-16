import SwiftUI
import Foundation
import WiFiKit
import Darwin
import SystemConfiguration

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
    public var defaultGatewayIPv6: String = ""
    public var dnsServer: String = ""
    public var dnsServerIPv6: String = ""
    public var allDnsServers: [String] = []
    public var gatewayLatencyMs: Double? = nil
    public var gatewayIPv6LatencyMs: Double? = nil
    public var internetLatencyMs: Double? = nil
    public var publicIP: String = "Resolving..."
    public var publicIPv4: String = "Resolving..."
    public var publicIPv6: String = "Resolving..."
    public var localIPv6: String = ""
    public var hasIPv6: Bool = false
    public var asnName: String = ""
    public var wifiLink: WiFiCurrentLink? = nil
    public var gatewaySamples: [Double] = []
    public var healthStatus: NetworkHealthStatus = .optimal
    public var lastFlushTimestamp: Date? = nil

    public var dnsResolverName: String {
        guard !dnsServer.isEmpty else { return "Unassigned" }
        if dnsServer.starts(with: "1.1.1.") || dnsServer.starts(with: "1.0.0.") {
            return "Cloudflare"
        } else if dnsServer.starts(with: "8.8.8.") || dnsServer.starts(with: "8.8.4.") {
            return "Google DNS"
        } else if dnsServer.starts(with: "9.9.9.") || dnsServer.starts(with: "149.112.112.") {
            return "Quad9"
        } else if dnsServer.starts(with: "208.67.222.") || dnsServer.starts(with: "208.67.220.") {
            return "OpenDNS"
        } else if !defaultGateway.isEmpty && dnsServer == defaultGateway {
            return "Router DNS"
        } else if dnsServer.contains(":") {
            return "IPv6 DNS"
        } else {
            return "System DNS"
        }
    }

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
        if !dns.primary.isEmpty {
            self.dnsServer = dns.primary
            self.allDnsServers = dns.all
        }
        if let v6DNS = dns.all.first(where: { $0.contains(":") }) {
            self.dnsServerIPv6 = v6DNS
        }
        let v6 = queryLocalIPv6(interface: self.activeInterface)
        if !v6.isEmpty {
            self.localIPv6 = v6
            self.hasIPv6 = true
        }
        let gw6 = parseDefaultRouteIPv6()
        if !gw6.isEmpty {
            self.defaultGatewayIPv6 = gw6
        }
        Task { [weak self] in
            await self?.fetchPublicIPDetails()
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
        let v6 = queryLocalIPv6(interface: self.activeInterface)
        if !v6.isEmpty {
            self.localIPv6 = v6
            self.hasIPv6 = true
        }

        // 3. Query system DNS
        let dns = parseSystemDNS()
        if !dns.primary.isEmpty {
            self.dnsServer = dns.primary
            self.allDnsServers = dns.all
        }
        if let v6DNS = dns.all.first(where: { $0.contains(":") }) {
            self.dnsServerIPv6 = v6DNS
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

        // 5. Query & Ping IPv6 Default Gateway
        let gw6 = parseDefaultRouteIPv6()
        if !gw6.isEmpty {
            self.defaultGatewayIPv6 = gw6
            self.gatewayIPv6LatencyMs = await pingHostIPv6(host: gw6, interface: self.activeInterface)
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

    /// Performs an instantaneous IPv6 ping probe using /sbin/ping6
    public func pingHostIPv6(host: String, interface: String, timeoutMs: Int = 800) async -> Double? {
        guard !host.isEmpty else { return nil }
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/ping6")
        process.arguments = ["-c", "1", "-I", interface, host]
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
        let v4Endpoints = ["https://api.ipify.org?format=text", "https://v4.ident.me", "https://ipv4.icanhazip.com"]
        let v6Endpoints = ["https://api6.ipify.org?format=text", "https://v6.ident.me", "https://ipv6.icanhazip.com"]

        async let fetchV4: String? = {
            for ep in v4Endpoints {
                guard let url = URL(string: ep) else { continue }
                var req = URLRequest(url: url)
                req.timeoutInterval = 3.0
                if let (data, resp) = try? await URLSession.shared.data(for: req),
                   let http = resp as? HTTPURLResponse, http.statusCode == 200,
                   let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !text.isEmpty && !text.contains(":") {
                    return text
                }
            }
            return nil
        }()

        async let fetchV6: String? = {
            for ep in v6Endpoints {
                guard let url = URL(string: ep) else { continue }
                var req = URLRequest(url: url)
                req.timeoutInterval = 3.0
                if let (data, resp) = try? await URLSession.shared.data(for: req),
                   let http = resp as? HTTPURLResponse, http.statusCode == 200,
                   let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !text.isEmpty && text.contains(":") {
                    return text
                }
            }
            return nil
        }()

        let (resV4, resV6) = await (fetchV4, fetchV6)

        await MainActor.run {
            if let v4 = resV4 {
                self.publicIPv4 = v4
                self.publicIP = v4
            } else if self.publicIPv4 == "Resolving..." {
                self.publicIPv4 = "Unavailable"
            }

            if let v6 = resV6 {
                self.publicIPv6 = v6
                self.hasIPv6 = true
            } else {
                if self.localIPv6.isEmpty {
                    self.publicIPv6 = "Not Configured"
                } else if self.publicIPv6 == "Resolving..." {
                    self.publicIPv6 = "No Global Route"
                }
            }
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
                let lines = output.components(separatedBy: .newlines)
                for line in lines {
                    let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                    if parts.count >= 6 && parts[0] == "default" {
                        let gateway = String(parts[1])
                        let iface = String(parts[5])
                        if !gateway.isEmpty {
                            return (gateway, iface)
                        }
                    }
                }
            }
        }

        return ("", "en0")
    }

    public func parseDefaultRouteIPv6() -> String {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/route")
        process.arguments = ["-n", "get", "-inet6", "default"]
        process.standardOutput = pipe
        process.standardError = Pipe()

        if let _ = try? process.run() {
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                for line in output.components(separatedBy: .newlines) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.starts(with: "gateway:") {
                        let gw = trimmed.replacingOccurrences(of: "gateway:", with: "").trimmingCharacters(in: .whitespaces)
                        return gw.components(separatedBy: "%")[0]
                    }
                }
            }
        }

        // Fallback: netstat -rn -f inet6
        let netstatPipe = Pipe()
        let netstatProc = Process()
        netstatProc.executableURL = URL(fileURLWithPath: "/usr/sbin/netstat")
        netstatProc.arguments = ["-rn", "-f", "inet6"]
        netstatProc.standardOutput = netstatPipe
        netstatProc.standardError = Pipe()

        if let _ = try? netstatProc.run() {
            netstatProc.waitUntilExit()
            let data = netstatPipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                for line in output.components(separatedBy: .newlines) {
                    let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                    if parts.count >= 4 && parts[0] == "default" {
                        let gw = String(parts[1])
                        return gw.components(separatedBy: "%")[0]
                    }
                }
            }
        }

        return ""
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

    public func queryLocalIPv6(interface: String) -> String {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return "" }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let current = ptr {
            let name = String(cString: current.pointee.ifa_name)
            if (name == interface || interface.isEmpty) && current.pointee.ifa_addr != nil && current.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET6) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(current.pointee.ifa_addr, socklen_t(current.pointee.ifa_addr.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let ipStr = hostname.withUnsafeBufferPointer { buffer in
                        buffer.baseAddress.map { String(cString: $0) } ?? ""
                    }
                    if !ipStr.isEmpty && !ipStr.starts(with: "fe80") && !ipStr.starts(with: "::1") {
                        return ipStr.components(separatedBy: "%")[0]
                    }
                }
            }
            ptr = current.pointee.ifa_next
        }
        return ""
    }

    public func parseSystemDNS() -> (primary: String, all: [String]) {
        // 1. Authoritative macOS SystemConfiguration SCDynamicStore query (in-memory configd state)
        if let store = SCDynamicStoreCreate(nil, "NexWaveDNS" as CFString, nil, nil),
           let dnsDict = SCDynamicStoreCopyValue(store, "State:/Network/Global/DNS" as CFString) as? [String: Any],
           let servers = dnsDict["ServerAddresses"] as? [String], !servers.isEmpty {
            let ipv4s = servers.filter { !$0.contains(":") }
            let primary = ipv4s.first ?? servers.first ?? ""
            return (primary, servers)
        }

        // 2. /etc/resolv.conf fallback
        if let content = try? String(contentsOfFile: "/etc/resolv.conf", encoding: .utf8) {
            var servers: [String] = []
            for line in content.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.starts(with: "nameserver ") {
                    let ns = trimmed.replacingOccurrences(of: "nameserver ", with: "").trimmingCharacters(in: .whitespaces)
                    if !ns.isEmpty && !servers.contains(ns) {
                        servers.append(ns)
                    }
                }
            }
            if !servers.isEmpty {
                let ipv4s = servers.filter { !$0.contains(":") }
                let primary = ipv4s.first ?? servers.first ?? ""
                return (primary, servers)
            }
        }

        return ("", [])
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
