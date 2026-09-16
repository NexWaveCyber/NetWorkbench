import Foundation
import NetworkCore
import DNSEngine
import PingEngine
import TracerouteEngine
import HTTPInspector

public enum DiagnosticStage: String, Sendable, CaseIterable {
    case resolvingDNS = "Resolving DNS & Host IP"
    case probingTCP = "Testing TCP Port Reachability"
    case measuringLatency = "Measuring Latency & Jitter"
    case tracingPath = "Discovering Path Hops"
    case inspectingHTTP = "Inspecting TLS & HTTP Response"
    case correlating = "Correlating Analytical Findings"
    case completed = "Diagnosis Completed"
}

public struct PipelineProgress: Sendable {
    public let stage: DiagnosticStage
    public let percentage: Double
    public let message: String

    public init(stage: DiagnosticStage, percentage: Double, message: String) {
        self.stage = stage
        self.percentage = percentage
        self.message = message
    }
}

/// Orchestrates the multi-layer diagnostic pipeline asynchronously.
public final class DiagnosticPipeline: Sendable {
    private let dnsResolver = DNSResolver()
    private let tcpProber = TCPPingProber()
    private let icmpProber = ICMPPingProber()
    private let tracerouteRunner = TracerouteRunner()
    private let httpInspector = HTTPInspector()

    public init() {}

    public func execute(
        target: NetworkTarget,
        customPort: NetworkPort? = nil,
        onProgress: (@Sendable (PipelineProgress) -> Void)? = nil
    ) async -> DiagnosticResult {
        let startTime = DispatchTime.now()
        let host = target.destinationHost
        let port = customPort ?? target.defaultPort

        // Stage 1: DNS Resolution
        onProgress?(PipelineProgress(stage: .resolvingDNS, percentage: 0.15, message: "Resolving \(host)..."))
        var dnsResult: DNSResolutionResult? = nil
        if target.targetType == .hostname || target.targetType == .url {
            dnsResult = await dnsResolver.resolve(hostname: host)
        }

        // Stages 2-5: Parallel Execution via Structured Concurrency
        onProgress?(PipelineProgress(stage: .probingTCP, percentage: 0.40, message: "Probing TCP port \(port.rawValue), ICMP, route hops, and HTTP/TLS in parallel..."))

        async let tcpTask = tcpProber.probe(host: host, port: port)
        async let latencyTask = icmpProber.runSeries(host: host, count: 5, port: port)
        async let pathTask = tracerouteRunner.trace(target: host, maxHops: 12)
        async let httpTask: HTTPObservation? = {
            if target.targetType == .hostname || target.targetType == .url {
                let useHTTPS = port.rawValue == 443 || port.rawValue == 8443 || (target.defaultPort.rawValue == 443 && port.rawValue != 80)
                return await httpInspector.inspect(targetHost: host, port: port, useHTTPS: useHTTPS)
            }
            return nil
        }()

        let (tcpResult, latencyStats, pathObservation, httpObservation) = await (tcpTask, latencyTask, pathTask, httpTask)

        // Stage 6: Deterministic Correlation
        onProgress?(PipelineProgress(stage: .correlating, percentage: 0.95, message: "Correlating multi-layer observations..."))
        let findings = CorrelationEngine.correlate(
            target: target,
            dns: dnsResult,
            latency: latencyStats,
            tcp: tcpResult,
            path: pathObservation,
            http: httpObservation
        )

        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000.0
        onProgress?(PipelineProgress(stage: .completed, percentage: 1.0, message: "Diagnosis complete in \(String(format: "%.1f", elapsedMs)) ms."))

        return DiagnosticResult(
            target: target,
            timestamp: Date(),
            dns: dnsResult,
            latency: latencyStats,
            tcp: tcpResult,
            path: pathObservation,
            http: httpObservation,
            findings: findings,
            executionDurationMs: elapsedMs
        )
    }
}
