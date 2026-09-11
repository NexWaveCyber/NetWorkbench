import Foundation
import NetworkCore

public final class TracerouteRunner: Sendable {
    public init() {}

    /// Executes path discovery with bounded maximum hops.
    public func trace(target: String, maxHops: Int = 15) async -> PathObservation {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/traceroute")
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
                hops.append(HopRecord(hopNumber: hopNum, address: ipStr, hostname: nil, rttMs: rttMs, isTimeout: false))
            }
        }

        let reached = hops.last?.address == target || (hops.last?.rttMs != nil && !hops.isEmpty)
        return PathObservation(target: target, hops: hops, finalHopReached: reached)
    }
}
