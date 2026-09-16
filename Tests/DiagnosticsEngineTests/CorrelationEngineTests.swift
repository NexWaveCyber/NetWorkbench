import Foundation
import Testing
@testable import NetworkCore
@testable import DiagnosticsEngine
@testable import DNSEngine
@testable import PingEngine
@testable import TracerouteEngine
@testable import HTTPInspector

@Suite("CorrelationEngine Deterministic Rules")
struct CorrelationEngineTests {
    @Test("Rule: DNS Resolution Failure")
    func testDNSFailureRule() {
        let target = TargetClassifier.classify("broken.internal.local")!
        let failedDNS = DNSResolutionResult(
            hostname: "broken.internal.local",
            resolverName: "System",
            records: [],
            ipv4Addresses: [],
            ipv6Addresses: [],
            queryTimeMs: 45.0,
            isHealthy: false,
            errorMessage: "nodename nor servname provided, or not known"
        )

        let findings = CorrelationEngine.correlate(
            target: target,
            dns: failedDNS,
            latency: nil,
            tcp: nil,
            path: nil,
            http: nil
        )

        #expect(findings.contains(where: { $0.faultDomain == "Name Resolution / DNS" && $0.severity == .critical }))
        #expect(findings.first?.classification == .inferred)
    }

    @Test("Rule: ICMP Filtered while TCP 443 Succeeds")
    func testICMPFilteredRule() {
        let target = TargetClassifier.classify("secure.example.com")!
        let dns = DNSResolutionResult(
            hostname: "secure.example.com",
            resolverName: "System",
            records: [DNSRecord(name: "secure.example.com", type: .a, value: "93.184.216.34")],
            ipv4Addresses: [IPAddress.IPv4("93.184.216.34")!],
            ipv6Addresses: [],
            queryTimeMs: 12.0,
            isHealthy: true
        )
        let latencyLoss = LatencyStatistics(samples: [], sentCount: 5) // 100% loss
        let tcpOpen = ProbeResult.success(latencyMs: 38.0)

        let findings = CorrelationEngine.correlate(
            target: target,
            dns: dns,
            latency: latencyLoss,
            tcp: tcpOpen,
            path: nil,
            http: nil
        )

        #expect(findings.contains(where: { $0.title == "ICMP Administratively Filtered" }))
        let finding = findings.first(where: { $0.title == "ICMP Administratively Filtered" })
        #expect(finding?.classification == .inferred)
        #expect(finding?.faultDomain == "Perimeter Security / Firewall")
    }

    @Test("Rule: Host Reachable via Ping but Port Unreachable")
    func testPortUnreachableRule() {
        let target = TargetClassifier.classify("host.corp.internal")!
        let dns = DNSResolutionResult(
            hostname: "host.corp.internal",
            resolverName: "System",
            records: [DNSRecord(name: "host.corp.internal", type: .a, value: "10.0.1.50")],
            ipv4Addresses: [IPAddress.IPv4("10.0.1.50")!],
            ipv6Addresses: [],
            queryTimeMs: 5.0,
            isHealthy: true
        )
        let latencyGood = LatencyStatistics(samples: [4.2, 4.5, 4.1], sentCount: 3)
        let tcpFailed = ProbeResult.error("Connection refused")

        let findings = CorrelationEngine.correlate(
            target: target,
            dns: dns,
            latency: latencyGood,
            tcp: tcpFailed,
            path: nil,
            http: nil
        )

        #expect(findings.contains(where: { $0.title == "Transport Port Unreachable" }))
        let finding = findings.first(where: { $0.title == "Transport Port Unreachable" })
        #expect(finding?.remediation != nil)
    }

    @Test("Rule: Severe Bufferbloat & Jitter Detection")
    func testBufferbloatRule() {
        let target = TargetClassifier.classify("laggy.stream.net")!
        // high jitter: min 10ms, max 180ms, jitter > 35ms
        let jitterStats = LatencyStatistics(samples: [10.0, 90.0, 15.0, 180.0, 20.0], sentCount: 5)
        let findings = CorrelationEngine.correlate(
            target: target,
            dns: nil,
            latency: jitterStats,
            tcp: nil,
            path: nil,
            http: nil
        )

        #expect(findings.contains(where: { $0.title == "Bufferbloat / High Jitter Detected" }))
        let finding = findings.first(where: { $0.title == "Bufferbloat / High Jitter Detected" })
        #expect(finding?.remediation != nil)
    }

    @Test("Rule: Routing Loop Detection")
    func testRoutingLoopRule() {
        let target = TargetClassifier.classify("looping.isp.net")!
        let hops = [
            HopRecord(hopNumber: 1, address: "192.168.1.1", hostname: nil, rttMs: 1.0, isTimeout: false),
            HopRecord(hopNumber: 2, address: "10.50.0.1", hostname: nil, rttMs: 15.0, isTimeout: false),
            HopRecord(hopNumber: 3, address: "10.50.0.2", hostname: nil, rttMs: 25.0, isTimeout: false),
            HopRecord(hopNumber: 4, address: "10.50.0.1", hostname: nil, rttMs: 35.0, isTimeout: false) // duplicate IP loop!
        ]
        let path = PathObservation(
            target: "looping.isp.net",
            hops: hops,
            finalHopReached: false
        )

        let findings = CorrelationEngine.correlate(
            target: target,
            dns: nil,
            latency: nil,
            tcp: nil,
            path: path,
            http: nil
        )

        #expect(findings.contains(where: { $0.title == "Routing Loop Detected" }))
        let finding = findings.first(where: { $0.title == "Routing Loop Detected" })
        #expect(finding?.severity == .critical)
        #expect(finding?.remediation != nil)
    }

    @Test("Rule: TLS Certificate Valid with Days Remaining")
    func testTLSCertificateValidRule() {
        let target = TargetClassifier.classify("apple.com")!
        let cert = TLSCertificateInfo(
            subjectSummary: "apple.com",
            issuerSummary: "Apple Public SubCA",
            expirationDate: Date().addingTimeInterval(90 * 86400),
            daysUntilExpiry: 90,
            isExpired: false,
            cipherSuite: "TLS_AES_128_GCM_SHA256",
            protocolVersion: "TLS 1.3"
        )
        let http = HTTPObservation(
            url: URL(string: "https://apple.com")!,
            statusCode: 200,
            httpVersion: "HTTP/2",
            redirectURL: nil,
            headers: [:],
            dnsTimeMs: 10.0,
            connectTimeMs: 25.0,
            tlsTimeMs: 30.0,
            ttfbMs: 65.0,
            totalTimeMs: 80.0,
            certificateInfo: cert,
            isHealthy: true,
            errorMessage: nil
        )

        let findings = CorrelationEngine.correlate(
            target: target,
            dns: nil,
            latency: nil,
            tcp: nil,
            path: nil,
            http: http
        )

        let validFinding = findings.first(where: { $0.title == "TLS Handshake Valid" })
        #expect(validFinding != nil)
        #expect(validFinding?.statement.contains("90 days remaining") == true)
        #expect(validFinding?.statement.contains("TLS 1.3") == true)
        #expect(validFinding?.severity == .healthy)
    }

    @Test("Rule: TLS Certificate Expiring Soon (< 30 days)")
    func testTLSCertificateExpiringSoonRule() {
        let target = TargetClassifier.classify("expiring.example.com")!
        let cert = TLSCertificateInfo(
            subjectSummary: "expiring.example.com",
            issuerSummary: "Let's Encrypt",
            expirationDate: Date().addingTimeInterval(14 * 86400),
            daysUntilExpiry: 14,
            isExpired: false,
            cipherSuite: "TLS_AES_128_GCM_SHA256",
            protocolVersion: "TLS 1.3"
        )
        let http = HTTPObservation(
            url: URL(string: "https://expiring.example.com")!,
            statusCode: 200,
            httpVersion: "HTTP/2",
            redirectURL: nil,
            headers: [:],
            dnsTimeMs: nil,
            connectTimeMs: nil,
            tlsTimeMs: nil,
            ttfbMs: nil,
            totalTimeMs: 50.0,
            certificateInfo: cert,
            isHealthy: true,
            errorMessage: nil
        )

        let findings = CorrelationEngine.correlate(
            target: target,
            dns: nil,
            latency: nil,
            tcp: nil,
            path: nil,
            http: http
        )

        let expiringFinding = findings.first(where: { $0.title == "TLS Certificate Expiring Soon" })
        #expect(expiringFinding != nil)
        #expect(expiringFinding?.severity == .warning)
        #expect(expiringFinding?.statement.contains("14 more days") == true)
    }

    @Test("Rule: TLS Certificate Expired")
    func testTLSCertificateExpiredRule() {
        let target = TargetClassifier.classify("expired.badssl.com")!
        let cert = TLSCertificateInfo(
            subjectSummary: "expired.badssl.com",
            issuerSummary: "DigiCert",
            expirationDate: Date().addingTimeInterval(-10 * 86400),
            daysUntilExpiry: -10,
            isExpired: true,
            cipherSuite: nil,
            protocolVersion: "TLS 1.2"
        )
        let http = HTTPObservation(
            url: URL(string: "https://expired.badssl.com")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            redirectURL: nil,
            headers: [:],
            dnsTimeMs: nil,
            connectTimeMs: nil,
            tlsTimeMs: nil,
            ttfbMs: nil,
            totalTimeMs: 45.0,
            certificateInfo: cert,
            isHealthy: true,
            errorMessage: nil
        )

        let findings = CorrelationEngine.correlate(
            target: target,
            dns: nil,
            latency: nil,
            tcp: nil,
            path: nil,
            http: http
        )

        let expiredFinding = findings.first(where: { $0.title == "TLS Certificate Invalid or Expired" })
        #expect(expiredFinding != nil)
        #expect(expiredFinding?.severity == .critical)
    }

    @Test("Rule: Deprecated TLS Protocol (TLS 1.0 / 1.1)")
    func testDeprecatedTLSProtocolRule() {
        let target = TargetClassifier.classify("tls-v1-0.badssl.com")!
        let cert = TLSCertificateInfo(
            subjectSummary: "tls-v1-0.badssl.com",
            issuerSummary: "DigiCert",
            expirationDate: Date().addingTimeInterval(60 * 86400),
            daysUntilExpiry: 60,
            isExpired: false,
            cipherSuite: "TLS_RSA_WITH_AES_128_CBC_SHA",
            protocolVersion: "TLS 1.0"
        )
        let http = HTTPObservation(
            url: URL(string: "https://tls-v1-0.badssl.com")!,
            statusCode: 200,
            httpVersion: "HTTP/1.0",
            redirectURL: nil,
            headers: [:],
            dnsTimeMs: nil,
            connectTimeMs: nil,
            tlsTimeMs: nil,
            ttfbMs: nil,
            totalTimeMs: 120.0,
            certificateInfo: cert,
            isHealthy: true,
            errorMessage: nil
        )

        let findings = CorrelationEngine.correlate(
            target: target,
            dns: nil,
            latency: nil,
            tcp: nil,
            path: nil,
            http: http
        )

        let deprecatedFinding = findings.first(where: { $0.title.contains("Deprecated TLS Protocol") })
        #expect(deprecatedFinding != nil)
        #expect(deprecatedFinding?.severity == .warning)
        #expect(deprecatedFinding?.statement.contains("RFC 8996") == true)
    }
}

