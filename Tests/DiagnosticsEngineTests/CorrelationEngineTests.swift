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
    }
}
