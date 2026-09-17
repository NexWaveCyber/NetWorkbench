import Foundation
import NetworkCore
import PingEngine
import InternetIntel

public final class TracerouteRunner: Sendable {
    private let intelEngine = InternetIntelEngine()

    public init() {}

    /// Executes path discovery with bounded maximum hops.
    /// Prefers unprivileged ICMP ECHO traceroute (-I) on macOS for superior firewall penetration.
    public func trace(target: String, maxHops: Int = 15, useICMP: Bool = true) async -> PathObservation {
        let resolved = DarwinAddressResolver.resolve(target)
        let isIPv6: Bool
        let destination: String

        switch resolved {
        case .ipv6(let ip):
            isIPv6 = true
            destination = ip
        case .ipv4(let ip):
            isIPv6 = false
            destination = ip
        case .none:
            isIPv6 = target.contains(":")
            destination = target
        }

        let binary = isIPv6 ? "/usr/sbin/traceroute6" : "/usr/sbin/traceroute"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: binary)

        // On macOS /usr/sbin/traceroute:
        // -I: ICMP ECHO packets (much better at bypassing UDP firewall drops)
        // -q 1: 1 probe per hop for rapid interactive completion
        // -w 1: 1 second timeout
        // -m <maxHops>: maximum TTL hops
        // -n: numeric addresses (prevents DNS timeouts on intermediate hops)
        if !isIPv6 && useICMP {
            task.arguments = ["-I", "-q", "1", "-w", "1", "-m", "\(maxHops)", "-n", destination]
        } else {
            task.arguments = ["-q", "1", "-w", "1", "-m", "\(maxHops)", "-n", destination]
        }

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

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

        // Temporary storage for raw parsed tokens
        struct RawHop {
            let hopNum: Int
            let ipStr: String?
            let rttMs: Double?
            let delta: Double?
            let isTimeout: Bool
        }
        var rawHops: [RawHop] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Skip header line
            if trimmed.lowercased().hasPrefix("traceroute") { continue }

            let tokens = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard let hopNum = Int(tokens[0]) else { continue }

            if tokens.contains("*") {
                rawHops.append(RawHop(hopNum: hopNum, ipStr: nil, rttMs: nil, delta: nil, isTimeout: true))
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

                rawHops.append(RawHop(hopNum: hopNum, ipStr: ipStr, rttMs: rttMs, delta: delta, isTimeout: false))
            }
        }

        // Asynchronously resolve ASNs in parallel for all discovered IPs
        for raw in rawHops {
            if raw.isTimeout || raw.ipStr == nil {
                hops.append(HopRecord(hopNumber: raw.hopNum, address: nil, hostname: nil, rttMs: nil, isTimeout: true))
            } else if let ip = raw.ipStr {
                let asInfo = await intelEngine.resolveASN(ip: ip, hopNumber: raw.hopNum)
                hops.append(HopRecord(
                    hopNumber: raw.hopNum,
                    address: ip,
                    hostname: nil,
                    rttMs: raw.rttMs,
                    isTimeout: false,
                    asn: asInfo.asn,
                    asName: asInfo.asName,
                    deltaMs: raw.delta
                ))
            }
        }

        let reached = hops.last?.address == destination || (hops.last?.rttMs != nil && !hops.isEmpty)
        return PathObservation(target: target, hops: hops, finalHopReached: reached)
    }
}
