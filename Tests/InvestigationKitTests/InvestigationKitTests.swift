import Testing
import Foundation
import CryptoKit
@testable import InvestigationKit
@testable import PersistenceKit
@testable import DiagnosticsEngine
@testable import NetworkCore

@Suite("InvestigationKit Tests")
struct InvestigationKitTests {

    private func makeInMemoryDatabase() throws -> SQLiteDatabase {
        try SQLiteDatabase(path: ":memory:")
    }

    // MARK: - Test 1: Lifecycle & Status Transitions

    @Test("Investigation Creation and Status Lifecycle Progression")
    func testInvestigationLifecycle() throws {
        let db = try makeInMemoryDatabase()
        let manager = InvestigationManager(database: db)

        let inv = try manager.createInvestigation(
            title: "Core Transit BGP Flap",
            description: "Transit peer AS65001 dropping sessions",
            severity: .critical,
            commander: "Sarah Chen",
            affectedServices: ["BGP", "DirectConnect"],
            affectedDevices: ["edge-rtr01"],
            blastRadius: "14,000 corporate users"
        )

        #expect(inv.title == "Core Transit BGP Flap")
        #expect(inv.severity == .critical)
        #expect(inv.status == .open)
        #expect(inv.commander == "Sarah Chen")
        #expect(inv.affectedServices.count == 2)
        #expect(inv.affectedDevices.first == "edge-rtr01")

        // Initial timeline event logged
        let timeline = try manager.fetchTimeline(forInvestigationId: inv.id)
        #expect(timeline.count == 1)
        #expect(timeline.first?.title == "Investigation Opened")

        // Progress to Mitigating
        try manager.updateInvestigationStatus(id: inv.id, status: .mitigating)
        let listAfterMit = try manager.listInvestigations()
        let updatedMit = listAfterMit.first { $0.id == inv.id }
        #expect(updatedMit?.status == .mitigating)
        #expect(updatedMit?.mitigatedAt != nil)

        // Progress to Resolved
        try manager.updateInvestigationStatus(
            id: inv.id,
            status: .resolved,
            resolution: "Replaced SFP+ optic and cleaned fiber patch",
            rootCauseSummary: "Optical attenuation on TenGigE0/0/1"
        )

        let listAfterRes = try manager.listInvestigations()
        let updatedRes = listAfterRes.first { $0.id == inv.id }
        #expect(updatedRes?.status == .resolved)
        #expect(updatedRes?.resolvedAt != nil)
        #expect(updatedRes?.resolution == "Replaced SFP+ optic and cleaned fiber patch")

        let finalTimeline = try manager.fetchTimeline(forInvestigationId: inv.id)
        #expect(finalTimeline.count == 3) // Opened, Mitigating, Resolved
    }

    // MARK: - Test 2: SLA Metrics & MTTR Calculations

    @Test("SLA Targets and MTTR/MTTD Metric Calculations")
    func testSLAMetrics() {
        let detected = Date(timeIntervalSince1970: 1700000000)
        let created = Date(timeIntervalSince1970: 1700000300) // 5m detection-to-triage
        let mitigated = Date(timeIntervalSince1970: 1700001800) // 30m detection-to-mitigate
        let resolved = Date(timeIntervalSince1970: 1700003600) // 60m detection-to-resolve

        var inv = Investigation(
            title: "Test SLA Outage",
            severity: .critical,
            createdAt: created,
            detectedAt: detected,
            mitigatedAt: mitigated
        )
        inv.resolvedAt = resolved
        inv.status = .resolved

        #expect(inv.mttdMinutes == 5.0)
        #expect(inv.mttmMinutes == 30.0)
        #expect(inv.mttrMinutes == 60.0)
        #expect(inv.durationMinutes == 60.0)
        #expect(inv.severity.slaTargetMinutes == 60.0)
        #expect(!inv.isSLAOverdue) // Exactly on SLA target and resolved

        // Overdue Active SLA Test
        let overdueDetected = Date().addingTimeInterval(-7200) // 2 hours ago
        let overdueInv = Investigation(
            title: "Overdue Critical Incident",
            status: .open,
            severity: .critical, // 60m SLA target
            createdAt: overdueDetected,
            detectedAt: overdueDetected
        )
        #expect(overdueInv.durationMinutes >= 119.0)
        #expect(overdueInv.isSLAOverdue) // Breached
    }

    // MARK: - Test 3: Evidence Vault & SHA-256 Checksum

    @Test("Forensic Evidence Vault Attachment and SHA-256 Cryptographic Integrity")
    func testEvidenceVault() throws {
        let db = try makeInMemoryDatabase()
        let manager = InvestigationManager(database: db)

        let inv = try manager.createInvestigation(title: "Evidence Test")

        // 1. Text Evidence (CLI output)
        let cliText = "Interface TenGigE0/0/1 is Up, line protocol is Up\n5 minute input rate 842000 bits/sec, 842 packets/sec\n842 input errors, 842 CRC, 0 frame"
        let cliItem = try manager.attachEvidence(
            investigationId: inv.id,
            title: "Interface Error Counter Dump",
            filename: "show_interface.txt",
            type: .cliOutput,
            content: cliText,
            sourceWorkbench: "Config Studio",
            notes: "Recorded during peak CRC errors"
        )

        let expectedHash = SHA256.hash(data: Data(cliText.utf8)).compactMap { String(format: "%02x", $0) }.joined()
        #expect(cliItem.sha256 == expectedHash)
        #expect(cliItem.byteSize == cliText.utf8.count)
        #expect(cliItem.evidenceType == .cliOutput)

        // 2. Binary Data Evidence (Simulated PCAP capture)
        let samplePcapBytes: [UInt8] = [0xD4, 0xC3, 0xB2, 0xA1, 0x02, 0x00, 0x04, 0x00]
        let pcapData = Data(samplePcapBytes)
        let pcapItem = try manager.attachEvidenceData(
            investigationId: inv.id,
            title: "Malformed Frame Capture",
            filename: "crc_corrupted.pcap",
            type: .pcap,
            data: pcapData,
            sourceWorkbench: "Packet Workbench",
            notes: "First 8 bytes of PCAP header"
        )

        let expectedPcapHash = SHA256.hash(data: pcapData).compactMap { String(format: "%02x", $0) }.joined()
        #expect(pcapItem.sha256 == expectedPcapHash)
        #expect(pcapItem.byteSize == 8)

        // List and verify
        let evidenceList = try manager.listEvidence(forInvestigationId: inv.id)
        #expect(evidenceList.count == 2)

        // Delete evidence
        try manager.deleteEvidence(id: cliItem.id)
        let afterDelete = try manager.listEvidence(forInvestigationId: inv.id)
        #expect(afterDelete.count == 1)
        #expect(afterDelete.first?.id == pcapItem.id)
    }

    // MARK: - Test 4: Hypothesis Testing Matrix

    @Test("Hypothesis Testing Matrix Evaluation")
    func testHypothesisMatrix() throws {
        let db = try makeInMemoryDatabase()
        let manager = InvestigationManager(database: db)

        let inv = try manager.createInvestigation(title: "Hypothesis Test")

        let h1 = try manager.addHypothesis(
            investigationId: inv.id,
            statement: "Fiber cable damaged in riser shaft",
            proposedTest: "Run TDR diagnostics"
        )
        #expect(h1.status == .untested)

        let h2 = try manager.addHypothesis(
            investigationId: inv.id,
            statement: "Transceiver optical power degraded",
            proposedTest: "Read DOM optics"
        )

        // Confirm h2
        try manager.updateHypothesisStatus(
            id: h2.id,
            investigationId: inv.id,
            status: .confirmed,
            findings: "RX optical power dropped to -21.4 dBm"
        )

        // Refute h1
        try manager.updateHypothesisStatus(
            id: h1.id,
            investigationId: inv.id,
            status: .refuted,
            findings: "TDR reports 0 faults on physical pair"
        )

        let list = try manager.listHypotheses(forInvestigationId: inv.id)
        #expect(list.count == 2)
        #expect(list.first(where: { $0.id == h2.id })?.status == .confirmed)
        #expect(list.first(where: { $0.id == h1.id })?.status == .refuted)
    }

    // MARK: - Test 5: 5-Whys RCA Persistence

    @Test("5-Whys Root Cause Analysis Tree Persistence")
    func testFiveWhysRCA() throws {
        let db = try makeInMemoryDatabase()
        let manager = InvestigationManager(database: db)

        let inv = try manager.createInvestigation(title: "RCA Incident")

        let rca = InvestigationRCA(
            investigationId: inv.id,
            problemStatement: "Core BGP transit dropped 14,000 corporate clients",
            why1: "Why? BGP neighbor timed out",
            why2: "Why? Keepalives were dropped by interface",
            why3: "Why? Interface accumulated 842 CRC errors/sec",
            why4: "Why? Optical power dropped to -21.4 dBm",
            why5: "Why? Contaminated LC connector in patch rack 4B",
            rootCause: "Dirty fiber optic connector causing 6.2 dB attenuation",
            preventativeStrategy: "Mandate fiber cleaning and configure optical DOM threshold alerts"
        )

        try manager.saveRCA(rca)

        let fetched = try manager.fetchRCA(forInvestigationId: inv.id)
        #expect(fetched != nil)
        #expect(fetched?.problemStatement == "Core BGP transit dropped 14,000 corporate clients")
        #expect(fetched?.why1 == "Why? BGP neighbor timed out")
        #expect(fetched?.why5 == "Why? Contaminated LC connector in patch rack 4B")
        #expect(fetched?.rootCause == "Dirty fiber optic connector causing 6.2 dB attenuation")
    }

    // MARK: - Test 6: Action Item Checklist Progression

    @Test("Mitigation Runbook Action Items and Completion Progression")
    func testActionItems() throws {
        let db = try makeInMemoryDatabase()
        let manager = InvestigationManager(database: db)

        let inv = try manager.createInvestigation(title: "Action Item Test")

        let act1 = try manager.addActionItem(
            investigationId: inv.id,
            title: "Prepend BGP path to backup peer",
            phase: .mitigation,
            assignee: "Sarah Chen"
        )
        let act2 = try manager.addActionItem(
            investigationId: inv.id,
            title: "Verify packet loss returned to 0%",
            phase: .verification,
            assignee: "Alex Rivera"
        )
        _ = try manager.addActionItem(
            investigationId: inv.id,
            title: "Replace SFP+ optic",
            phase: .postMortem
        )

        let initial = try manager.listActionItems(forInvestigationId: inv.id)
        #expect(initial.count == 3)
        #expect(!initial[0].isCompleted)

        // Complete act1
        try manager.toggleActionItem(id: act1.id, investigationId: inv.id, isCompleted: true)
        let afterToggle = try manager.listActionItems(forInvestigationId: inv.id)
        let updatedAct1 = afterToggle.first { $0.id == act1.id }
        #expect(updatedAct1?.isCompleted == true)
        #expect(updatedAct1?.completedAt != nil)

        // Verify timeline logged action completion
        let timeline = try manager.fetchTimeline(forInvestigationId: inv.id)
        #expect(timeline.contains { $0.title.contains("Action Item Completed") })
    }

    // MARK: - Test 7: Timeline Chronological Ordering

    @Test("Timeline Event Chronological Ordering and Multi-Category Handling")
    func testTimelineOrdering() throws {
        let db = try makeInMemoryDatabase()
        let manager = InvestigationManager(database: db)

        let inv = try manager.createInvestigation(title: "Timeline Order Test")

        let baseTime = Date(timeIntervalSince1970: 1700000000)
        try manager.addTimelineEvent(investigationId: inv.id, title: "Step 1", detail: "Detection", category: "StatusChange", timestamp: baseTime)
        try manager.addTimelineEvent(investigationId: inv.id, title: "Step 3", detail: "Resolution", category: "Action", timestamp: baseTime.addingTimeInterval(300))
        try manager.addTimelineEvent(investigationId: inv.id, title: "Step 2", detail: "Triage", category: "Diagnostic", timestamp: baseTime.addingTimeInterval(120))

        let timeline = try manager.fetchTimeline(forInvestigationId: inv.id)
        #expect(timeline.count == 4) // Initial open + 3 steps

        let manualEvents = timeline.filter { $0.title.hasPrefix("Step") }
        #expect(manualEvents[0].title == "Step 1")
        #expect(manualEvents[1].title == "Step 2")
        #expect(manualEvents[2].title == "Step 3")
    }

    // MARK: - Test 8: Post-Mortem Generator Output

    @Test("Post-Mortem Generator Markdown, HTML, and Slack Formats")
    func testPostMortemGenerator() throws {
        let db = try makeInMemoryDatabase()
        let manager = InvestigationManager(database: db)

        let inv = try manager.createInvestigation(
            title: "Spanning Tree Protocol Loop Outage",
            description: "Datacenter broadcast storm caused by rogue BPDU",
            severity: .critical,
            commander: "Jordan Blake",
            affectedServices: ["Storage SAN", "Internal DNS"],
            blastRadius: "48 hosts, 420 VMs"
        )
        _ = try manager.attachEvidence(
            investigationId: inv.id,
            title: "STP Root Port Dump",
            filename: "show_spanning_tree.txt",
            type: .cliOutput,
            content: "Root ID Priority 4096 Port Gi2/0/12"
        )
        let rca = InvestigationRCA(
            investigationId: inv.id,
            problemStatement: "Broadcast storm on VLAN 10",
            why1: "Root bridge claimed by test switch",
            rootCause: "Missing BPDU Guard on access port"
        )
        try manager.saveRCA(rca)

        // 1. Markdown
        let md = try manager.generatePostMortemMarkdown(id: inv.id)
        #expect(md.contains("Incident Post-Mortem: Spanning Tree Protocol Loop Outage"))
        #expect(md.contains("Severity / Priority"))
        #expect(md.contains("Jordan Blake"))
        #expect(md.contains("Root Cause Analysis (RCA)"))
        #expect(md.contains("Forensic Evidence & Chain-of-Custody"))
        #expect(md.contains("show_spanning_tree.txt"))

        // 2. HTML
        let html = try manager.generatePostMortemHTML(id: inv.id)
        #expect(html.contains("<!DOCTYPE html>"))
        #expect(html.contains("INCIDENT POST-MORTEM REVIEW"))
        #expect(html.contains("Spanning Tree Protocol Loop Outage"))
        #expect(html.contains("Forensic Evidence Ledger"))

        // 3. Slack/Jira
        let slack = IncidentPostMortemGenerator.generateSlackJiraTriage(
            investigation: inv,
            timeline: try manager.fetchTimeline(forInvestigationId: inv.id),
            evidenceCount: 1,
            rca: rca
        )
        #expect(slack.contains("🚨 *INCIDENT TRIAGE:"))
        #expect(slack.contains("Commander*: `Jordan Blake`"))
    }

    // MARK: - Test 9: .nwi Bundle v2.0 Lossless Roundtrip

    @Test("NWI Archive Bundle v2.0 Lossless Export and Re-Import")
    func testNWIArchiveV2Roundtrip() throws {
        let db1 = try makeInMemoryDatabase()
        let manager1 = InvestigationManager(database: db1)

        let inv = try manager1.createInvestigation(
            title: "Full Bundle Incident",
            description: "Testing complete export serialization",
            severity: .high,
            commander: "Alex Mercer",
            affectedServices: ["Radius", "Wi-Fi"],
            blastRadius: "Campus North"
        )
        _ = try manager1.attachEvidence(
            investigationId: inv.id,
            title: "Radius Auth Trace",
            filename: "radius.log",
            type: .syslog,
            content: "Access-Request timeout"
        )
        _ = try manager1.addHypothesis(
            investigationId: inv.id,
            statement: "CRL sync lock deadlock"
        )
        _ = try manager1.addActionItem(
            investigationId: inv.id,
            title: "Restart FreeRADIUS service",
            phase: .mitigation
        )
        try manager1.saveRCA(InvestigationRCA(
            investigationId: inv.id,
            rootCause: "Single-threaded CRL fetch"
        ))

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_\(UUID().uuidString).nwi")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try manager1.exportInvestigationBundle(id: inv.id, to: tempURL, notes: "Exported drill")

        // Ingest into fresh database
        let db2 = try makeInMemoryDatabase()
        let manager2 = InvestigationManager(database: db2)

        let imported = try manager2.importInvestigationBundle(from: tempURL)
        #expect(imported.id == inv.id)
        #expect(imported.title == "Full Bundle Incident")
        #expect(imported.commander == "Alex Mercer")

        let importedEvidence = try manager2.listEvidence(forInvestigationId: imported.id)
        #expect(importedEvidence.count == 1)
        #expect(importedEvidence.first?.filename == "radius.log")

        let importedHypotheses = try manager2.listHypotheses(forInvestigationId: imported.id)
        #expect(importedHypotheses.count == 1)
        #expect(importedHypotheses.first?.statement == "CRL sync lock deadlock")

        let importedActions = try manager2.listActionItems(forInvestigationId: imported.id)
        #expect(importedActions.count == 1)
        #expect(importedActions.first?.title == "Restart FreeRADIUS service")

        let importedRCA = try manager2.fetchRCA(forInvestigationId: imported.id)
        #expect(importedRCA?.rootCause == "Single-threaded CRL fetch")
    }

    // MARK: - Test 10: Cascading SQLite Deletion

    @Test("Cascading Deletion of Sub-Entities upon Investigation Removal")
    func testCascadeDeletion() throws {
        let db = try makeInMemoryDatabase()
        let manager = InvestigationManager(database: db)

        let inv = try manager.createInvestigation(title: "Cascade Test")
        _ = try manager.attachEvidence(investigationId: inv.id, title: "Log", filename: "log.txt", type: .syslog, content: "err")
        _ = try manager.addHypothesis(investigationId: inv.id, statement: "Hypothesis A")
        _ = try manager.addActionItem(investigationId: inv.id, title: "Action A")
        try manager.saveRCA(InvestigationRCA(investigationId: inv.id, rootCause: "Bug"))

        // Delete investigation
        try manager.deleteInvestigation(id: inv.id)

        #expect(try manager.listInvestigations().isEmpty)
        #expect(try manager.fetchTimeline(forInvestigationId: inv.id).isEmpty)
        #expect(try manager.listEvidence(forInvestigationId: inv.id).isEmpty)
        #expect(try manager.listHypotheses(forInvestigationId: inv.id).isEmpty)
        #expect(try manager.listActionItems(forInvestigationId: inv.id).isEmpty)
        #expect(try manager.fetchRCA(forInvestigationId: inv.id) == nil)
    }
}
