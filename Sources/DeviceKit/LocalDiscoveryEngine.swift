import Foundation
import Network

/// High-speed local LAN neighbor discoverer using zero-root macOS neighbor tables and Bonjour.
public actor LocalDiscoveryEngine {
    public init() {}

    /// Discovers local network neighbors across ARP (IPv4) and NDP (IPv6) tables.
    public func discoverNeighbors() async -> [DiscoveredNeighbor] {
        var results: [String: DiscoveredNeighbor] = [:]

        // 1. Ingest IPv4 ARP cache
        let arpNeighbors = parseARPOutput(runCommand("/usr/sbin/arp", arguments: ["-an"]))
        for n in arpNeighbors {
            results[n.ipAddress] = n
        }

        // 2. Ingest IPv6 NDP cache
        let ndpNeighbors = parseNDPOutput(runCommand("/usr/sbin/ndp", arguments: ["-an"]))
        for n in ndpNeighbors {
            if var existing = results[n.ipAddress] {
                existing.discoveredServices.append(contentsOf: n.discoveredServices)
                results[n.ipAddress] = existing
            } else {
                results[n.ipAddress] = n
            }
        }

        return Array(results.values).sorted { $0.ipAddress < $1.ipAddress }
    }

    /// Parses output from `/usr/sbin/arp -an`.
    /// Typical line format:
    /// `? (192.168.1.1) at 0:1c:73:a1:b2:c3 on en0 ifscope [ethernet]`
    /// or `? (192.168.1.255) at (incomplete) on en0 [ethernet]`
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
    /// Typical line format:
    /// `Neighbor                             Linklayer Address  Netif Expire    St Flgs Prbs`
    /// `fe80::1%en0                          0:1c:73:a1:b2:c3   en0   23h59m59s R`
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
}
