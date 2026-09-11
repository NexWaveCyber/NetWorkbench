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
        onProgress: (@Sendable (PipelineProgress) -> Void)? = nil
    ) async -> DiagnosticResult {
        let host = target.destinationHost

        // Stage 1: DNS Resolution
        onProgress?(PipelineProgress(stage: .resolvingDNS, percentage: 0.15, message: "Resolving \(host)..."))
        var dnsResult: DNSResolutionResult? = nil
        if target.targetType == .hostname || target.targetType == .url {
            dnsResult = await dnsResolver.resolve(hostname: host)
        }

        // Stage 2: TCP Handshake Probing
        onProgress?(PipelineProgress(stage: .probingTCP, percentage: 0.35, message: "Testing TCP port \(target.defaultPort)..."))
        let tcpResult = await tcpProber.probe(host: host, port: target.defaultPort)

        // Stage 3: Measuring Latency & Jitter
        onProgress?(PipelineProgress(stage: .measuringLatency, percentage: 0.55, message: "Sampling round-trip latency..."))
        let latencyStats = await icmpProber.runSeries(host: host, count: 5, port: target.defaultPort)

        // Stage 4: Discovering Path Hops
        onProgress?(PipelineProgress(stage: .tracingPath, percentage: 0.70, message: "Tracing route hops (TTL 1..15)..."))
        let pathObservation = await tracerouteRunner.trace(target: host, maxHops: 12)

        // Stage 5: Inspecting TLS & HTTP
        onProgress?(PipelineProgress(stage: .inspectingHTTP, percentage: 0.85, message: "Inspecting HTTP/TLS application layer..."))
        var httpObservation: HTTPObservation? = nil
        if target.targetType == .hostname || target.targetType == .url {
            httpObservation = await httpInspector.inspect(targetHost: host, port: target.defaultPort, useHTTPS: true)
        }

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

        onProgress?(PipelineProgress(stage: .completed, percentage: 1.0, message: "Diagnosis complete."))

        return DiagnosticResult(
            target: target,
            timestamp: Date(),
            dns: dnsResult,
            latency: latencyStats,
            tcp: tcpResult,
            path: pathObservation,
            http: httpObservation,
            findings: findings
        )
    }
}
