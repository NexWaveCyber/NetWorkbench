import Foundation
import Network
import NetworkCore

/// High-speed local LAN neighbor discoverer using zero-root macOS neighbor tables, active subnet sweep, and Bonjour mDNS.
public actor LocalDiscoveryEngine {
    public init() {}

    /// Discovers local network neighbors across ARP (IPv4), NDP (IPv6), and Bonjour mDNS services.
    /// - Parameter performSweep: If true, proactively sends gentle unprivileged probes across the /24 subnet to wake dormant hosts.
    public func discoverNeighbors(performSweep: Bool = true) async -> [DiscoveredNeighbor] {
        // 1. Proactive gentle sweep to wake dormant devices into Darwin kernel ARP cache
        if performSweep {
            await sweepActiveSubnet()
        }

        // 2. Discover Bonjour / mDNS network services concurrently
        let bonjourMap = await browseBonjourServices()

        var results: [String: DiscoveredNeighbor] = [:]

        // 3. Ingest IPv4 ARP cache
        let arpNeighbors = parseARPOutput(runCommand("/usr/sbin/arp", arguments: ["-an"]))
        for n in arpNeighbors {
            guard isEligibleHost(ip: n.ipAddress, interface: n.interface) else { continue }
            results[n.ipAddress] = n
        }

        // 4. Ingest IPv6 NDP cache
        let ndpNeighbors = parseNDPOutput(runCommand("/usr/sbin/ndp", arguments: ["-an"]))
        for n in ndpNeighbors {
            guard isEligibleHost(ip: n.ipAddress, interface: n.interface) else { continue }
            if var existing = results[n.ipAddress] {
                existing.discoveredServices.append(contentsOf: n.discoveredServices)
                results[n.ipAddress] = existing
            } else {
                results[n.ipAddress] = n
            }
        }

        // 5. Enrich with Bonjour hostnames, services, and Reverse DNS PTR
        var enriched: [DiscoveredNeighbor] = []
        for var neighbor in results.values {
            // Apply Bonjour metadata if available
            if let bj = bonjourMap[neighbor.ipAddress] {
                if neighbor.hostname == nil || neighbor.hostname?.isEmpty == true {
                    neighbor.hostname = bj.hostname
                }
                for s in bj.services where !neighbor.discoveredServices.contains(s) {
                    neighbor.discoveredServices.append(s)
                }
            }

            // Fallback to Reverse DNS PTR query if hostname is still empty
            if neighbor.hostname == nil || neighbor.hostname?.isEmpty == true {
                if let ptrName = resolveReverseDNS(ip: neighbor.ipAddress) {
                    neighbor.hostname = ptrName
                }
            }

            // If neighbor has Bonjour services, upgrade source to combined
            if !neighbor.discoveredServices.isEmpty && neighbor.discoverySource != .bonjour {
                neighbor = DiscoveredNeighbor(
                    ipAddress: neighbor.ipAddress,
                    macAddress: neighbor.macAddress,
                    hostname: neighbor.hostname,
                    interface: neighbor.interface,
                    discoverySource: .combined,
                    ouiVendor: neighbor.ouiVendor,
                    discoveredServices: neighbor.discoveredServices,
                    lastSeen: neighbor.lastSeen
                )
            }

            enriched.append(neighbor)
        }

        return enriched.sorted {
            // Natural sort: IPv4 before IPv6, then numerically
            if $0.ipAddress.contains(".") && !$1.ipAddress.contains(".") { return true }
            if !$0.ipAddress.contains(".") && $1.ipAddress.contains(".") { return false }
            return $0.ipAddress < $1.ipAddress
        }
    }

    // MARK: - Active Subnet Sweep

    /// Rapid unprivileged sweep of the local IPv4 /24 subnet to populate macOS ARP cache.
    public func sweepActiveSubnet() async {
        guard let subnetPrefix = detectLocalIPv4SubnetPrefix() else { return }

        // Sweep 1...254 with 32 concurrent unprivileged TCP/UDP touch tasks
        await withTaskGroup(of: Void.self) { group in
            for hostNum in 1...254 {
                let targetIP = "\(subnetPrefix).\(hostNum)"
                group.addTask {
                    let endpoint = NWEndpoint.hostPort(
                        host: NWEndpoint.Host(targetIP),
                        port: NWEndpoint.Port(rawValue: 80)!
                    )
                    let params = NWParameters.tcp
                    params.prohibitExpensivePaths = false
                    let conn = NWConnection(to: endpoint, using: params)
                    conn.start(queue: .global(qos: .utility))

                    try? await Task.sleep(nanoseconds: 120_000_000) // 120ms probe
                    conn.cancel()
                }
            }
        }
    }

    private func detectLocalIPv4SubnetPrefix() -> String? {
        let output = runCommand("/sbin/ifconfig", arguments: ["en0"])
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("inet ") {
                let parts = trimmed.components(separatedBy: .whitespaces)
                if parts.count >= 2 {
                    let ip = parts[1]
                    let octets = ip.split(separator: ".")
                    if octets.count == 4 {
                        return "\(octets[0]).\(octets[1]).\(octets[2])"
                    }
                }
            }
        }
        return nil
    }

    // MARK: - Bonjour / mDNS Discovery

    public struct BonjourInfo: Sendable {
        public var hostname: String
        public var services: [String]
    }

    private final class DiscoveredBox: @unchecked Sendable {
        private let lock = NSLock()
        private var item: (String, String, String)?
        func set(_ value: (String, String, String)) {
            lock.lock()
            defer { lock.unlock() }
            item = value
        }
        func get() -> (String, String, String)? {
            lock.lock()
            defer { lock.unlock() }
            return item
        }
    }

    /// Discovers local Bonjour announcements across common service protocols.
    private func browseBonjourServices() async -> [String: BonjourInfo] {
        var map: [String: BonjourInfo] = [:]
        let serviceTypes: [(type: String, label: String)] = [
            ("_http._tcp", "HTTP Web UI"),
            ("_https._tcp", "HTTPS Web UI"),
            ("_ssh._tcp", "SSH Terminal"),
            ("_smb._tcp", "SMB File Sharing"),
            ("_airplay._tcp", "AirPlay Display"),
            ("_raop._tcp", "AirPlay Audio"),
            ("_googlecast._tcp", "Google Cast"),
            ("_printer._tcp", "IPP Printer"),
            ("_ipp._tcp", "IPP Printer"),
            ("_workstation._tcp", "Mac Workstation")
        ]

        await withTaskGroup(of: (String, String, String)?.self) { group in
            for s in serviceTypes {
                group.addTask {
                    let box = DiscoveredBox()
                    let descriptor = NWBrowser.Descriptor.bonjour(type: s.type, domain: "local.")
                    let browser = NWBrowser(for: descriptor, using: .tcp)

                    browser.browseResultsChangedHandler = { results, _ in
                        for res in results {
                            if case .service(let name, _, _, let iface) = res.endpoint {
                                box.set((name, s.label, iface?.name ?? "en0"))
                            }
                        }
                    }

                    browser.start(queue: .global(qos: .utility))
                    try? await Task.sleep(nanoseconds: 600_000_000) // 600ms listener window
                    browser.cancel()
                    return box.get()
                }
            }

            for await result in group {
                if let (name, label, _) = result {
                    // Match by resolved mDNS hostname if resolvable
                    let cleanHost = name.replacingOccurrences(of: " ", with: "-") + ".local"
                    map[cleanHost, default: BonjourInfo(hostname: name, services: [])].services.append(label)
                }
            }
        }

        return map
    }

    // MARK: - Reverse DNS PTR Resolver

    private func resolveReverseDNS(ip: String) -> String? {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_flags = AI_NUMERICHOST

        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(ip, nil, &hints, &res) == 0, let addr = res else {
            return nil
        }
        defer { freeaddrinfo(res) }

        var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let status = getnameinfo(
            addr.pointee.ai_addr,
            addr.pointee.ai_addrlen,
            &hostBuffer,
            socklen_t(hostBuffer.count),
            nil,
            0,
            NI_NAMEREQD
        )

        if status == 0 {
            let name = hostBuffer.withUnsafeBufferPointer { ptr -> String in
                guard let base = ptr.baseAddress else { return "" }
                return String(cString: base)
            }
            if !name.isEmpty && name != ip {
                return name
            }
        }
        return nil
    }

    // MARK: - Filtering & Eligibility

    private func isEligibleHost(ip: String, interface: String) -> Bool {
        // Filter out multicast
        if ip.hasPrefix("224.") || ip.hasPrefix("225.") || ip.hasPrefix("239.") || ip.hasPrefix("ff") {
            return false
        }
        // Filter out broadcast
        if ip.hasSuffix(".255") || ip == "255.255.255.255" {
            return false
        }
        // Filter out virtual/tunnel interfaces
        let lowerIface = interface.lowercased()
        if lowerIface.hasPrefix("lo") || lowerIface.hasPrefix("utun") || lowerIface.hasPrefix("awdl") || lowerIface.hasPrefix("llw") {
            return false
        }
        return true
    }

    // MARK: - Output Parsers

    /// Parses output from `/usr/sbin/arp -an`.
    public func parseARPOutput(_ output: String) -> [DiscoveredNeighbor] {
        var neighbors: [DiscoveredNeighbor] = []
        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            guard !trimmed.contains("(incomplete)"), !trimmed.contains("ff:ff:ff:ff:ff:ff") else { continue }

            // Extract IP address inside ( ... )
            guard let openParen = trimmed.firstIndex(of: "("),
                  let closeParen = trimmed.firstIndex(of: ")"),
                  openParen < closeParen else { continue }

            let ip = String(trimmed[trimmed.index(after: openParen)..<closeParen])

            // Extract MAC address after " at "
            guard let atRange = trimmed.range(of: " at ") else { continue }
            let afterAt = String(trimmed[atRange.upperBound...])
            let parts = afterAt.components(separatedBy: .whitespaces)
            guard let rawMac = parts.first, rawMac.contains(":") else { continue }

            // Format MAC standard 2-digit pairs
            let formattedMac = normalizeMAC(rawMac)

            // Extract Interface after " on "
            var iface = "en0"
            if let onRange = trimmed.range(of: " on ") {
                let afterOn = String(trimmed[onRange.upperBound...])
                if let ifaceName = afterOn.components(separatedBy: .whitespaces).first {
                    iface = ifaceName
                }
            }

            let vendor = OUIResolver.resolve(mac: formattedMac)
            neighbors.append(DiscoveredNeighbor(
                ipAddress: ip,
                macAddress: formattedMac,
                interface: iface,
                discoverySource: .arp,
                ouiVendor: vendor,
                discoveredServices: []
            ))
        }

        return neighbors
    }

    /// Parses output from `/usr/sbin/ndp -an`.
    public func parseNDPOutput(_ output: String) -> [DiscoveredNeighbor] {
        var neighbors: [DiscoveredNeighbor] = []
        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("Neighbor") else { continue }
            guard !trimmed.contains("(incomplete)"), !trimmed.contains("(none)") else { continue }

            let tokens = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard tokens.count >= 3 else { continue }

            let rawIP = tokens[0]
            let rawMac = tokens[1]
            let iface = tokens[2]

            guard rawMac.contains(":") else { continue }
            let formattedMac = normalizeMAC(rawMac)
            let cleanIP = rawIP.components(separatedBy: "%").first ?? rawIP

            let vendor = OUIResolver.resolve(mac: formattedMac)
            neighbors.append(DiscoveredNeighbor(
                ipAddress: cleanIP,
                macAddress: formattedMac,
                interface: iface,
                discoverySource: .ndp,
                ouiVendor: vendor,
                discoveredServices: []
            ))
        }

        return neighbors
    }

    private func normalizeMAC(_ mac: String) -> String {
        let parts = mac.components(separatedBy: ":")
        let padded = parts.map { part -> String in
            if part.count == 1 {
                return "0" + part
            }
            return part
        }
        return padded.joined(separator: ":").lowercased()
    }

    private func runCommand(_ executable: String, arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }

    /// Rapidly resolves a local IP address (such as the default gateway) to its hardware MAC and OUI vendor via Darwin ARP cache.
    public static func resolveLocalHost(ip: String) -> (mac: String, vendor: DeviceVendor, vendorName: String?)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/arp")
        process.arguments = ["-n", ip]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8), !output.isEmpty else { return nil }

            guard !output.contains("(incomplete)"),
                  let atRange = output.range(of: " at ") else { return nil }

            let afterAt = String(output[atRange.upperBound...])
            let parts = afterAt.components(separatedBy: .whitespaces)
            guard let rawMac = parts.first, rawMac.contains(":") else { return nil }

            let octets = rawMac.components(separatedBy: ":").map { $0.count == 1 ? "0\($0)" : $0 }
            let normalized = octets.joined(separator: ":").lowercased()

            let vendorName = OUIResolver.resolve(mac: normalized)
            let vendorEnum = OUIResolver.inferVendor(mac: normalized)

            return (normalized, vendorEnum, vendorName)
        } catch {
            return nil
        }
    }
}
