import Foundation
import Network
import NetworkCore
import Darwin

public enum ProbeResult: Sendable {
    case success(latencyMs: Double)
    case timeout
    case error(String)

    public var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    public var latencyMs: Double? {
        if case .success(let ms) = self { return ms }
        return nil
    }
}

private final class ProbeCompletion: @unchecked Sendable {
    private var hasResumed = false
    private let lock = NSLock()
    private let connection: NWConnection
    private let continuation: CheckedContinuation<ProbeResult, Never>

    init(connection: NWConnection, continuation: CheckedContinuation<ProbeResult, Never>) {
        self.connection = connection
        self.continuation = continuation
    }

    func complete(with result: ProbeResult) {
        lock.lock()
        defer { lock.unlock() }
        if !hasResumed {
            hasResumed = true
            connection.cancel()
            continuation.resume(returning: result)
        }
    }
}

/// Measures TCP connection establishment latency.
public final class TCPPingProber: Sendable {
    public init() {}

    public func probe(host: String, port: NetworkPort = .https, timeoutSeconds: Double = 2.0) async -> ProbeResult {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port.rawValue)!
        )
        let parameters = NWParameters.tcp
        parameters.prohibitExpensivePaths = false

        let connection = NWConnection(to: endpoint, using: parameters)
        let startTime = DispatchTime.now()

        return await withCheckedContinuation { continuation in
            let completion = ProbeCompletion(connection: connection, continuation: continuation)

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000.0
                    completion.complete(with: .success(latencyMs: elapsed))
                case .failed(let err):
                    completion.complete(with: .error(err.localizedDescription))
                case .cancelled:
                    completion.complete(with: .timeout)
                default:
                    break
                }
            }

            connection.start(queue: .global(qos: .userInitiated))

            DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds) {
                completion.complete(with: .timeout)
            }
        }
    }
}

/// Performs standard ICMP Echo probes using Darwin native ping or TCP fallback.
public final class ICMPPingProber: Sendable {
    public init() {}

    public func probe(host: String, timeoutSeconds: Double = 1.5) async -> ProbeResult {
        let isIPv6 = host.contains(":")
        let binary = isIPv6 ? "/sbin/ping6" : "/sbin/ping"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: binary)
        let timeoutMs = Int(timeoutSeconds * 1000)
        task.arguments = isIPv6 ? ["-c", "1", "-q", host] : ["-c", "1", "-W", "\(timeoutMs)", "-q", host]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()

            if let out = String(data: data, encoding: .utf8), task.terminationStatus == 0 {
                if let rttLine = out.components(separatedBy: .newlines).first(where: { $0.contains("round-trip") || $0.contains("min/avg/max") }) {
                    let parts = rttLine.components(separatedBy: "=")
                    if parts.count >= 2 {
                        let values = parts[1].trimmingCharacters(in: .whitespaces).components(separatedBy: "/")
                        if values.count >= 2, let avg = Double(values[1]) {
                            return .success(latencyMs: avg)
                        }
                    }
                }
                return .success(latencyMs: 1.0)
            }
        } catch {
            // Fallback to TCP if ping fails to execute
        }

        // Fallback to TCP reachability probe
        let tcpProbe = TCPPingProber()
        return await tcpProbe.probe(host: host, port: .https, timeoutSeconds: timeoutSeconds)
    }

    /// Runs a batch of latency probes and computes comprehensive statistics.
    public func runSeries(host: String, count: Int = 5, port: NetworkPort = .https) async -> LatencyStatistics {
        let isIPv6 = host.contains(":")
        let binary = isIPv6 ? "/sbin/ping6" : "/sbin/ping"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: binary)
        task.arguments = isIPv6 ? ["-c", "\(count)", "-i", "0.1", host] : ["-c", "\(count)", "-i", "0.1", "-W", "1000", host]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        var samples: [Double] = []

        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()

            if let out = String(data: data, encoding: .utf8) {
                let lines = out.components(separatedBy: .newlines)
                for line in lines {
                    if line.contains("time=") {
                        let parts = line.components(separatedBy: "time=")
                        if parts.count >= 2 {
                            let msStr = parts[1].replacingOccurrences(of: " ms", with: "").trimmingCharacters(in: .whitespaces)
                            if let ms = Double(msStr) {
                                samples.append(ms)
                            }
                        }
                    }
                }
            }
        } catch {
            // Fallback to TCP if process execution fails
        }

        if !samples.isEmpty {
            return LatencyStatistics(samples: samples, sentCount: count)
        }

        // Fallback to TCPPingProber if ICMP is blocked or failed
        let prober = TCPPingProber()
        for _ in 0..<count {
            let res = await prober.probe(host: host, port: port, timeoutSeconds: 1.5)
            if case .success(let ms) = res {
                samples.append(ms)
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        return LatencyStatistics(samples: samples, sentCount: count)
    }
}
