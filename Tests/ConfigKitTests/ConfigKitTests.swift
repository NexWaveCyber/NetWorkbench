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

    @Test("Multi-Vendor Grammar Parsing for Junos and Fortinet")
    func testMultiVendorGrammarParsing() {
        let junosConfig = """
        system {
            host-name sfo-core-edge;
            domain-name corp.internal;
        }
        interfaces {
            ge-0/0/0 {
                unit 0 {
                    family inet {
                        address 10.50.1.1/30;
                    }
                }
            }
        }
        """
        let parser = ConfigParser()
        let ast = parser.parse(text: junosConfig)
        #expect(ast.vendor == .juniperJunos)
        #expect(ast.hostname == "sfo-core-edge")
        #expect(ast.domainName == "corp.internal")

        let intfs = parser.extractInterfaces(from: ast)
        #expect(intfs.count >= 1)
        #expect(intfs.first?.ipAddress == "10.50.1.1")
        #expect(intfs.first?.subnetMask == "255.255.255.252")

        let fortinetConfig = """
        config system global
            set hostname FGT-DATA-CENTER
        end
        config system interface
            edit "port1"
                set ip 172.16.10.1 255.255.255.0
            next
        end
        """
        let astFgt = parser.parse(text: fortinetConfig)
        #expect(astFgt.vendor == .fortinetFortiOS)
        #expect(astFgt.hostname == "FGT-DATA-CENTER")
        let intfsFgt = parser.extractInterfaces(from: astFgt)
        #expect(intfsFgt.count >= 1)
        #expect(intfsFgt.first?.ipAddress == "172.16.10.1")
    }

    @Test("CIS Hardening Compliance Auditor computes score and generates remediation playbook")
    func testComplianceAuditor() {
        let insecureConfig = """
        hostname vulnerable-router
        enable password PlainTextPassword123
        snmp-server community public RW
        line vty 0 4
         transport input telnet
         exec-timeout 0 0
        """
        let parser = ConfigParser()
        let ast = parser.parse(text: insecureConfig)
        let auditor = ComplianceAuditor()
        let report = auditor.audit(ast: ast, rawConfig: insecureConfig)

        #expect(report.totalScore < 60.0)
        #expect(report.failedRulesCount >= 3)
        #expect(report.findings.contains(where: { $0.ruleId == "CIS-1.2.1" && !$0.isCompliant })) // Telnet
        #expect(report.findings.contains(where: { $0.ruleId == "CIS-2.1.1" && !$0.isCompliant })) // SNMP public
        #expect(report.fullRemediationScript.contains("transport input ssh"))
        #expect(report.fullRemediationScript.contains("no snmp-server community public"))
    }

    @Test("Automated Semantic Rollback Generator creates accurate no-commands and warns on BGP teardown")
    func testRollbackGenerator() {
        let baseline = """
        hostname core-sw
        interface GigabitEthernet0/1
         description LAN
         switchport access vlan 10
         shutdown
        router bgp 65000
         neighbor 10.0.0.1 remote-as 65001
        """
        let target = """
        hostname core-sw
        interface GigabitEthernet0/1
         description LAN
         switchport access vlan 20
         no shutdown
        router bgp 65000
         neighbor 10.0.0.1 remote-as 65001
        router bgp 65999
         neighbor 172.16.0.1 remote-as 65998
        """
        let engine = StructuralDiffEngine()
        let report = engine.compare(baseline: baseline, target: target)

        let rollback = report.rollbackScript.rollbackCommands
        #expect(rollback.contains(where: { $0.contains("interface GigabitEthernet0/1") }))
        #expect(rollback.contains(where: { $0.contains("shutdown") }))
        #expect(rollback.contains(where: { $0.contains("no router bgp 65999") }))
        #expect(!report.rollbackScript.safetyWarnings.isEmpty)
    }

    @Test("Object-Group parsing and ACL resolution")
    func testObjectGroupResolution() {
        let configWithOG = """
        object-group network WEB_SERVERS
         host 10.0.0.10
         host 10.0.0.11
        !
        ip access-list extended SECURE_WEB
         10 permit tcp any object-group WEB_SERVERS eq 443
         20 deny ip any any
        """
        let parser = ConfigParser()
        let ast = parser.parse(text: configWithOG)
        #expect(ast.objectGroups.count == 1)
        #expect(ast.objectGroups.first?.name == "WEB_SERVERS")
        #expect(ast.objectGroups.first?.members.contains("10.0.0.10") == true)

        let acls = parser.extractACLs(from: ast)
        let acl = acls.first!
        let analyzer = ACLAnalyzer()

        // Flow to 10.0.0.10 -> Should permit because it matches WEB_SERVERS object-group
        let flow1 = PacketFlow(srcIP: "192.168.1.5", dstIP: "10.0.0.10", protocolType: .tcp, dstPort: 443)
        let res1 = analyzer.evaluate(flow: flow1, against: acl, objectGroups: ast.objectGroups)
        #expect(res1.action == .permit)
        #expect(res1.matchedRule?.sequence == 10)

        // Flow to 10.0.0.99 -> Should deny because it's not in WEB_SERVERS object-group
        let flow2 = PacketFlow(srcIP: "192.168.1.5", dstIP: "10.0.0.99", protocolType: .tcp, dstPort: 443)
        let res2 = analyzer.evaluate(flow: flow2, against: acl, objectGroups: ast.objectGroups)
        #expect(res2.action == .deny)
        #expect(res2.matchedRule?.sequence == 20)
    }
}
