import Foundation
import Network
import NetworkCore

/// Information describing the active primary local network interface and subnet.
public struct ActiveNetworkInterface: Sendable, Equatable {
    public let name: String          // e.g. "en0"
    public let ipAddress: String     // e.g. "192.168.10.19"
    public let netmask: String       // e.g. "255.255.255.0"
    public let prefixLength: Int     // e.g. 24
    public let gateway: String       // e.g. "192.168.10.1"
    public let cidr: String          // e.g. "192.168.10.0/24"
    public let broadcast: String?    // e.g. "192.168.10.255"

    public var ipv4: String { ipAddress }

    public init(
        name: String,
        ipAddress: String,
        netmask: String,
        prefixLength: Int,
        gateway: String,
        cidr: String,
        broadcast: String? = nil
    ) {
        self.name = name
        self.ipAddress = ipAddress
        self.netmask = netmask
        self.prefixLength = prefixLength
        self.gateway = gateway
        self.cidr = cidr
        self.broadcast = broadcast
    }
}

/// Thread-safe atomic flag for fast unprivileged probe cancellations.
private final class ThreadSafeAtomicFlag: @unchecked Sendable {
    private var value: Bool
    private let lock = NSLock()

    init(_ value: Bool = false) {
        self.value = value
    }

    func testAndSet() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if !value {
            value = true
            return true
        }
        return false
    }
}

/// Thread-safe collector for multi-instance Bonjour mDNS announcements.
private final class BonjourCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [(name: String, label: String, iface: String)] = []

    func append(name: String, label: String, iface: String) {
        lock.lock()
        defer { lock.unlock() }
        entries.append((name, label, iface))
    }

    func all() -> [(name: String, label: String, iface: String)] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

/// High-speed local LAN neighbor discoverer using zero-root macOS neighbor tables, active subnet sweep, and Bonjour mDNS.
public actor LocalDiscoveryEngine {
    public init() {}

    /// Discovers local network neighbors across ARP (IPv4), NDP (IPv6), and Bonjour mDNS services.
    /// - Parameters:
    ///   - customSubnet: Optional specific CIDR subnet to scan (e.g. "10.0.50.0/24"). If nil, dynamically detects the active interface's subnet.
    ///   - targetInterface: Optional specific network interface name to scan (e.g. "en0", "en5"). If nil, uses default active route interface.
    ///   - performSweep: If true, proactively sweeps the subnet with throttled multi-vector probes to populate Darwin kernel ARP cache.
    ///   - onProgress: Optional callback invoked with (phaseDescription, currentCount, totalCount) for real-time UI telemetry.
    public func discoverNeighbors(
        customSubnet: String? = nil,
        targetInterface: String? = nil,
        performSweep: Bool = true,
        onProgress: (@Sendable (_ phase: String, _ current: Int, _ total: Int) -> Void)? = nil
    ) async -> [DiscoveredNeighbor] {
        if Task.isCancelled { return [] }

        // 0. Detect active interface and target CIDR
        let activeIface = resolveTargetInterface(preferredName: targetInterface)
        let targetCIDR = customSubnet ?? activeIface?.cidr ?? "192.168.1.0/24"
        let ifaceName = activeIface?.name ?? "en0"

        // 1. Proactive multi-vector sweep to wake dormant devices into Darwin kernel ARP cache
        var latencyMap: [String: Double] = [:]
        if performSweep {
            latencyMap = await sweepSubnet(cidr: targetCIDR, onProgress: onProgress)
        }

        if Task.isCancelled { return [] }
        onProgress?("Waking IPv6 Nodes & Ingesting Kernel Neighbor Tables", 1, 4)

        // 2. Discover Bonjour / mDNS network services concurrently
        let (bonjourByIP, bonjourByName) = await browseBonjourServices()

        var results: [String: DiscoveredNeighbor] = [:]

        // 3. Ingest IPv4 ARP cache
        let arpNeighbors = parseARPOutput(Self.runCommand("/usr/sbin/arp", arguments: ["-an"]))
        for n in arpNeighbors {
            guard isEligibleHost(ip: n.ipAddress, interface: n.interface) else { continue }
            results[n.ipAddress] = n
        }

        // 4. Proactively ping IPv6 all-nodes multicast and ingest IPv6 NDP cache
        Self.pingIPv6AllNodesMulticast(interface: ifaceName)
        let ndpNeighbors = parseNDPOutput(Self.runCommand("/usr/sbin/ndp", arguments: ["-an"]))
        for n in ndpNeighbors {
            guard isEligibleHost(ip: n.ipAddress, interface: n.interface) else { continue }

            // If an ARP neighbor already exists for this exact MAC, consolidate IPv4 + unique IPv6!
            if let existingKey = results.keys.first(where: { results[$0]?.macAddress == n.macAddress }) {
                var existing = results[existingKey]!
                if existing.ipv6Address == nil {
                    existing.ipv6Address = n.ipAddress
                }
                existing.discoveredServices.append(contentsOf: n.discoveredServices)
                results[existingKey] = existing
            } else if var existingByIP = results[n.ipAddress] {
                if existingByIP.ipv6Address == nil {
                    existingByIP.ipv6Address = n.ipAddress
                }
                existingByIP.discoveredServices.append(contentsOf: n.discoveredServices)
                results[n.ipAddress] = existingByIP
            } else {
                // Device discovered solely via unique IPv6
                results[n.ipAddress] = n
            }
        }

        if Task.isCancelled { return [] }
        onProgress?("Resolving Reverse DNS & Profiling Host Latencies", 3, 4)

        // 5. Concurrent Reverse DNS Lookups
        let ipsToResolve = Array(results.keys)
        let ptrMap = await resolveReverseDNSConcurrent(ips: ipsToResolve)

        // 6. Enrich with Bonjour hostnames, services, PTR, and measured latency
        var enriched: [DiscoveredNeighbor] = []
        for var neighbor in results.values {
            // Attach measured latency from sweep
            if let lat = latencyMap[neighbor.ipAddress] {
                neighbor.latencyMs = lat
            }

            // Apply Bonjour services by IP
            if let services = bonjourByIP[neighbor.ipAddress] {
                for s in services where !neighbor.discoveredServices.contains(s) {
                    neighbor.discoveredServices.append(s)
                }
            }

            // Apply Reverse DNS PTR hostname
            if let ptrName = ptrMap[neighbor.ipAddress], !ptrName.isEmpty {
                neighbor.hostname = ptrName
            }

            // Fallback to Bonjour hostname by name match
            if let h = neighbor.hostname?.lowercased(), let services = bonjourByName[h] {
                for s in services where !neighbor.discoveredServices.contains(s) {
                    neighbor.discoveredServices.append(s)
                }
            }

            // If neighbor has Bonjour services or dual-stack IPv4+IPv6, upgrade source to combined
            let isDualStack = neighbor.ipAddress.contains(".") && neighbor.ipv6Address != nil
            if (!neighbor.discoveredServices.isEmpty || isDualStack) && neighbor.discoverySource != .bonjour {
                neighbor = DiscoveredNeighbor(
                    ipAddress: neighbor.ipAddress,
                    ipv6Address: neighbor.ipv6Address,
                    macAddress: neighbor.macAddress,
                    hostname: neighbor.hostname,
                    interface: neighbor.interface.isEmpty ? ifaceName : neighbor.interface,
                    discoverySource: .combined,
                    ouiVendor: neighbor.ouiVendor,
                    discoveredServices: neighbor.discoveredServices,
                    latencyMs: neighbor.latencyMs,
                    lastSeen: neighbor.lastSeen
                )
            } else if neighbor.latencyMs != nil {
                neighbor = DiscoveredNeighbor(
                    ipAddress: neighbor.ipAddress,
                    ipv6Address: neighbor.ipv6Address,
                    macAddress: neighbor.macAddress,
                    hostname: neighbor.hostname,
                    interface: neighbor.interface.isEmpty ? ifaceName : neighbor.interface,
                    discoverySource: neighbor.discoverySource,
                    ouiVendor: neighbor.ouiVendor,
                    discoveredServices: neighbor.discoveredServices,
                    latencyMs: neighbor.latencyMs,
                    lastSeen: neighbor.lastSeen
                )
            }

            enriched.append(neighbor)
        }

        // 7. Concurrent Asynchronous OUI Vendor Resolution for any remaining unmapped MACs
        let unmappedMACs = Array(Set(enriched.filter { $0.ouiVendor == nil && !$0.macAddress.isEmpty }.map { $0.macAddress }))
        if !unmappedMACs.isEmpty {
            var asyncOUI: [String: String] = [:]
            await withTaskGroup(of: (String, String?).self) { group in
                for mac in unmappedMACs {
                    group.addTask {
                        let res = await OUIResolver.resolveAsync(mac: mac)
                        return (mac, res)
                    }
                }
                for await (mac, name) in group {
                    if let name = name, !name.isEmpty {
                        asyncOUI[mac] = name
                    }
                }
            }
            if !asyncOUI.isEmpty {
                for i in 0..<enriched.count {
                    if enriched[i].ouiVendor == nil, let resolved = asyncOUI[enriched[i].macAddress] {
                        enriched[i].ouiVendor = resolved
                    }
                }
            }
        }

        onProgress?("Discovery Complete (\(enriched.count) hosts)", 4, 4)

        return enriched.sorted {
            let aIsV4 = $0.ipAddress.contains(".")
            let bIsV4 = $1.ipAddress.contains(".")
            if aIsV4 && !bIsV4 { return true }
            if !aIsV4 && bIsV4 { return false }
            if aIsV4 && bIsV4,
               let aIP = IPAddress.IPv4($0.ipAddress),
               let bIP = IPAddress.IPv4($1.ipAddress) {
                return aIP < bIP
            }
            return $0.ipAddress < $1.ipAddress
        }
    }

    // MARK: - Dynamic Interface & Subnet Resolution

    /// Discovers all currently active physical interfaces with an assigned IPv4 subnet carrier.
    nonisolated public static func enumerateActiveInterfaces() -> [ActiveNetworkInterface] {
        let output = runCommand("/sbin/ifconfig", arguments: ["-l"])
        let allIfaces = output.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }

        // Find default gateway
        let routeOutput = runCommand("/sbin/route", arguments: ["-n", "get", "default"])
        var defaultGateway = ""
        for line in routeOutput.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("gateway:") {
                defaultGateway = trimmed.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces) ?? ""
            }
        }

        var interfaces: [ActiveNetworkInterface] = []
        for iface in allIfaces {
            let lower = iface.lowercased()
            if lower.hasPrefix("lo") || lower.hasPrefix("utun") || lower.hasPrefix("awdl") || lower.hasPrefix("llw") || lower.hasPrefix("gif") || lower.hasPrefix("stf") || lower.hasPrefix("anpi") {
                continue
            }
            let check = runCommand("/sbin/ifconfig", arguments: [iface])
            if (check.contains("status: active") || check.contains("<UP,")) && check.contains("inet ") {
                if let parsed = parseInterfaceDetails(iface: iface, gateway: defaultGateway) {
                    interfaces.append(parsed)
                }
            }
        }
        return interfaces
    }

    /// Resolves target network interface, respecting user's preferred interface selection or falling back to active route.
    nonisolated public static func resolveTargetInterface(preferredName: String?) -> ActiveNetworkInterface? {
        if let pref = preferredName, !pref.isEmpty {
            let all = enumerateActiveInterfaces()
            if let matched = all.first(where: { $0.name.lowercased() == pref.lowercased() }) {
                return matched
            }
        }
        return resolveActiveInterface()
    }

    public func resolveTargetInterface(preferredName: String?) -> ActiveNetworkInterface? {
        Self.resolveTargetInterface(preferredName: preferredName)
    }

    public func enumerateActiveInterfaces() -> [ActiveNetworkInterface] {
        Self.enumerateActiveInterfaces()
    }

    /// Issues an unprivileged 1-packet multicast probe to the link-local all-nodes address ff02::1%<interface>.
    /// This proactively wakes dormant IPv6 nodes on the local link so they appear in `/usr/sbin/ndp -an`.
    nonisolated public static func pingIPv6AllNodesMulticast(interface: String) {
        let iface = interface.isEmpty ? "en0" : interface
        let destination = "ff02::1%\(iface)"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/ping6")
        process.arguments = ["-c", "1", "-i", "0.2", destination]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
            if process.isRunning {
                process.terminate()
            }
        }
        process.waitUntilExit()
    }

    /// Discovers the active network interface and subnet details.
    nonisolated public static func resolveActiveInterface() -> ActiveNetworkInterface? {
        // 1. Query Darwin route table for default gateway and interface
        let routeOutput = runCommand("/sbin/route", arguments: ["-n", "get", "default"])
        var ifaceName: String?
        var gatewayIP: String?

        for line in routeOutput.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("interface:") {
                ifaceName = trimmed.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("gateway:") {
                gatewayIP = trimmed.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces)
            }
        }

        let primaryIface = ifaceName ?? detectFallbackInterfaceName() ?? "en0"
        return parseInterfaceDetails(iface: primaryIface, gateway: gatewayIP ?? "")
    }

    public func resolveActiveInterface() -> ActiveNetworkInterface? {
        Self.resolveActiveInterface()
    }

    nonisolated private static func detectFallbackInterfaceName() -> String? {
        let output = runCommand("/sbin/ifconfig", arguments: ["-l"])
        let ifaces = output.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        for iface in ifaces {
            if iface.hasPrefix("lo") || iface.hasPrefix("utun") || iface.hasPrefix("awdl") || iface.hasPrefix("llw") {
                continue
            }
            let check = runCommand("/sbin/ifconfig", arguments: [iface])
            if check.contains("status: active") && check.contains("inet ") {
                return iface
            }
        }
        return ifaces.first(where: { $0.hasPrefix("en") })
    }

    nonisolated private static func parseInterfaceDetails(iface: String, gateway: String) -> ActiveNetworkInterface? {
        let output = runCommand("/sbin/ifconfig", arguments: [iface])
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("inet ") {
                let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                guard parts.count >= 4 else { continue }
                let ip = parts[1]
                let netmaskToken = parts[3]
                var maskStr = "255.255.255.0"
                var prefix = 24

                if netmaskToken.hasPrefix("0x") {
                    let hex = String(netmaskToken.dropFirst(2))
                    if let val = UInt32(hex, radix: 16) {
                        let o1 = (val >> 24) & 0xFF
                        let o2 = (val >> 16) & 0xFF
                        let o3 = (val >> 8) & 0xFF
                        let o4 = val & 0xFF
                        maskStr = "\(o1).\(o2).\(o3).\(o4)"
                        prefix = val.nonzeroBitCount
                    }
                } else if let parsedMask = IPAddress.IPv4(netmaskToken) {
                    maskStr = netmaskToken
                    prefix = parsedMask.rawValue.nonzeroBitCount
                }

                var bcast: String?
                if let bcastIdx = parts.firstIndex(of: "broadcast"), bcastIdx + 1 < parts.count {
                    bcast = parts[bcastIdx + 1]
                }

                let cidr: String
                if let net = IPNetwork("\(ip)/\(prefix)") {
                    cidr = net.description
                } else {
                    cidr = "\(ip)/\(prefix)"
                }

                return ActiveNetworkInterface(
                    name: iface,
                    ipAddress: ip,
                    netmask: maskStr,
                    prefixLength: prefix,
                    gateway: gateway,
                    cidr: cidr,
                    broadcast: bcast
                )
            }
        }
        return nil
    }

    // MARK: - Dynamic Target IP Generation

    /// Generates usable host IP strings for a given CIDR network, capped at 1024 hosts for safety.
    nonisolated public func generateTargetIPs(cidr: String) -> [String] {
        guard let net = IPNetwork(cidr) else { return [] }
        guard case .v4(let startV4) = net.networkAddress else { return [] }

        let startRaw = startV4.rawValue
        let hostCount = Int(min(net.usableHostCount, 1024))
        var list: [String] = []
        list.reserveCapacity(hostCount)

        if net.prefixLength >= 31 {
            if let first = net.firstUsableAddress { list.append(first.description) }
            if net.prefixLength == 31, let last = net.lastUsableAddress { list.append(last.description) }
        } else {
            for i in 1...hostCount {
                let currentRaw = startRaw + UInt32(i)
                let o1 = (currentRaw >> 24) & 0xFF
                let o2 = (currentRaw >> 16) & 0xFF
                let o3 = (currentRaw >> 8) & 0xFF
                let o4 = currentRaw & 0xFF
                list.append("\(o1).\(o2).\(o3).\(o4)")
            }
        }
        return list
    }

    // MARK: - Active Subnet Sweep

    /// Rapid unprivileged sweep of target IPs with concurrency throttling and multi-vector probing.
    /// Uses concurrent TCP 80, 443, 445, and 22 probes to wake all live devices into Darwin ARP cache.
    /// Returns dictionary of [IPAddress: LatencyMs] for responsive hosts.
    public func sweepSubnet(
        cidr: String? = nil,
        onProgress: (@Sendable (_ phase: String, _ current: Int, _ total: Int) -> Void)? = nil
    ) async -> [String: Double] {
        let activeIface = resolveActiveInterface()
        let targetCIDR = cidr ?? activeIface?.cidr ?? "192.168.1.0/24"
        let targets = generateTargetIPs(cidr: targetCIDR)

        guard !targets.isEmpty else { return [:] }

        let total = targets.count
        var probedCount = 0
        var latencyMap: [String: Double] = [:]

        onProgress?("Sweeping Subnet \(targetCIDR) [Multi-Vector 80/443/445/22] (0/\(total) hosts)", 0, total)

        let batchSize = 32
        for batch in targets.chunked(into: batchSize) {
            if Task.isCancelled { break }

            await withTaskGroup(of: (String, Double?).self) { group in
                for targetIP in batch {
                    group.addTask {
                        let startTime = DispatchTime.now()
                        let finished = ThreadSafeAtomicFlag()
                        let probePorts: [UInt16] = [80, 443, 445, 22]

                        let connections: [NWConnection] = probePorts.compactMap { portNum in
                            guard let nwPort = NWEndpoint.Port(rawValue: portNum) else { return nil }
                            let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(targetIP), port: nwPort)
                            let params = NWParameters.tcp
                            params.prohibitExpensivePaths = false
                            return NWConnection(to: endpoint, using: params)
                        }

                        let isAlive = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                            for conn in connections {
                                conn.stateUpdateHandler = { state in
                                    switch state {
                                    case .ready, .waiting:
                                        if finished.testAndSet() {
                                            continuation.resume(returning: true)
                                        }
                                    case .failed:
                                        // TCP RST indicates host is alive and responded with a reset packet!
                                        if finished.testAndSet() {
                                            continuation.resume(returning: true)
                                        }
                                    default:
                                        break
                                    }
                                }
                                conn.start(queue: .global(qos: .utility))
                            }

                            DispatchQueue.global().asyncAfter(deadline: .now() + 0.14) {
                                if finished.testAndSet() {
                                    continuation.resume(returning: false)
                                }
                                for c in connections {
                                    c.cancel()
                                }
                            }
                        }

                        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000.0
                        return (targetIP, isAlive ? elapsed : nil)
                    }
                }

                for await (ip, latency) in group {
                    if let l = latency {
                        latencyMap[ip] = l
                    }
                }
            }

            probedCount += batch.count
            onProgress?("Sweeping Subnet \(targetCIDR) [Multi-Vector 80/443/445/22] (\(probedCount)/\(total) hosts)", probedCount, total)
        }

        return latencyMap
    }

    /// Backwards compatible sweep method.
    public func sweepActiveSubnet() async {
        _ = await sweepSubnet()
    }

    // MARK: - Inline Quick Port Scanner

    /// Performs an instantaneous parallel port audit of top enterprise and networking ports on a target host.
    public static func quickScanPorts(
        ip: String,
        ports: [Int] = [22, 53, 80, 443, 445, 548, 3389, 5000, 8080, 8443, 9100],
        timeoutSeconds: Double = 0.45
    ) async -> [Int] {
        await withTaskGroup(of: (Int, Bool).self) { group in
            for port in ports {
                group.addTask {
                    guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else {
                        return (port, false)
                    }
                    let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(ip), port: nwPort)
                    let params = NWParameters.tcp
                    params.prohibitExpensivePaths = false
                    let conn = NWConnection(to: endpoint, using: params)
                    let finished = ThreadSafeAtomicFlag()

                    let isOpen = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                        conn.stateUpdateHandler = { state in
                            switch state {
                            case .ready:
                                if finished.testAndSet() {
                                    continuation.resume(returning: true)
                                }
                            case .failed, .cancelled:
                                if finished.testAndSet() {
                                    continuation.resume(returning: false)
                                }
                            default:
                                break
                            }
                        }
                        conn.start(queue: .global(qos: .utility))
                        DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds) {
                            if finished.testAndSet() {
                                continuation.resume(returning: false)
                            }
                        }
                    }
                    conn.cancel()
                    return (port, isOpen)
                }
            }

            var openPorts: [Int] = []
            for await (port, isOpen) in group {
                if isOpen {
                    openPorts.append(port)
                }
            }
            return openPorts.sorted()
        }
    }

    // MARK: - Bonjour / mDNS Discovery

    public struct BonjourInfo: Sendable {
        public var hostname: String
        public var services: [String]
    }

    /// Discovers local Bonjour announcements across 18 common service protocols, returning both IP-mapped and Name-mapped maps.
    private func browseBonjourServices() async -> (byIP: [String: [String]], byName: [String: [String]]) {
        let collector = BonjourCollector()
        let serviceTypes: [(type: String, label: String)] = [
            ("_http._tcp", "HTTP"),
            ("_https._tcp", "HTTPS"),
            ("_ssh._tcp", "SSH"),
            ("_smb._tcp", "SMB"),
            ("_airplay._tcp", "AirPlay"),
            ("_raop._tcp", "AirPlay Audio"),
            ("_googlecast._tcp", "Google Cast"),
            ("_printer._tcp", "Printer"),
            ("_ipp._tcp", "IPP"),
            ("_workstation._tcp", "Workstation"),
            ("_hap._tcp", "HomeKit"),
            ("_matter._tcp", "Matter"),
            ("_sonos._tcp", "Sonos"),
            ("_spotify-connect._tcp", "Spotify"),
            ("_hue._tcp", "Philips Hue"),
            ("_rtsp._tcp", "RTSP Camera"),
            ("_companion-link._tcp", "Apple Companion"),
            ("_scanner._tcp", "Scanner")
        ]

        await withTaskGroup(of: Void.self) { group in
            for s in serviceTypes {
                group.addTask {
                    let descriptor = NWBrowser.Descriptor.bonjour(type: s.type, domain: "local.")
                    let browser = NWBrowser(for: descriptor, using: .tcp)

                    browser.browseResultsChangedHandler = { results, _ in
                        for res in results {
                            if case .service(let name, _, _, let iface) = res.endpoint {
                                collector.append(name: name, label: s.label, iface: iface?.name ?? "en0")
                            }
                        }
                    }

                    browser.start(queue: .global(qos: .utility))
                    try? await Task.sleep(nanoseconds: 500_000_000) // 500ms discovery window
                    browser.cancel()
                }
            }
        }

        var servicesByName: [String: [String]] = [:]
        var servicesByIP: [String: [String]] = [:]

        for entry in collector.all() {
            let cleanHost = entry.name.replacingOccurrences(of: " ", with: "-")
            let localFQDN = "\(cleanHost).local"

            servicesByName[entry.name.lowercased(), default: []].append(entry.label)
            servicesByName[cleanHost.lowercased(), default: []].append(entry.label)

            // Resolve mDNS .local name to real IP address
            if let resolvedIP = resolveHostToIP(localFQDN) {
                servicesByIP[resolvedIP, default: []].append(entry.label)
            }
        }

        return (servicesByIP, servicesByName)
    }

    private func resolveHostToIP(_ host: String) -> String? {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &res) == 0, let addr = res else {
            return nil
        }
        defer { freeaddrinfo(res) }

        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        if addr.pointee.ai_family == AF_INET {
            let sin = addr.pointee.ai_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            var sinAddr = sin.sin_addr
            if inet_ntop(AF_INET, &sinAddr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil {
                let nulIndex = buffer.firstIndex(of: 0) ?? buffer.count
                return buffer[..<nulIndex].withUnsafeBufferPointer { ptr in
                    String(decoding: ptr.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                }
            }
        } else if addr.pointee.ai_family == AF_INET6 {
            let sin6 = addr.pointee.ai_addr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee }
            var sin6Addr = sin6.sin6_addr
            if inet_ntop(AF_INET6, &sin6Addr, &buffer, socklen_t(INET6_ADDRSTRLEN)) != nil {
                let nulIndex = buffer.firstIndex(of: 0) ?? buffer.count
                return buffer[..<nulIndex].withUnsafeBufferPointer { ptr in
                    String(decoding: ptr.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                }
            }
        }
        return nil
    }

    // MARK: - Concurrent Reverse DNS PTR Resolver

    private func resolveReverseDNSConcurrent(ips: [String]) async -> [String: String] {
        var map: [String: String] = [:]

        await withTaskGroup(of: (String, String?).self) { group in
            for ip in ips {
                group.addTask {
                    let name = Self.resolveReverseDNS(ip: ip)
                    return (ip, name)
                }
            }
            for await (ip, name) in group {
                if let name = name, !name.isEmpty {
                    map[ip] = name
                }
            }
        }
        return map
    }

    nonisolated public static func resolveReverseDNS(ip: String) -> String? {
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
            let nulIndex = hostBuffer.firstIndex(of: 0) ?? hostBuffer.count
            let name = hostBuffer[..<nulIndex].withUnsafeBufferPointer { ptr in
                String(decoding: ptr.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            }
            if !name.isEmpty && name != ip {
                return name
            }
        }
        return nil
    }

    // MARK: - Filtering & Eligibility

    private func isEligibleHost(ip: String, interface: String) -> Bool {
        let cleanIP = ip.components(separatedBy: "%").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ip
        let lower = cleanIP.lowercased()

        // Filter out IPv6 link-local addresses (fe80::/10)
        if lower.hasPrefix("fe8") || lower.hasPrefix("fe9") || lower.hasPrefix("fea") || lower.hasPrefix("feb") {
            return false
        }
        // Filter out IPv4 link-local (169.254.0.0/16)
        if lower.hasPrefix("169.254.") {
            return false
        }
        // Filter out loopback
        if lower == "127.0.0.1" || lower.hasPrefix("127.") || lower == "::1" {
            return false
        }
        // Filter out multicast
        if lower.hasPrefix("224.") || lower.hasPrefix("225.") || lower.hasPrefix("239.") || lower.hasPrefix("ff") {
            return false
        }
        // Filter out broadcast
        if lower.hasSuffix(".255") || lower == "255.255.255.255" {
            return false
        }
        // Filter out virtual/tunnel interfaces
        let lowerIface = interface.lowercased()
        if lowerIface.hasPrefix("lo") || lowerIface.hasPrefix("utun") || lowerIface.hasPrefix("awdl") || lowerIface.hasPrefix("llw") {
            return false
        }

        // If it's an IPv6 address, ensure it is a unique IPv6 (Global Unicast 2000::/3 or ULA fc00::/7)
        if cleanIP.contains(":") {
            guard let parsed = IPAddress(cleanIP), parsed.isUniqueIPv6 else {
                return false
            }
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
            let formattedMac = OUIResolver.normalizeMAC(rawMac)

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

    /// Parses output from `/usr/sbin/ndp -an`, extracting only unique/global IPv6 addresses (link-local excluded).
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
            let formattedMac = OUIResolver.normalizeMAC(rawMac)
            let cleanIP = rawIP.components(separatedBy: "%").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? rawIP

            // Strictly filter out link-local addresses (fe80::/10)
            let lower = cleanIP.lowercased()
            if lower.hasPrefix("fe8") || lower.hasPrefix("fe9") || lower.hasPrefix("fea") || lower.hasPrefix("feb") {
                continue
            }

            // Only accept unique IPv6 (Global Unicast 2000::/3 or ULA fc00::/7)
            guard let parsed = IPAddress(cleanIP), parsed.isUniqueIPv6 else {
                continue
            }

            let vendor = OUIResolver.resolve(mac: formattedMac)
            neighbors.append(DiscoveredNeighbor(
                ipAddress: cleanIP,
                ipv6Address: cleanIP,
                macAddress: formattedMac,
                interface: iface,
                discoverySource: .ndp,
                ouiVendor: vendor,
                discoveredServices: []
            ))
        }

        return neighbors
    }

    nonisolated private static func runCommand(_ executable: String, arguments: [String]) -> String {
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

            let normalized = OUIResolver.normalizeMAC(rawMac)
            let vendorName = OUIResolver.resolve(mac: normalized)
            let vendorEnum = OUIResolver.inferVendor(mac: normalized)

            return (normalized, vendorEnum, vendorName)
        } catch {
            return nil
        }
    }
}
