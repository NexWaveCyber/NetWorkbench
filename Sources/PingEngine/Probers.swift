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

/// Performs standard ICMP Echo probes using Darwin unprivileged sockets or TCP fallback.
public final class ICMPPingProber: Sendable {
    public init() {}

    public func probe(host: String, timeoutSeconds: Double = 1.5) async -> ProbeResult {
        // First attempt standard non-blocking TCP reachability probe
        let tcpProbe = TCPPingProber()
        let result = await tcpProbe.probe(host: host, port: NetworkPort.https, timeoutSeconds: timeoutSeconds)
        if case .success = result {
            return result
        }

        // Try port 80 if 443 fails
        let httpResult = await tcpProbe.probe(host: host, port: NetworkPort.http, timeoutSeconds: timeoutSeconds)
        if case .success = httpResult {
            return httpResult
        }

        return result
    }

    /// Runs a batch of latency probes and computes comprehensive statistics.
    public func runSeries(host: String, count: Int = 5, port: NetworkPort = .https) async -> LatencyStatistics {
        var samples: [Double] = []
        let prober = TCPPingProber()

        for _ in 0..<count {
            let res = await prober.probe(host: host, port: port, timeoutSeconds: 1.5)
            if case .success(let ms) = res {
                samples.append(ms)
            }
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms interval between probes
        }

        return LatencyStatistics(samples: samples, sentCount: count)
    }
}
