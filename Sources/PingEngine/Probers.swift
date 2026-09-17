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

public enum DarwinAddressResolver {
    public enum TargetFamily: Sendable {
        case ipv4(String)
        case ipv6(String)
    }

    /// Resolves any host string (IPv4 literal, IPv6 literal, or FQDN) to its specific IP address and family.
    public static func resolve(_ host: String) -> TargetFamily? {
        let clean = host.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")

        // Check if literal IPv6
        if clean.contains(":") {
            return .ipv6(clean)
        }
        // Check if literal IPv4
        if IPAddress.IPv4(clean) != nil {
            return .ipv4(clean)
        }

        // Hostname: resolve via POSIX getaddrinfo
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(clean, nil, &hints, &res) == 0, let head = res else {
            return nil
        }
        defer { freeaddrinfo(head) }

        var curr: UnsafeMutablePointer<addrinfo>? = head
        var v6Fallback: String? = nil

        while let c = curr {
            if c.pointee.ai_family == AF_INET {
                var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                let sin = c.pointee.ai_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                var addr = sin.sin_addr
                if inet_ntop(AF_INET, &addr, &buf, socklen_t(INET_ADDRSTRLEN)) != nil {
                    return .ipv4(String(cString: buf))
                }
            } else if c.pointee.ai_family == AF_INET6 && v6Fallback == nil {
                var buf = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                let sin6 = c.pointee.ai_addr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee }
                var addr6 = sin6.sin6_addr
                if inet_ntop(AF_INET6, &addr6, &buf, socklen_t(INET6_ADDRSTRLEN)) != nil {
                    v6Fallback = String(cString: buf)
                }
            }
            curr = c.pointee.ai_next
        }

        if let v6 = v6Fallback {
            return .ipv6(v6)
        }
        return nil
    }
}

/// Performs standard ICMP Echo probes using Darwin native ping or TCP fallback.
public final class ICMPPingProber: Sendable {
    public init() {}

    public func probe(host: String, timeoutSeconds: Double = 1.5, allowTCPFallback: Bool = false) async -> ProbeResult {
        let resolved = DarwinAddressResolver.resolve(host)
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
            isIPv6 = host.contains(":")
            destination = host
        }

        let binary = isIPv6 ? "/sbin/ping6" : "/sbin/ping"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: binary)
        let timeoutMs = Int(timeoutSeconds * 1000)
        task.arguments = isIPv6 ? ["-c", "1", "-q", destination] : ["-c", "1", "-W", "\(timeoutMs)", "-q", destination]

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
            // Process launch failure
        }

        if allowTCPFallback {
            let tcpProbe = TCPPingProber()
            return await tcpProbe.probe(host: host, port: .https, timeoutSeconds: timeoutSeconds)
        }

        return .timeout
    }

    /// Runs a batch of latency probes and computes comprehensive statistics.
    public func runSeries(
        host: String,
        count: Int = 5,
        port: NetworkPort = .https,
        allowTCPFallback: Bool = false
    ) async -> LatencyStatistics {
        let resolved = DarwinAddressResolver.resolve(host)
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
            isIPv6 = host.contains(":")
            destination = host
        }

        let binary = isIPv6 ? "/sbin/ping6" : "/sbin/ping"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: binary)
        task.arguments = isIPv6 ? ["-c", "\(count)", "-i", "0.1", destination] : ["-c", "\(count)", "-i", "0.1", "-W", "1000", destination]

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
            // Process execution error
        }

        if !samples.isEmpty {
            return LatencyStatistics(samples: samples, sentCount: count, probeProtocol: .icmp, isFallback: false)
        }

        if allowTCPFallback {
            let prober = TCPPingProber()
            var tcpSamples: [Double] = []
            for _ in 0..<count {
                let res = await prober.probe(host: host, port: port, timeoutSeconds: 1.5)
                if case .success(let ms) = res {
                    tcpSamples.append(ms)
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            if !tcpSamples.isEmpty {
                return LatencyStatistics(samples: tcpSamples, sentCount: count, probeProtocol: .tcp, isFallback: true)
            }
        }

        // Return honest ICMP packet loss (0 samples received = 100% loss)
        return LatencyStatistics(samples: [], sentCount: count, probeProtocol: .icmp, isFallback: false)
    }
}
