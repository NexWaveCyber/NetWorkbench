import Foundation
import NetworkCore
import InternetIntel

public final class TracerouteRunner: Sendable {
    public init() {}

    /// Executes path discovery with bounded maximum hops.
    public func trace(target: String, maxHops: Int = 15) async -> PathObservation {
        let isIPv6 = target.contains(":")
        let binary = isIPv6 ? "/usr/sbin/traceroute6" : "/usr/sbin/traceroute"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: binary)
        // -q 1: 1 probe per hop for speed
        // -w 1: 1 second timeout
        // -m <maxHops>: maximum TTL hops
        // -n: print numeric addresses (fast, avoids slow reverse DNS hangs)
        task.arguments = ["-q", "1", "-w", "1", "-m", "\(maxHops)", "-n", target]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe() // Suppress stderr

        do {
            try task.run()
        } catch {
            return PathObservation(target: target, hops: [], finalHopReached: false)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else {
            return PathObservation(target: target, hops: [], finalHopReached: false)
        }

        var hops: [HopRecord] = []
        let lines = output.components(separatedBy: .newlines)
        var prevRtt: Double? = nil

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Skip traceroute header line (e.g. "traceroute to google.com (142.250.190.46)...")
            if trimmed.lowercased().hasPrefix("traceroute") { continue }

            let tokens = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard let hopNum = Int(tokens[0]) else { continue }

            if tokens.contains("*") {
                hops.append(HopRecord(hopNumber: hopNum, address: nil, hostname: nil, rttMs: nil, isTimeout: true))
            } else if tokens.count >= 3 {
                let ipStr = tokens[1]
                let rttStr = tokens[2]
                let rttMs = Double(rttStr)
                let delta: Double? = {
                    if let cur = rttMs, let prev = prevRtt {
                        return max(0.0, cur - prev)
                    }
                    return nil
                }()
                if let rtt = rttMs { prevRtt = rtt }

                // Quick ASN / Infrastructure Classification
                let isPrivate = ipStr.starts(with: "192.168.") || ipStr.starts(with: "10.") || ipStr.starts(with: "172.16.") || ipStr.starts(with: "172.31.")
                let asInfo: (asn: String?, asName: String?) = {
                    if isPrivate {
                        return (nil, hopNum == 1 ? "Default Gateway" : "Private Subnet")
                    } else if ipStr.starts(with: "1.1.1") || ipStr.starts(with: "1.0.0") {
                        return ("AS13335", "Cloudflare")
                    } else if ipStr.starts(with: "8.8.") || ipStr.starts(with: "142.250.") || ipStr.starts(with: "172.217.") {
                        return ("AS15169", "Google")
                    } else if ipStr.starts(with: "140.82.") || ipStr.starts(with: "20.205.") {
                        return ("AS36459", "GitHub / Microsoft")
                    }
                    return (nil, "Transit Provider")
                }()

                hops.append(HopRecord(
                    hopNumber: hopNum,
                    address: ipStr,
                    hostname: nil,
                    rttMs: rttMs,
                    isTimeout: false,
                    asn: asInfo.asn,
                    asName: asInfo.asName,
                    deltaMs: delta
                ))
            }
        }

        let reached = hops.last?.address == target || (hops.last?.rttMs != nil && !hops.isEmpty)
        return PathObservation(target: target, hops: hops, finalHopReached: reached)
    }
}
