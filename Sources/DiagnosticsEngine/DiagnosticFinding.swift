import Foundation
import NetworkCore
import DNSEngine
import PingEngine
import TracerouteEngine
import HTTPInspector

public enum FindingClassification: String, Sendable, CaseIterable {
    case observed = "Observed"   // Directly measured fact
    case derived = "Derived"     // Statistically calculated
    case inferred = "Inferred"   // Correlated diagnosis
}

public enum FindingSeverity: String, Sendable, CaseIterable {
    case healthy = "Healthy"
    case info = "Info"
    case warning = "Warning"
    case critical = "Critical"
}

public enum ConfidenceLevel: String, Sendable, CaseIterable {
    case high = "High"
    case medium = "Medium"
    case low = "Low"
}

/// A structured engineering finding with strict analytical classification.
public struct DiagnosticFinding: Hashable, Sendable, Identifiable {
    public let id: String
    public let classification: FindingClassification
    public let severity: FindingSeverity
    public let title: String
    public let statement: String
    public let faultDomain: String
    public let confidence: ConfidenceLevel
    public let remediation: String?

    public init(
        classification: FindingClassification,
        severity: FindingSeverity,
        title: String,
        statement: String,
        faultDomain: String,
        confidence: ConfidenceLevel,
        remediation: String? = nil
    ) {
        self.id = "\(classification.rawValue)_\(title)"
        self.classification = classification
        self.severity = severity
        self.title = title
        self.statement = statement
        self.faultDomain = faultDomain
        self.confidence = confidence
        self.remediation = remediation
    }
}

public enum OverallHealthStatus: String, Sendable {
    case healthy = "Healthy"
    case degraded = "Degraded"
    case critical = "Critical"
    case unreachable = "Unreachable"
}

/// The complete multi-layer diagnostic snapshot for a network target.
public struct DiagnosticResult: Sendable {
    public let target: NetworkTarget
    public let timestamp: Date
    public let dns: DNSResolutionResult?
    public let latency: LatencyStatistics?
    public let tcp: ProbeResult?
    public let path: PathObservation?
    public let http: HTTPObservation?
    public let findings: [DiagnosticFinding]
    public let overallStatus: OverallHealthStatus
    public let overallSummary: String
    public let executionDurationMs: Double

    public init(
        target: NetworkTarget,
        timestamp: Date = Date(),
        dns: DNSResolutionResult?,
        latency: LatencyStatistics?,
        tcp: ProbeResult?,
        path: PathObservation?,
        http: HTTPObservation?,
        findings: [DiagnosticFinding],
        executionDurationMs: Double = 0.0
    ) {
        self.target = target
        self.timestamp = timestamp
        self.dns = dns
        self.latency = latency
        self.tcp = tcp
        self.path = path
        self.http = http
        self.findings = findings
        self.executionDurationMs = executionDurationMs

        // Determine overall status
        if let dns = dns, !dns.isHealthy {
            self.overallStatus = .unreachable
            self.overallSummary = "DNS resolution failed. Target hostname cannot be resolved."
        } else if let tcp = tcp, !tcp.isSuccess && (latency?.received ?? 0) == 0 {
            self.overallStatus = .unreachable
            self.overallSummary = "Host unreachable. No response to TCP or ICMP probes."
        } else if findings.contains(where: { $0.severity == .critical }) {
            self.overallStatus = .critical
            self.overallSummary = findings.first(where: { $0.severity == .critical })?.statement ?? "Critical network anomalies detected."
        } else if findings.contains(where: { $0.severity == .warning }) {
            self.overallStatus = .degraded
            self.overallSummary = findings.first(where: { $0.severity == .warning })?.statement ?? "Network degraded."
        } else {
            self.overallStatus = .healthy
            self.overallSummary = "All network layers operational and within normal tolerances."
        }
    }
}
