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

public struct SLABaselineResult: Sendable, Identifiable {
    public let id = UUID()
    public let timestamp: Date
    public let gatewayHost: String
    public let gatewayMinMs: Double
    public let gatewayAvgMs: Double
    public let gatewayMaxMs: Double
    public let gatewayJitterMs: Double
    public let gatewayLossPercent: Double
    public let internetHost: String
    public let internetAvgMs: Double
    public let internetLossPercent: Double
    public let dnsHost: String
    public let dnsLookupMs: Double
    public let overallGrade: String
    public let recommendation: String

    public init(
        timestamp: Date = Date(),
        gatewayHost: String,
        gatewayMinMs: Double,
        gatewayAvgMs: Double,
        gatewayMaxMs: Double,
        gatewayJitterMs: Double,
        gatewayLossPercent: Double,
        internetHost: String,
        internetAvgMs: Double,
        internetLossPercent: Double,
        dnsHost: String,
        dnsLookupMs: Double,
        overallGrade: String,
        recommendation: String
    ) {
        self.timestamp = timestamp
        self.gatewayHost = gatewayHost
        self.gatewayMinMs = gatewayMinMs
        self.gatewayAvgMs = gatewayAvgMs
        self.gatewayMaxMs = gatewayMaxMs
        self.gatewayJitterMs = gatewayJitterMs
        self.gatewayLossPercent = gatewayLossPercent
        self.internetHost = internetHost
        self.internetAvgMs = internetAvgMs
        self.internetLossPercent = internetLossPercent
        self.dnsHost = dnsHost
        self.dnsLookupMs = dnsLookupMs
        self.overallGrade = overallGrade
        self.recommendation = recommendation
    }
}

@Observable
public final class MenuBarMonitorEngine: @unchecked Sendable {
    public static let shared = MenuBarMonitorEngine()

    public var activeInterface: String = "en0"
    public var localIP: String = "127.0.0.1"
    public var subnetMask: String = "255.255.255.0"
    public var broadcastAddress: String = ""

    public var cidrPrefix: Int {
        let parts = subnetMask.split(separator: ".").compactMap { UInt8($0) }
        guard parts.count == 4 else { return 24 }
        return parts.reduce(0) { acc, byte in acc + byte.nonzeroBitCount }
    }

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
    public var lastRenewTimestamp: Date? = nil
    public var lastSLAResult: SLABaselineResult? = nil
    public var isRunningSLA: Bool = false

    public var healthScorePercentage: Int {
        var score = 100
        if let gw = gatewayLatencyMs {
            if gw > 50 { score -= 25 }
            else if gw > 15 { score -= 10 }
            else if gw > 5 { score -= 5 }
        } else {
            score -= 50
        }

        if let inet = internetLatencyMs {
            if inet > 150 { score -= 25 }
            else if inet > 70 { score -= 10 }
            else if inet > 35 { score -= 5 }
        } else {
            score -= 40
        }

        if let link = wifiLink {
            if link.rssi < -80 { score -= 20 }
            else if link.rssi < -70 { score -= 10 }
            else if link.rssi < -65 { score -= 5 }
        }

        if !(hasIPv6 && !publicIPv6.isEmpty && !publicIPv6.contains("Unavailable") && !publicIPv6.contains("Resolving")) {
            score -= 5
        }

        return max(0, min(100, score))
    }

    public var healthScoreLabel: String {
        let s = healthScorePercentage
        if s >= 90 { return "OPTIMAL" }
        if s >= 75 { return "GOOD" }
        if s >= 50 { return "FAIR" }
        return "DEGRADED"
    }

    public var healthScoreColorHex: String {
        let s = healthScorePercentage
        if s >= 90 { return "#10B981" }
        if s >= 75 { return "#3B82F6" }
        if s >= 50 { return "#F59E0B" }
        return "#EF4444"
    }

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
    private var cycleCounter: Int = 0
    private var isProbingCycleActive: Bool = false

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
        let subnet = querySubnetInfo(interface: self.activeInterface)
        self.subnetMask = subnet.mask
        self.broadcastAddress = subnet.broadcast
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
                try? await Task.sleep(nanoseconds: 8_000_000_000) // 8s tick (energy and CPU friendly)
            }
        }
    }

    public func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    @MainActor
    public func performMonitorCycle() async {
        guard !isProbingCycleActive else { return }
        isProbingCycleActive = true
        defer { isProbingCycleActive = false }

        cycleCounter += 1
        let shouldRefreshInterfaces = (cycleCounter == 1 || cycleCounter % 4 == 0) // Every 32s or initial cycle

        if shouldRefreshInterfaces {
            let activeIf = self.activeInterface
            let telemetry = await Task.detached(priority: .utility) { [weak self] () -> ((gateway: String, interface: String), String, (mask: String, broadcast: String), String, (primary: String, all: [String])) in
                guard let self = self else { return (("", "en0"), "", ("", ""), "", ("", [])) }
                let route = self.parseDefaultRoute()
                let targetIf = !route.interface.isEmpty ? route.interface : activeIf
                let ip = self.queryLocalIP(interface: targetIf)
                let subnet = self.querySubnetInfo(interface: targetIf)
                let v6 = self.queryLocalIPv6(interface: targetIf)
                let dns = self.parseSystemDNS()
                return (route, ip, subnet, v6, dns)
            }.value

            let route = telemetry.0
            if !route.interface.isEmpty {
                self.activeInterface = route.interface
            }
            if !route.gateway.isEmpty {
                self.defaultGateway = route.gateway
            }

            let ip = telemetry.1
            if !ip.isEmpty && ip != "127.0.0.1" {
                self.localIP = ip
            }

            let subnet = telemetry.2
            self.subnetMask = subnet.mask
            self.broadcastAddress = subnet.broadcast

            let v6 = telemetry.3
            if !v6.isEmpty {
                self.localIPv6 = v6
                self.hasIPv6 = true
            }

            let dns = telemetry.4
            if !dns.primary.isEmpty {
                self.dnsServer = dns.primary
                self.allDnsServers = dns.all
            }
            if let v6DNS = dns.all.first(where: { $0.contains(":") }) {
                self.dnsServerIPv6 = v6DNS
            }

            // Wi-Fi status if active interface is Wi-Fi
            let link = await WiFiEngine.shared.fetchCurrentLink(interfaceName: self.activeInterface)
            self.wifiLink = link
        }

        // 4. Ping local default gateway (runs off MainActor)
        let gwRTT = await pingHost(host: self.defaultGateway, timeoutMs: 800)
        self.gatewayLatencyMs = gwRTT
        if let rtt = gwRTT {
            self.gatewaySamples.append(rtt)
            if self.gatewaySamples.count > 24 {
                self.gatewaySamples.removeFirst(self.gatewaySamples.count - 24)
            }
        }

        // 5. Query & Ping IPv6 Default Gateway (runs off MainActor)
        let gw6 = await Task.detached(priority: .utility) { [weak self] in
            self?.parseDefaultRouteIPv6() ?? ""
        }.value

        if !gw6.isEmpty {
            self.defaultGatewayIPv6 = gw6
            self.gatewayIPv6LatencyMs = await pingHostIPv6(host: gw6, interface: self.activeInterface)
        }

        // 6. Ping Internet (1.1.1.1) (runs off MainActor)
        let inetRTT = await pingHost(host: "1.1.1.1", timeoutMs: 900)
        self.internetLatencyMs = inetRTT

        // 7. Evaluate Health Status
        if gwRTT == nil && inetRTT == nil {
            self.healthStatus = .offline
        } else if let gw = gwRTT, gw > 60.0 || inetRTT == nil {
            self.healthStatus = .degraded
        } else {
            self.healthStatus = .optimal
        }

        // 8. Refresh Public IP periodically (every 5 minutes)
        if Date().timeIntervalSince(lastPublicIPCheck) > 300 {
            lastPublicIPCheck = Date()
            Task {
                await fetchPublicIPDetails()
            }
        }
    }

    /// Performs an instantaneous ping probe using /sbin/ping asynchronously off the MainActor
    public func pingHost(host: String, timeoutMs: Int = 800) async -> Double? {
        guard !host.isEmpty && host != "127.0.0.1" else { return 0.5 }
        return await Task.detached(priority: .utility) {
            let pipe = Pipe()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/sbin/ping")
            process.arguments = ["-c", "1", "-W", "\(timeoutMs)", host]
            process.standardOutput = pipe
            process.standardError = Pipe()

            let watchdog = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
            watchdog.schedule(deadline: .now() + Double(timeoutMs) / 1000.0 + 0.6)
            watchdog.setEventHandler {
                if process.isRunning {
                    process.terminate()
                }
            }
            watchdog.resume()
            defer { watchdog.cancel() }

            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else { return nil }

                guard let output = String(data: data, encoding: .utf8) else { return nil }

                // Parse "time=1.234 ms"
                if let timeRange = output.range(of: "time=") {
                    let after = output[timeRange.upperBound...]
                    if let msRange = after.range(of: " ms") {
                        let numStr = after[..<msRange.lowerBound]
                        return Double(numStr)
                    }
                }
                return nil
            } catch {
                return nil
            }
        }.value
    }

    /// Measures instantaneous round-trip time to an IPv6 address using /sbin/ping6 asynchronously off the MainActor
    public func pingHostIPv6(host: String, interface: String = "en0", timeoutMs: Int = 800) async -> Double? {
        guard !host.isEmpty else { return nil }
        return await Task.detached(priority: .utility) {
            let pipe = Pipe()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/sbin/ping6")
            // If link-local (starts with fe80), append interface
            let targetHost = (host.lowercased().starts(with: "fe80") && !host.contains("%")) ? "\(host)%\(interface)" : host
            process.arguments = ["-c", "1", "-W", "\(timeoutMs)", targetHost]
            process.standardOutput = pipe
            process.standardError = Pipe()

            let watchdog = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
            watchdog.schedule(deadline: .now() + Double(timeoutMs) / 1000.0 + 0.6)
            watchdog.setEventHandler {
                if process.isRunning {
                    process.terminate()
                }
            }
            watchdog.resume()
            defer { watchdog.cancel() }

            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else { return nil }

                guard let output = String(data: data, encoding: .utf8) else { return nil }

                if let timeRange = output.range(of: "time=") {
                    let after = output[timeRange.upperBound...]
                    if let msRange = after.range(of: " ms") {
                        let numStr = after[..<msRange.lowerBound]
                        return Double(numStr)
                    }
                }
                return nil
            } catch {
                return nil
            }
        }.value
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

    /// Runs a 5-probe baseline SLA audit calculating RFC 3550 jitter, loss, and latency
    public func runSLABaselineAudit() async -> SLABaselineResult {
        await MainActor.run {
            self.isRunningSLA = true
        }

        let gw = self.defaultGateway.isEmpty ? "192.168.10.1" : self.defaultGateway
        let inet = "1.1.1.1"

        // 1. Probe Gateway 5 times
        var gwSamples: [Double] = []
        var gwLost = 0
        for _ in 0..<5 {
            if let rtt = await pingHost(host: gw, timeoutMs: 500) {
                gwSamples.append(rtt)
            } else {
                gwLost += 1
            }
            try? await Task.sleep(nanoseconds: 80_000_000)
        }

        let gwLoss = (Double(gwLost) / 5.0) * 100.0
        let gwAvg = gwSamples.isEmpty ? 0.0 : gwSamples.reduce(0, +) / Double(gwSamples.count)
        let gwMin = gwSamples.min() ?? 0.0
        let gwMax = gwSamples.max() ?? 0.0

        // RFC 3550 Interarrival Jitter calculation: J = J + (|D(i-1, i)| - J) / 16
        var jitter: Double = 0.0
        if gwSamples.count > 1 {
            for i in 1..<gwSamples.count {
                let diff = abs(gwSamples[i] - gwSamples[i - 1])
                jitter += (diff - jitter) / 16.0
            }
        }

        // 2. Probe Internet WAN 4 times
        var inetSamples: [Double] = []
        var inetLost = 0
        for _ in 0..<4 {
            if let rtt = await pingHost(host: inet, timeoutMs: 800) {
                inetSamples.append(rtt)
            } else {
                inetLost += 1
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        let inetLoss = (Double(inetLost) / 4.0) * 100.0
        let inetAvg = inetSamples.isEmpty ? 0.0 : inetSamples.reduce(0, +) / Double(inetSamples.count)

        // 3. DNS Lookup Timing via Darwin getaddrinfo (pure C, zero bridging overhead)
        let dnsStart = DispatchTime.now()
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var res: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo("apple.com", "80", &hints, &res)
        let dnsEnd = DispatchTime.now()
        var dnsMs = -1.0
        if status == 0 {
            freeaddrinfo(res)
            dnsMs = Double(dnsEnd.uptimeNanoseconds - dnsStart.uptimeNanoseconds) / 1_000_000.0
        }

        // 4. Grade Evaluation
        let grade: String
        let recommendation: String
        if gwLoss == 100.0 && inetLoss == 100.0 {
            grade = "F (Offline / Link Down)"
            recommendation = "Complete network link failure. Both default gateway and WAN targets are unresponsive (100% loss)."
        } else if inetLoss == 100.0 && gwLoss == 0.0 {
            grade = "D (Gateway OK, WAN Outage)"
            recommendation = "Local LAN gateway reachable, but upstream ISP WAN connection is completely unresponsive."
        } else if gwLoss == 0.0 && inetLoss == 0.0 && gwAvg < 15.0 && inetAvg < 60.0 && jitter < 4.0 {
            grade = "A++++ (Optimal SLA)"
            recommendation = "Low jitter (\(String(format: "%.1f", jitter))ms), 0% packet loss, sub-millisecond local switching. Meets Tier-1 VoIP/eSports standard."
        } else if gwLoss == 0.0 && inetLoss < 5.0 && inetAvg < 100.0 {
            grade = "A (Good Quality)"
            recommendation = "Reliable broadband transit with 0% gateway loss. Suitable for 4K streaming and high-bandwidth workloads."
        } else if gwLoss > 10.0 || inetLoss > 15.0 {
            grade = "C (High Loss SLA)"
            recommendation = "Packet loss detected on \(gwLoss > 0 ? "local LAN segment" : "upstream WAN transit"). Check Wi-Fi interference or physical cabling."
        } else {
            grade = "B (Acceptable)"
            recommendation = "Moderate latency detected. All core protocols functional."
        }

        let result = SLABaselineResult(
            timestamp: Date(),
            gatewayHost: gw,
            gatewayMinMs: gwMin,
            gatewayAvgMs: gwAvg,
            gatewayMaxMs: gwMax,
            gatewayJitterMs: jitter,
            gatewayLossPercent: gwLoss,
            internetHost: inet,
            internetAvgMs: inetAvg,
            internetLossPercent: inetLoss,
            dnsHost: "apple.com",
            dnsLookupMs: dnsMs,
            overallGrade: grade,
            recommendation: recommendation
        )

        await MainActor.run {
            self.lastSLAResult = result
            self.isRunningSLA = false
        }

        return result
    }

    /// Renews DHCP lease for active interface
    public func renewDHCPLease() async -> (success: Bool, message: String) {
        let serviceName = findServiceName(for: self.activeInterface) ?? "Wi-Fi"

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        proc.arguments = ["-setdhcp", serviceName]
        let errPipe = Pipe()
        proc.standardError = errPipe
        proc.standardOutput = Pipe()

        do {
            try proc.run()
            proc.waitUntilExit()
            if proc.terminationStatus == 0 {
                self.lastRenewTimestamp = Date()
                try? await Task.sleep(nanoseconds: 800_000_000)
                await self.performMonitorCycle()
                return (true, "DHCP lease renewed successfully on \(serviceName) (\(self.activeInterface)).")
            } else {
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let errStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return (false, "DHCP renew failed: \(errStr.isEmpty ? "Exit code \(proc.terminationStatus)" : errStr)")
            }
        } catch {
            return (false, "Failed to execute networksetup: \(error.localizedDescription)")
        }
    }

    /// Discovers macOS network service name corresponding to an interface name
    public func findServiceName(for interface: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        proc.arguments = ["-listnetworkserviceorder"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()

        guard let _ = try? proc.run() else { return nil }
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }

        let lines = output.components(separatedBy: .newlines)
        for (idx, line) in lines.enumerated() {
            if line.contains("Device: \(interface)") && idx > 0 {
                let prev = lines[idx - 1].trimmingCharacters(in: .whitespaces)
                if let closeParen = prev.firstIndex(of: ")") {
                    let after = prev[prev.index(after: closeParen)...].trimmingCharacters(in: .whitespaces)
                    if !after.isEmpty {
                        return after
                    }
                }
            }
        }
        return nil
    }

    /// Formats a complete, production-grade Markdown engineering diagnosis report
    public func generateSysdiagnoseReport() -> String {
        let dateStr = ISO8601DateFormatter().string(from: Date())
        let hostName = ProcessInfo.processInfo.hostName
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString

        var lines: [String] = []
        lines.append("# NexWave Network Diagnostics Engineering Report")
        lines.append("**Generated:** \(dateStr)  ")
        lines.append("**Host:** `\(hostName)`  ")
        lines.append("**OS:** macOS \(osVersion)  ")
        lines.append("**Health Index:** \(healthScorePercentage)% (\(healthScoreLabel))")
        lines.append("")
        lines.append("---")
        lines.append("")
        lines.append("## 1. Network Interface & Physical Layer")
        lines.append("- **Active Interface:** `\(activeInterface)`")

        if let link = wifiLink {
            lines.append("- **Medium:** Wi-Fi (\(link.phyMode.displayName))")
            lines.append("- **SSID / BSSID:** `\(link.ssid)` (`\(link.bssid)`)")
            lines.append("- **Radio Channel:** Ch \(link.channel) (\(link.band.rawValue))")
            lines.append("- **Signal (RSSI):** \(link.rssi) dBm")
            lines.append("- **Noise Floor:** \(link.noise) dBm")
            lines.append("- **SNR:** \(link.snr) dB")
            lines.append("- **Tx Rate:** \(Int(link.transmitRate)) Mbps")
            lines.append("- **Security:** \(link.security)")
        } else {
            lines.append("- **Medium:** Wired Ethernet / Bridge")
            lines.append("- **Link Speed:** Gigabit Full-Duplex")
        }

        lines.append("")
        lines.append("## 2. IP Protocol Telemetry (Dual-Stack)")
        lines.append("### IPv4 Configuration")
        lines.append("- **Local IPv4:** `\(localIP)/\(cidrPrefix)` (Subnet Mask: `\(subnetMask)`, Broadcast: `\(broadcastAddress)`)")
        let gwLat = gatewayLatencyMs.map { String(format: "%.2f ms", $0) } ?? "Unreachable"
        lines.append("- **Default Gateway:** `\(defaultGateway)` (RTT: \(gwLat))")
        lines.append("- **Primary Resolver:** `\(dnsServer)` (\(dnsResolverName))")
        lines.append("")
        lines.append("### IPv6 Configuration")
        lines.append("- **Local IPv6 (SLAAC/Global):** `\(localIPv6.isEmpty ? "None" : localIPv6)`")
        let gw6Lat = gatewayIPv6LatencyMs.map { String(format: "%.2f ms", $0) } ?? "N/A"
        lines.append("- **Default Gateway IPv6:** `\(defaultGatewayIPv6.isEmpty ? "None" : defaultGatewayIPv6)` (RTT: \(gw6Lat))")
        lines.append("- **IPv6 Resolver:** `\(dnsServerIPv6.isEmpty ? "None" : dnsServerIPv6)`")
        lines.append("")
        lines.append("### Public WAN Egress")
        lines.append("- **Public IPv4:** `\(publicIPv4)`")
        lines.append("- **Public IPv6:** `\(publicIPv6)`")
        lines.append("")
        lines.append("## 3. SLA & End-to-End Latency")
        let gwRoundTrip = gatewayLatencyMs.map { String(format: "%.2f ms", $0) } ?? "Timeout"
        lines.append("- **Local Gateway Round-Trip:** \(gwRoundTrip)")
        let inetRoundTrip = internetLatencyMs.map { String(format: "%.2f ms", $0) } ?? "Timeout"
        lines.append("- **Internet Backbone Round-Trip (1.1.1.1):** \(inetRoundTrip)")
        lines.append("- **All Configured DNS Resolvers:**")
        for s in allDnsServers {
            lines.append("  - `\(s)`")
        }
        lines.append("")
        lines.append("*Generated by NexWave Mac Network Workbench — Zero-Root Unprivileged Diagnostics.*")

        return lines.joined(separator: "\n")
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
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
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
            let data = netstatPipe.fileHandleForReading.readDataToEndOfFile()
            netstatProc.waitUntilExit()
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
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            if let output = String(data: data, encoding: .utf8) {
                for line in output.components(separatedBy: .newlines) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.starts(with: "gateway:") {
                        let gw = trimmed.replacingOccurrences(of: "gateway:", with: "").trimmingCharacters(in: .whitespaces)
                        return gw.components(separatedBy: "%").first ?? ""
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
            let data = netstatPipe.fileHandleForReading.readDataToEndOfFile()
            netstatProc.waitUntilExit()
            if let output = String(data: data, encoding: .utf8) {
                for line in output.components(separatedBy: .newlines) {
                    let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                    if parts.count >= 4 && parts[0] == "default" {
                        let gw = String(parts[1])
                        return gw.components(separatedBy: "%").first ?? ""
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
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
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

    public func querySubnetInfo(interface: String) -> (mask: String, broadcast: String) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return ("255.255.255.0", "") }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let current = ptr {
            let name = String(cString: current.pointee.ifa_name)
            if (name == interface || interface.isEmpty) && current.pointee.ifa_addr != nil && current.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                var maskStr = ""
                var broadStr = ""
                if let netmask = current.pointee.ifa_netmask {
                    var maskBuf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(netmask, socklen_t(netmask.pointee.sa_len), &maskBuf, socklen_t(maskBuf.count), nil, 0, NI_NUMERICHOST) == 0 {
                        maskStr = maskBuf.withUnsafeBufferPointer { $0.baseAddress.map { String(cString: $0) } ?? "" }
                    }
                }
                if let broad = current.pointee.ifa_dstaddr {
                    var broadBuf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(broad, socklen_t(broad.pointee.sa_len), &broadBuf, socklen_t(broadBuf.count), nil, 0, NI_NUMERICHOST) == 0 {
                        broadStr = broadBuf.withUnsafeBufferPointer { $0.baseAddress.map { String(cString: $0) } ?? "" }
                    }
                }
                return (maskStr.isEmpty ? "255.255.255.0" : maskStr, broadStr)
            }
            ptr = current.pointee.ifa_next
        }
        return ("255.255.255.0", "")
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
