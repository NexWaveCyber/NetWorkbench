import Testing
import Foundation
@testable import ReportingKit
import DeviceKit
import ConfigKit
import PacketKit

@Suite("ReportingKit Tests")
struct ReportingKitTests {

    @Test("Report Redactor sanitizes passwords, SNMP communities, and auth tokens")
    func zeroLeakRedaction() {
        let rawText = """
        Building configuration...
        username admin password SuperSecretPassword123
        snmp-server community CorpSNMPCommunity RO
        Authorization: Bearer confidential_access_token_987654321
        -----BEGIN RSA PRIVATE KEY-----
        MIIEowIBAAKCAQEA0Y1234567890abcdef
        -----END RSA PRIVATE KEY-----
        """

        let sanitized = ReportRedactor.sanitize(rawText)

        #expect(!sanitized.contains("SuperSecretPassword123"))
        #expect(!sanitized.contains("CorpSNMPCommunity"))
        #expect(!sanitized.contains("confidential_access_token_987654321"))
        #expect(!sanitized.contains("MIIEowIBAAKCAQEA0Y1234567890abcdef"))

        #expect(sanitized.contains("[REDACTED_PASSWORD_"))
        #expect(sanitized.contains("[REDACTED_SNMP_"))
        #expect(sanitized.contains("[REDACTED_BEARER_"))
        #expect(sanitized.contains("[REDACTED_PRIVATE_KEY_"))
    }

    @Test("Device Audit Report formats clean Markdown and valid JSON")
    func deviceAuditReporting() throws {
        let d1 = NetworkDevice(
            name: "Core-Switch-01",
            ipAddress: "10.0.0.1",
            vendor: .cisco,
            role: .switchRole,
            status: .online,
            tags: ["HQ", "Datacenter"]
        )
        let d2 = NetworkDevice(
            name: "Edge-Router-01",
            ipAddress: "192.168.1.1",
            vendor: .arista,
            role: .router,
            status: .online,
            tags: ["WAN"]
        )

        let mdReport = ReportEngine.generateDeviceAuditReport(devices: [d1, d2], format: .markdown)
        #expect(mdReport.content.contains("# Network Device Fleet Audit Report"))
        #expect(mdReport.content.contains("Core-Switch-01"))
        #expect(mdReport.content.contains("Edge-Router-01"))
        #expect(mdReport.content.contains("| **Core-Switch-01** | `10.0.0.1` |"))

        let jsonReport = ReportEngine.generateDeviceAuditReport(devices: [d1, d2], format: .json)
        let jsonData = Data(jsonReport.content.utf8)
        guard let jsonDict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            Issue.record("Failed to parse JSON report")
            return
        }

        #expect(jsonDict["deviceCount"] as? Int == 2)
        #expect(jsonDict["reportId"] != nil)
    }

    @Test("Config Diff Report formats semantic change tables and unified diff blocks")
    func configDiffReporting() {
        let change1 = SemanticChange(category: .interface, changeType: .added, title: "Interface", detail: "Interface GigabitEthernet0/1 added")
        let change2 = SemanticChange(category: .routing, changeType: .modified, title: "Routing", detail: "BGP peer 10.0.0.2 remote AS updated")
        let diffLine = DiffLine(id: 1, kind: .added, oldLineNumber: nil, newLineNumber: 1, text: "interface GigabitEthernet0/1")

        let diffReport = StructuralDiffReport(
            semanticChanges: [change1, change2],
            diffLines: [diffLine],
            addedCount: 1,
            removedCount: 0,
            modifiedCount: 1
        )

        let report = ReportEngine.generateConfigDiffReport(
            diff: diffReport,
            baselineName: "Router-Golden-Config",
            targetName: "Router-Running-Config",
            format: .markdown
        )

        #expect(report.content.contains("# Configuration Structural Audit Report"))
        #expect(report.content.contains("Router-Golden-Config"))
        #expect(report.content.contains("Router-Running-Config"))
        #expect(report.content.contains("Interface GigabitEthernet0/1 added"))
        #expect(report.content.contains("+ interface GigabitEthernet0/1"))
    }

    @Test("Packet Triage Report formats Markdown and JSON")
    func packetReportReporting() {
        let summary = PacketCaptureSummary(
            fileName: "capture.pcap",
            formatName: "PCAP (Classic)",
            totalPackets: 16,
            totalBytes: 2048,
            duration: 1.5,
            averageBitrateMbps: 0.01
        )
        let mdReport = ReportEngine.generatePacketReport(summary: summary, format: .markdown)
        #expect(mdReport.content.contains("# Packet Capture Triage Report"))
        #expect(mdReport.content.contains("capture.pcap"))

        let jsonReport = ReportEngine.generatePacketReport(summary: summary, format: .json)
        #expect(jsonReport.content.contains("totalPackets"))
    }
}
