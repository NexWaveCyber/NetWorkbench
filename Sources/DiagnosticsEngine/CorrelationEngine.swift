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
                    confidence: .high,
                    remediation: "Verify domain registrar status, authoritative nameservers, and check local resolver configuration via 'dscacheutil -flushcache'."
                ))
            } else {
                findings.append(DiagnosticFinding(
                    classification: .observed,
                    severity: .healthy,
                    title: "DNS Resolution Successful",
                    statement: "Resolved \(dns.hostname) in \(String(format: "%.1f", dns.queryTimeMs)) ms. IPv4: \(dns.ipv4Addresses.map(\.description).joined(separator: ", "))" +
                        (dns.ipv6Addresses.isEmpty ? "" : " | IPv6: \(dns.ipv6Addresses.map(\.description).joined(separator: ", "))"),
                    faultDomain: "Name Resolution / DNS",
                    confidence: .high,
                    remediation: nil
                ))

                // Rule: DNS Private RFC 1918 / Loopback leak for public domain
                let isPublicDomain = dns.hostname.contains(".") && !dns.hostname.hasSuffix(".local") && !dns.hostname.hasSuffix(".internal")
                let hasPrivateOnly = !dns.ipv4Addresses.isEmpty && dns.ipv4Addresses.allSatisfy { ip in
                    let s = ip.description
                    return s.starts(with: "10.") || s.starts(with: "192.168.") || s.starts(with: "127.") || s.starts(with: "172.16.") || s.starts(with: "172.31.")
                }
                if isPublicDomain && hasPrivateOnly {
                    findings.append(DiagnosticFinding(
                        classification: .inferred,
                        severity: .warning,
                        title: "DNS RFC 1918 Internal IP Leak",
                        statement: "Public domain '\(dns.hostname)' resolved exclusively to private/loopback addresses (\(dns.ipv4Addresses.map(\.description).joined(separator: ", "))).",
                        faultDomain: "Name Resolution / Security",
                        confidence: .high,
                        remediation: "Confirm whether split-horizon DNS or local DNS sinkhole (Pi-hole, enterprise gateway) is actively rerouting public traffic."
                    ))
                }
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
                confidence: .high,
                remediation: lat.lossPercentage > 0 ? "Investigate intermediary link saturation or Wi-Fi interference on current channel." : nil
            ))

            // Rule: Bufferbloat / Jitter Spike
            if lat.jitterMs > 20.0 || (lat.medianMs > 5.0 && lat.maxMs > lat.medianMs * 2.8) {
                findings.append(DiagnosticFinding(
                    classification: .inferred,
                    severity: .warning,
                    title: "Bufferbloat / High Jitter Detected",
                    statement: "RFC 3550 Jitter is \(String(format: "%.1f", lat.jitterMs)) ms with Max RTT (\(String(format: "%.1f", lat.maxMs)) ms) significantly exceeding median (\(String(format: "%.1f", lat.medianMs)) ms).",
                    faultDomain: "Transport / Queue Management",
                    confidence: .high,
                    remediation: "Enable Active Queue Management (FQ-CoDel or CAKE) on your local router or traffic-shape bandwidth-heavy background tasks."
                ))
            }

            // Rule: Intermittent Packet Loss
            if lat.lossPercentage > 0.0 && lat.lossPercentage < 100.0 {
                findings.append(DiagnosticFinding(
                    classification: .derived,
                    severity: .warning,
                    title: "Intermittent Packet Drop (\(String(format: "%.0f", lat.lossPercentage))%)",
                    statement: "\(lat.lost) of \(lat.sent) test probes were dropped. Intermittent loss causes severe TCP throughput degradation due to congestion window collapse.",
                    faultDomain: "Physical Link / Transport",
                    confidence: .high,
                    remediation: "Check Ethernet cable integrity, verify duplex negotiation (1000BASE-T Full Duplex), or reposition Wi-Fi antenna to improve SNR."
                ))
            }
        }

        // Canonical Case 1: ICMP fails/100% loss, but TCP port 443 succeeds
        if icmpLoss >= 100.0 && tcpOpen {
            findings.append(DiagnosticFinding(
                classification: .inferred,
                severity: .info,
                title: "ICMP Administratively Filtered",
                statement: "Target is reachable on TCP port 443 (\(String(format: "%.1f", tcp?.latencyMs ?? 0)) ms), but does not answer ICMP Echo Requests. Intermediary firewall or host OS is silently dropping ICMP.",
                faultDomain: "Perimeter Security / Firewall",
                confidence: .high,
                remediation: "No action required if intentional security policy; otherwise allow ICMP Type 8 / Type 0 on perimeter firewall."
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
                confidence: .high,
                remediation: "Verify that the web server (Nginx/Apache/Envoy) daemon is listening on port 443 and that local iptables/security groups permit inbound TCP 443."
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
                confidence: .high,
                remediation: nil
            ))

            // Rule: Routing Loop Detection
            var seenHops = Set<String>()
            var hasLoop = false
            for hop in path.hops {
                if let addr = hop.address, !addr.isEmpty {
                    if seenHops.contains(addr) {
                        hasLoop = true
                        break
                    }
                    seenHops.insert(addr)
                }
            }
            if hasLoop {
                findings.append(DiagnosticFinding(
                    classification: .inferred,
                    severity: .critical,
                    title: "Routing Loop Detected",
                    statement: "Identified recurring router IP across multiple hops in the traceroute path. Packets are circulating between intermediary routers until TTL expires.",
                    faultDomain: "Routing / Core Protocols",
                    confidence: .high,
                    remediation: "Inspect static route table entries, BGP route flaps, and dynamic routing convergence on intermediary gateways."
                ))
            }

            if let jumpHop = path.latencyJumpHop, let delta = path.latencyDeltaMs {
                findings.append(DiagnosticFinding(
                    classification: .inferred,
                    severity: .warning,
                    title: "Path Latency Anomaly",
                    statement: "Observed latency jump of +\(String(format: "%.1f", delta)) ms at hop \(jumpHop). Suggests transit congestion or autonomous system boundary crossing.",
                    faultDomain: "Upstream Transit WAN",
                    confidence: .medium,
                    remediation: "Evaluate upstream ISP peering and BGP AS path to determine if geographic route detour or transit congestion is occurring."
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
                        confidence: .high,
                        remediation: "Renew X.509 certificate immediately via ACME/Let's Encrypt or deploy renewed certificate to ingress reverse proxy."
                    ))
                } else if let days = cert.daysUntilExpiry, days < 30 {
                    findings.append(DiagnosticFinding(
                        classification: .derived,
                        severity: .warning,
                        title: "TLS Certificate Expiring Soon",
                        statement: "Certificate '\(cert.subjectSummary)' is valid for only \(days) more days.",
                        faultDomain: "TLS / PKI Certificate",
                        confidence: .high,
                        remediation: "Initiate certificate renewal workflow before expiration to prevent browser security warnings."
                    ))
                } else {
                    let daysDesc = cert.daysUntilExpiry.map { "\($0) days remaining" } ?? "valid"
                    findings.append(DiagnosticFinding(
                        classification: .observed,
                        severity: .healthy,
                        title: "TLS Handshake Valid",
                        statement: "Certificate '\(cert.subjectSummary)' valid (\(daysDesc)). Protocol: \(cert.protocolVersion ?? "TLS 1.3").",
                        faultDomain: "TLS / PKI Certificate",
                        confidence: .high,
                        remediation: nil
                    ))
                }

                // Rule: Weak/Legacy TLS protocol version
                if let proto = cert.protocolVersion, proto.contains("1.0") || proto.contains("1.1") {
                    findings.append(DiagnosticFinding(
                        classification: .inferred,
                        severity: .warning,
                        title: "Deprecated TLS Protocol (\(proto))",
                        statement: "Target negotiated legacy \(proto), which is deprecated by RFC 8996 due to known cryptographic vulnerabilities.",
                        faultDomain: "TLS / Security Configuration",
                        confidence: .high,
                        remediation: "Disable TLS 1.0/1.1 on web server; enforce minimum TLS 1.2 with forward secrecy cipher suites."
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
                    confidence: .medium,
                    remediation: "Profile application origin processing, database query response times, and consider edge caching / CDN CDN-Cache-Control."
                ))
            }

            if http.statusCode == 502 || http.statusCode == 504 {
                findings.append(DiagnosticFinding(
                    classification: .observed,
                    severity: .critical,
                    title: "Upstream Gateway Error (\(http.statusCode))",
                    statement: "Edge reverse proxy returned HTTP \(http.statusCode) (\(http.statusCode == 502 ? "Bad Gateway" : "Gateway Timeout")), indicating the backend origin application failed to respond.",
                    faultDomain: "Reverse Proxy / Upstream Origin",
                    confidence: .high,
                    remediation: "Check upstream service health (systemctl status / docker ps) and upstream proxy timeout settings (proxy_read_timeout)."
                ))
            } else if http.statusCode >= 500 {
                findings.append(DiagnosticFinding(
                    classification: .observed,
                    severity: .critical,
                    title: "HTTP Server Error (\(http.statusCode))",
                    statement: "Target origin responded with HTTP status \(http.statusCode).",
                    faultDomain: "Application / Web Server",
                    confidence: .high,
                    remediation: "Review server error logs (/var/log/nginx/error.log or application exception tracking)."
                ))
            } else if http.statusCode >= 200 && http.statusCode < 400 {
                findings.append(DiagnosticFinding(
                    classification: .observed,
                    severity: .healthy,
                    title: "HTTP Endpoint Operational",
                    statement: "HTTP response code: \(http.statusCode) OK. Total response time: \(String(format: "%.1f", http.totalTimeMs)) ms.",
                    faultDomain: "Application / Web Server",
                    confidence: .high,
                    remediation: nil
                ))
            }
        }

        return findings
    }
}
