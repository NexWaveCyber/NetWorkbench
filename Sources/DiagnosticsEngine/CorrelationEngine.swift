import Foundation
import NetworkCore
import DNSEngine
import PingEngine
import TracerouteEngine
import HTTPInspector

/// Deterministic correlation engine analyzing multi-layer network observations.
public struct CorrelationEngine: Sendable {
    public init() {}

    public static func correlate(
        target: NetworkTarget,
        dns: DNSResolutionResult?,
        latency: LatencyStatistics?,
        tcp: ProbeResult?,
        path: PathObservation?,
        http: HTTPObservation?
    ) -> [DiagnosticFinding] {
        var findings: [DiagnosticFinding] = []

        // MARK: - Layer 1: DNS Correlation
        if let dns = dns {
            if !dns.isHealthy {
                findings.append(DiagnosticFinding(
                    classification: .inferred,
                    severity: .critical,
                    title: "DNS Resolution Failure",
                    statement: "Hostname \(dns.hostname) failed to resolve across system resolvers: \(dns.errorMessage ?? "No records returned").",
                    faultDomain: "Name Resolution / DNS",
                    confidence: .high
                ))
            } else {
                findings.append(DiagnosticFinding(
                    classification: .observed,
                    severity: .healthy,
                    title: "DNS Resolution Successful",
                    statement: "Resolved \(dns.hostname) in \(String(format: "%.1f", dns.queryTimeMs)) ms. IPv4: \(dns.ipv4Addresses.map(\.description).joined(separator: ", "))" +
                        (dns.ipv6Addresses.isEmpty ? "" : " | IPv6: \(dns.ipv6Addresses.map(\.description).joined(separator: ", "))"),
                    faultDomain: "Name Resolution / DNS",
                    confidence: .high
                ))
            }
        }

        // MARK: - Layer 2: Transport & Latency Correlation
        let tcpOpen = tcp?.isSuccess ?? false
        let icmpReceived = (latency?.received ?? 0) > 0
        let icmpLoss = latency?.lossPercentage ?? 100.0

        if let lat = latency, lat.received > 0 {
            findings.append(DiagnosticFinding(
                classification: .derived,
                severity: lat.lossPercentage > 0 ? .warning : .healthy,
                title: "Path Latency Statistics",
                statement: "Median RTT: \(String(format: "%.1f", lat.medianMs)) ms (Min: \(String(format: "%.1f", lat.minMs)) ms, Max: \(String(format: "%.1f", lat.maxMs)) ms, P95: \(String(format: "%.1f", lat.p95Ms)) ms), Jitter: \(String(format: "%.1f", lat.jitterMs)) ms, Loss: \(String(format: "%.1f", lat.lossPercentage))%.",
                faultDomain: "Transport / Network Path",
                confidence: .high
            ))
        }

        // Canonical Case 1: ICMP fails/100% loss, but TCP port 443 succeeds
        if icmpLoss >= 100.0 && tcpOpen {
            findings.append(DiagnosticFinding(
                classification: .inferred,
                severity: .info,
                title: "ICMP Administratively Filtered",
                statement: "Target is reachable on TCP port 443 (\(String(format: "%.1f", tcp?.latencyMs ?? 0)) ms), but does not answer ICMP Echo Requests. Intermediary firewall or host OS is silently dropping ICMP.",
                faultDomain: "Perimeter Security / Firewall",
                confidence: .high
            ))
        }

        // Canonical Case 2: DNS succeeds, Ping succeeds, but TCP fails (Connection Refused or Timeout)
        if (dns?.isHealthy ?? true) && icmpReceived && !tcpOpen {
            findings.append(DiagnosticFinding(
                classification: .inferred,
                severity: .critical,
                title: "Transport Port Unreachable",
                statement: "Host is reachable at the IP layer via ICMP, but TCP port 443 failed to establish a handshake. Service daemon down or firewall filtering port 443.",
                faultDomain: "Target Host Service / Firewall",
                confidence: .high
            ))
        }

        // MARK: - Layer 3: Traceroute & Path Drift Correlation
        if let path = path {
            findings.append(DiagnosticFinding(
                classification: .observed,
                severity: .info,
                title: "Path Traversal",
                statement: "Traversed \(path.totalHops) hops to destination. \(path.finalHopReached ? "Destination reached." : "Path incomplete (final hop timed out).")",
                faultDomain: "Routing / IP Core",
                confidence: .high
            ))

            if let jumpHop = path.latencyJumpHop, let delta = path.latencyDeltaMs {
                findings.append(DiagnosticFinding(
                    classification: .inferred,
                    severity: .warning,
                    title: "Path Latency Anomaly",
                    statement: "Observed latency jump of +\(String(format: "%.1f", delta)) ms at hop \(jumpHop). Suggests transit congestion or autonomous system boundary crossing.",
                    faultDomain: "Upstream Transit WAN",
                    confidence: .medium
                ))
            }
        }

        // MARK: - Layer 4: TLS & Application Layer Correlation
        if let http = http {
            if let cert = http.certificateInfo {
                if cert.isExpired {
                    findings.append(DiagnosticFinding(
                        classification: .inferred,
                        severity: .critical,
                        title: "TLS Certificate Invalid or Expired",
                        statement: "Certificate issued to '\(cert.subjectSummary)' expired on \(cert.expirationDate?.formatted() ?? "unknown date").",
                        faultDomain: "TLS / PKI Certificate",
                        confidence: .high
                    ))
                } else if let days = cert.daysUntilExpiry, days < 30 {
                    findings.append(DiagnosticFinding(
                        classification: .derived,
                        severity: .warning,
                        title: "TLS Certificate Expiring Soon",
                        statement: "Certificate '\(cert.subjectSummary)' is valid for only \(days) more days.",
                        faultDomain: "TLS / PKI Certificate",
                        confidence: .high
                    ))
                } else {
                    findings.append(DiagnosticFinding(
                        classification: .observed,
                        severity: .healthy,
                        title: "TLS Handshake Valid",
                        statement: "Certificate '\(cert.subjectSummary)' valid (\(cert.daysUntilExpiry ?? 0) days remaining). Protocol: \(cert.protocolVersion ?? "TLS 1.3").",
                        faultDomain: "TLS / PKI Certificate",
                        confidence: .high
                    ))
                }
            }

            // Canonical Case 4: Transport healthy, but HTTP TTFB is excessively high (> 1000ms)
            if let ttfb = http.ttfbMs, ttfb > 1000.0 && tcpOpen {
                findings.append(DiagnosticFinding(
                    classification: .inferred,
                    severity: .warning,
                    title: "Elevated Application TTFB",
                    statement: "Network and TCP handshake completed in \(String(format: "%.1f", http.connectTimeMs ?? 0)) ms, but Time to First Byte was \(String(format: "%.1f", ttfb)) ms. Suggests application backend processing delay or cold start.",
                    faultDomain: "Application / Backend Origin",
                    confidence: .medium
                ))
            }

            if http.statusCode >= 500 {
                findings.append(DiagnosticFinding(
                    classification: .observed,
                    severity: .critical,
                    title: "HTTP Server Error (\(http.statusCode))",
                    statement: "Target origin responded with HTTP status \(http.statusCode).",
                    faultDomain: "Application / Web Server",
                    confidence: .high
                ))
            } else if http.statusCode >= 200 && http.statusCode < 400 {
                findings.append(DiagnosticFinding(
                    classification: .observed,
                    severity: .healthy,
                    title: "HTTP Endpoint Operational",
                    statement: "HTTP response code: \(http.statusCode) OK. Total response time: \(String(format: "%.1f", http.totalTimeMs)) ms.",
                    faultDomain: "Application / Web Server",
                    confidence: .high
                ))
            }
        }

        return findings
    }
}
