import Testing
import Foundation
@testable import ConfigKit
@testable import NetworkCore

@Suite("ConfigKit Tests")
struct ConfigKitTests {

    let sampleCiscoConfig = """
    ! Current configuration: 4120 bytes
    !
    version 17.3
    service timestamps debug datetime msec
    service timestamps log datetime msec
    service password-encryption
    !
    hostname core-switch-01
    !
    enable secret 9 $9$W2.y5G0.11$fP2o3/ZlS6
    username admin privilege 15 secret 9 $9$m0129Fz81$abcdef123456
    !
    vlan 10
     name MANAGEMENT
    !
    vlan 20
     name USERS
    !
    interface GigabitEthernet0/0/0
     description UPLINK TO WAN ROUTER
     ip address 10.0.0.2 255.255.255.252
     no shutdown
     mtu 1500
    !
    interface GigabitEthernet0/0/1
     description ACCESS USERS
     switchport access vlan 20
     shutdown
    !
    interface GigabitEthernet0/0/2
     description TRUNK TO DISTRIBUTION
     switchport trunk allowed vlan 10,20,30-40
    !
    router bgp 65001
     bgp router-id 10.255.255.1
     neighbor 10.0.0.1 remote-as 65000
     neighbor 10.0.0.1 password 7 071B244F4D091A
    !
    ip access-list extended INET_INBOUND
     remark Allow established web traffic
     10 permit tcp any any established
     20 permit tcp any host 10.0.0.2 eq 443
     30 permit tcp any host 10.0.0.2 eq 80
     40 deny ip any any
    !
    snmp-server community MySecretStr RO
    !
    line con 0
     stopbits 1
    !
    end
    """

    @Test("Config Parser extracts hostname, blocks, and lines")
    func testConfigParser() {
        let parser = ConfigParser()
        let ast = parser.parse(text: sampleCiscoConfig)

        #expect(ast.vendor == .ciscoIOS)
        #expect(ast.hostname == "core-switch-01")
        #expect(!ast.blocks.isEmpty)
        #expect(!ast.allLines.isEmpty)

        // Check interfaces
        let intfs = parser.extractInterfaces(from: ast)
        #expect(intfs.count == 3)
        let g0 = intfs.first(where: { $0.name == "GigabitEthernet0/0/0" })
        #expect(g0 != nil)
        #expect(g0?.ipAddress == "10.0.0.2")
        #expect(g0?.isShutdown == false)
        #expect(g0?.mtu == 1500)

        let g1 = intfs.first(where: { $0.name == "GigabitEthernet0/0/1" })
        #expect(g1?.accessVlan == 20)
        #expect(g1?.isShutdown == true)

        let g2 = intfs.first(where: { $0.name == "GigabitEthernet0/0/2" })
        #expect(g2?.trunkAllowedVlans.contains(10) == true)
        #expect(g2?.trunkAllowedVlans.contains(35) == true)

        // Check Routing
        let routes = parser.extractRouting(from: ast)
        #expect(routes.count == 1)
        #expect(routes.first?.routingProtocol == .bgp)
        #expect(routes.first?.autonomousSystem == 65001)

        // Check ACLs
        let acls = parser.extractACLs(from: ast)
        #expect(acls.count == 1)
        let acl = acls.first
        #expect(acl?.name == "INET_INBOUND")
        #expect(acl?.rules.count == 4)
    }

    @Test("Secret Redactor replaces credentials with deterministic tokens")
    func testSecretRedactor() {
        let redactor = ConfigRedactor()
        let result = redactor.sanitize(text: sampleCiscoConfig)

        #expect(result.redactedCount >= 4)
        #expect(!result.sanitizedText.contains("MySecretStr"))
        #expect(!result.sanitizedText.contains("071B244F4D091A"))
        #expect(result.sanitizedText.contains("[REDACTED_SECRET_"))
    }

    @Test("Structural Diff detects interface and routing changes")
    func testStructuralDiff() {
        let modifiedConfig = sampleCiscoConfig
            .replacingOccurrences(of: "switchport access vlan 20", with: "switchport access vlan 30")
            .replacingOccurrences(of: "shutdown\n", with: "no shutdown\n")
            .replacingOccurrences(of: "neighbor 10.0.0.1 remote-as 65000", with: "neighbor 10.0.0.1 remote-as 65000\n neighbor 10.0.0.5 remote-as 65002")

        let engine = StructuralDiffEngine()
        let report = engine.compare(baseline: sampleCiscoConfig, target: modifiedConfig)

        #expect(!report.semanticChanges.isEmpty)
        let intfChange = report.semanticChanges.first(where: { $0.category == .interface && $0.changeType == .modified })
        #expect(intfChange != nil)
        #expect(intfChange?.detail.contains("VLAN: 20 ➔ 30") == true)

        let bgpNeighborChange = report.semanticChanges.first(where: { $0.category == .routing && $0.changeType == .added })
        #expect(bgpNeighborChange != nil)
        #expect(bgpNeighborChange?.detail.contains("10.0.0.5") == true)
    }

    @Test("ACL Flow Simulator permits allowed traffic and denies blocked traffic")
    func testACLFlowSimulator() {
        let parser = ConfigParser()
        let ast = parser.parse(text: sampleCiscoConfig)
        let acls = parser.extractACLs(from: ast)
        guard let acl = acls.first(where: { $0.name == "INET_INBOUND" }) else {
            Issue.record("ACL not found")
            return
        }

        let analyzer = ACLAnalyzer()

        // 1. Port 443 to 10.0.0.2 -> Should permit (rule 20)
        let flowHTTPS = PacketFlow(
            srcIP: "192.168.1.50",
            dstIP: "10.0.0.2",
            protocolType: .tcp,
            srcPort: 54321,
            dstPort: 443
        )
        let res1 = analyzer.evaluate(flow: flowHTTPS, against: acl)
        #expect(res1.action == .permit)
        #expect(res1.matchedRule?.sequence == 20)

        // 2. Port 22 (SSH) to 10.0.0.2 -> Should deny (rule 40)
        let flowSSH = PacketFlow(
            srcIP: "192.168.1.50",
            dstIP: "10.0.0.2",
            protocolType: .tcp,
            srcPort: 54321,
            dstPort: 22
        )
        let res2 = analyzer.evaluate(flow: flowSSH, against: acl)
        #expect(res2.action == .deny)
        #expect(res2.matchedRule?.sequence == 40)
    }

    @Test("ACL Shadowed Rule Detector flags dead rules")
    func testShadowedRules() {
        let shadowedACLConfig = """
        ip access-list extended SHADOW_TEST
         10 permit ip any any
         20 deny tcp any host 10.0.0.1 eq 22
         30 permit ip any any
        """
        let parser = ConfigParser()
        let ast = parser.parse(text: shadowedACLConfig)
        let acls = parser.extractACLs(from: ast)
        guard let acl = acls.first else {
            Issue.record("ACL not parsed")
            return
        }

        let analyzer = ACLAnalyzer()
        let findings = analyzer.detectShadowedRules(in: acl)

        #expect(findings.count >= 2)
        #expect(findings.contains(where: { $0.kind == .shadowed }))
        #expect(findings.contains(where: { $0.kind == .redundant }))
    }
}
