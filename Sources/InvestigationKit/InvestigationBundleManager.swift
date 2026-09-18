import Foundation
import PersistenceKit

/// Manages serialization, file packaging, and database import for `.nwi` investigation bundles
public enum InvestigationBundleManager {

    /// Creates an `.nwi` v2.0 JSON/archive bundle payload
    public static func createBundle(
        investigation: InvestigationRecord,
        timelineEvents: [TimelineEventRecord] = [],
        evidenceItems: [EvidenceItemRecord] = [],
        hypotheses: [HypothesisRecord] = [],
        actionItems: [ActionItemRecord] = [],
        rca: InvestigationRCARecord? = nil,
        diagnostics: [DiagnosticHistoryRecord] = [],
        configFiles: [AttachedConfigFile] = [],
        pcapData: Data? = nil,
        notes: String = ""
    ) throws -> Data {
        let bundle = InvestigationBundle(
            version: "2.0",
            exportedAt: Date(),
            exportedBy: NSUserName(),
            investigation: investigation,
            timelineEvents: timelineEvents,
            evidenceItems: evidenceItems,
            hypotheses: hypotheses,
            actionItems: actionItems,
            rca: rca,
            diagnosticSnapshots: diagnostics,
            attachedConfigFiles: configFiles,
            packetCaptureBase64: pcapData?.base64EncodedString(),
            notes: notes
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(bundle)
    }

    /// Exports bundle data directly to a `.nwi` file URL
    public static func exportBundleToFile(
        investigation: InvestigationRecord,
        timelineEvents: [TimelineEventRecord] = [],
        evidenceItems: [EvidenceItemRecord] = [],
        hypotheses: [HypothesisRecord] = [],
        actionItems: [ActionItemRecord] = [],
        rca: InvestigationRCARecord? = nil,
        diagnostics: [DiagnosticHistoryRecord] = [],
        configFiles: [AttachedConfigFile] = [],
        pcapData: Data? = nil,
        notes: String = "",
        to url: URL
    ) throws {
        let data = try createBundle(
            investigation: investigation,
            timelineEvents: timelineEvents,
            evidenceItems: evidenceItems,
            hypotheses: hypotheses,
            actionItems: actionItems,
            rca: rca,
            diagnostics: diagnostics,
            configFiles: configFiles,
            pcapData: pcapData,
            notes: notes
        )
        try data.write(to: url, options: .atomic)
    }

    /// Decodes an `.nwi` bundle from raw Data
    public static func loadBundle(from data: Data) throws -> InvestigationBundle {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(InvestigationBundle.self, from: data)
    }

    /// Loads and parses an `.nwi` bundle from a file URL
    public static func loadBundle(from url: URL) throws -> InvestigationBundle {
        let data = try Data(contentsOf: url)
        return try loadBundle(from: data)
    }

    /// Ingests and persists an imported investigation bundle into SQLite
    public static func importIntoDatabase(
        bundle: InvestigationBundle,
        investigationRepo: InvestigationRepository,
        evidenceRepo: EvidenceRepository? = nil,
        hypothesisRepo: HypothesisRepository? = nil,
        actionItemRepo: ActionItemRepository? = nil,
        rcaRepo: RCARepository? = nil,
        historyRepo: DiagnosticHistoryRepository? = nil
    ) throws {
        try investigationRepo.insert(bundle.investigation)
        for event in bundle.timelineEvents {
            try investigationRepo.addTimelineEvent(event)
        }
        if let eRepo = evidenceRepo {
            for item in bundle.evidenceItems {
                try eRepo.insert(item)
            }
        }
        if let hRepo = hypothesisRepo {
            for hyp in bundle.hypotheses {
                try hRepo.insert(hyp)
            }
        }
        if let aRepo = actionItemRepo {
            for act in bundle.actionItems {
                try aRepo.insert(act)
            }
        }
        if let rRepo = rcaRepo, let rca = bundle.rca {
            try rRepo.insertOrUpdate(rca)
        }
        if let diagRepo = historyRepo {
            for diag in bundle.diagnosticSnapshots {
                try diagRepo.record(diag)
            }
        }
    }

    /// Formats an investigation bundle into a clean Slack / Jira incident triage markdown post
    public static func exportSlackJiraSummary(bundle: InvestigationBundle) -> String {
        IncidentPostMortemGenerator.generateSlackJiraTriage(
            investigation: Investigation(record: bundle.investigation),
            timeline: bundle.timelineEvents,
            evidenceCount: bundle.evidenceItems.count,
            rca: bundle.rca != nil ? InvestigationRCA(record: bundle.rca!) : nil
        )
    }

    /// Formats an investigation record and timeline into a clean Slack / Jira markdown triage snippet
    public static func exportSlackJiraSummary(
        investigation: InvestigationRecord,
        timeline: [TimelineEventRecord],
        notes: String = ""
    ) -> String {
        IncidentPostMortemGenerator.generateSlackJiraTriage(
            investigation: Investigation(record: investigation),
            timeline: timeline,
            evidenceCount: 0,
            rca: nil
        )
    }

    /// Pre-packaged realistic enterprise network incidents for training, drills, and demo triage
    public static func createDemoInvestigations() -> [InvestigationBundle] {
        let now = Date().timeIntervalSince1970

        // 1. Critical BGP Flap Incident
        let bgpId = "demo-bgp-incident-01"
        let bgpInv = InvestigationRecord(
            id: bgpId,
            title: "Core BGP Route Flap & Tier-1 Upstream Transit Loss",
            description: "Transit BGP peer AS65001 (198.51.100.1) experiencing repeated hold timer expiries and route withdrawals on TenGigE0/0/1.",
            status: "Monitoring",
            severity: "Critical",
            createdAt: now - 3600,
            updatedAt: now - 300,
            commander: "Sarah Chen (Principal NetOps Lead)",
            affectedServices: "BGP Transit, External API Gateway, Office VPN",
            affectedDevices: "edge-rtr01, edge-rtr02",
            blastRadius: "14,000 corporate users, 3 AWS DirectConnect routes",
            detectedAt: now - 3600,
            mitigatedAt: now - 1800,
            rootCauseCategory: "Hardware / Physical",
            rootCauseSummary: "Degraded SFP+ transceiver optical RX power (-21.4 dBm) causing CRC bursts and BGP hold timer drop."
        )
        let bgpEvents = [
            TimelineEventRecord(
                investigationId: bgpId,
                timestamp: now - 3600,
                title: "BGP Session Down Alert",
                detail: "%BGP-5-ADJCHANGE: neighbor 198.51.100.1 Down - BGP Notification sent (Hold Timer Expired)",
                category: "Syslog"
            ),
            TimelineEventRecord(
                investigationId: bgpId,
                timestamp: now - 3400,
                title: "Optical Transceiver Power Dip",
                detail: "Interface TenGigE0/0/1 input errors spiked to 842 CRC errs/sec. Optical RX power at -21.4 dBm (Threshold: -18.0 dBm).",
                category: "Diagnostic"
            ),
            TimelineEventRecord(
                investigationId: bgpId,
                timestamp: now - 1800,
                title: "Emergency BGP Path Prepend",
                detail: "Prepended AS path 3x to AS65001; primary transit traffic successfully shifted to backup Tier-1 peer AS65002.",
                category: "Action"
            ),
            TimelineEventRecord(
                investigationId: bgpId,
                timestamp: now - 300,
                title: "Transit Latency Normalized",
                detail: "Packet loss on external test probes reduced from 14.8% to 0.0%. Traffic balanced on secondary peer.",
                category: "StatusChange"
            )
        ]
        let bgpEvidence = [
            EvidenceItemRecord(
                id: "ev-bgp-01",
                investigationId: bgpId,
                title: "BGP Summary & Neighbor Counters",
                evidenceType: "cliOutput",
                filename: "show_ip_bgp_summary.txt",
                sha256: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
                byteSize: 1420,
                content: "BGP router identifier 198.51.100.2, local AS number 65999\nNeighbor 198.51.100.1 remote AS 65001, State = Active (HoldTimerExpired)\nLast reset 00:32:10, reset reason: Peer notification received\nInput queue: 0, Output queue: 0",
                sourceWorkbench: "Terminal & Console"
            ),
            EvidenceItemRecord(
                id: "ev-bgp-02",
                investigationId: bgpId,
                title: "Optical Transceiver DOM Telemetry",
                evidenceType: "diagnosticProbe",
                filename: "transceiver_dom_readout.json",
                sha256: "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9",
                byteSize: 680,
                content: "{\n  \"interface\": \"TenGigE0/0/1\",\n  \"optical_rx_dbm\": -21.4,\n  \"optical_tx_dbm\": -2.1,\n  \"alarm_status\": \"HIGH_ATTENUATION_WARNING\"\n}",
                sourceWorkbench: "Diagnostics"
            )
        ]
        let bgpHypotheses = [
            HypothesisRecord(
                id: "hyp-bgp-01",
                investigationId: bgpId,
                statement: "Upstream ISP AS65001 experienced internal core fiber cut.",
                status: "Refuted",
                proposedTest: "Check looking glass and ping peer loopback.",
                findings: "Peer responded to ICMP; issue isolated to our local ingress interface framing errors.",
                updatedAt: now - 3200
            ),
            HypothesisRecord(
                id: "hyp-bgp-02",
                investigationId: bgpId,
                statement: "Physical SFP+ optical power attenuation causing packet corruption and keepalive drop.",
                status: "Confirmed",
                proposedTest: "Read DOM optic diagnostics on edge-rtr01 TenGigE0/0/1.",
                findings: "RX optical power was -21.4 dBm (alarm threshold -18.0 dBm); optic fiber connector dirty/damaged.",
                updatedAt: now - 3000
            )
        ]
        let bgpActions = [
            ActionItemRecord(
                id: "act-bgp-01",
                investigationId: bgpId,
                title: "Prepend BGP AS path to shift traffic to AS65002",
                phase: "Mitigation",
                isCompleted: true,
                assignee: "Sarah Chen",
                completedAt: now - 1800
            ),
            ActionItemRecord(
                id: "act-bgp-02",
                investigationId: bgpId,
                title: "Verify packet loss returned to 0% across looking glass probes",
                phase: "Verification",
                isCompleted: true,
                assignee: "Alex Rivera",
                completedAt: now - 1500
            ),
            ActionItemRecord(
                id: "act-bgp-03",
                investigationId: bgpId,
                title: "Replace 10G-LR SFP+ optic and clean LC fiber bulkhead on rack 4 shelf B",
                phase: "PostMortem",
                isCompleted: false,
                assignee: "Field Tech Dispatch",
                notes: "Part # SFP-10G-LR= requested from spares depot."
            )
        ]
        let bgpRCA = InvestigationRCARecord(
            id: "rca-bgp-01",
            investigationId: bgpId,
            problemStatement: "Tier-1 BGP transit dropped intermittently every 90 seconds, causing packet loss and routing flapping for 14,000 corporate clients.",
            why1: "Why did traffic drop? Primary BGP neighbor went Down due to Hold Timer Expiry.",
            why2: "Why did hold timer expire? Ingress BGP keepalive packets were dropped by the interface MAC layer.",
            why3: "Why were packets dropped? TenGigE0/0/1 accumulated 842 CRC errors per second.",
            why4: "Why were there CRC errors? Optical signal power dropped below receiver sensitivity to -21.4 dBm.",
            why5: "Root Cause: Contaminated LC patch fiber connector in patch panel rack 4B caused 6.2 dB optical attenuation.",
            rootCause: "Dirty and scratched fiber patch optic connector causing optical attenuation beyond SFP+ receiver threshold.",
            preventativeStrategy: "Mandate optical scope inspection & cleaning before every patch insertion; set up automated DOM optic threshold alarms in SNMP Studio."
        )
        let bgpBundle = InvestigationBundle(
            version: "2.0",
            exportedAt: Date(),
            exportedBy: "Sarah Chen",
            investigation: bgpInv,
            timelineEvents: bgpEvents,
            evidenceItems: bgpEvidence,
            hypotheses: bgpHypotheses,
            actionItems: bgpActions,
            rca: bgpRCA,
            notes: "Ready for formal post-mortem review with infrastructure director."
        )

        // 2. Access Stack IDF-3 CRC Alignment Escalation
        let crcId = "demo-crc-incident-02"
        let crcInv = InvestigationRecord(
            id: crcId,
            title: "Access Stack IDF-3 PortChannel CRC Frame Escalation",
            description: "PortChannel 12 trunk uplink accumulating CRC and runt frames during peak building shifts.",
            status: "Open",
            severity: "High",
            createdAt: now - 7200,
            updatedAt: now - 1200,
            commander: "Marcus Vance",
            affectedServices: "Floor 3 VoIP Phones, Workstation Ethernet",
            affectedDevices: "sw-idf3-stack",
            blastRadius: "180 workstations, 95 VoIP handsets",
            detectedAt: now - 7200,
            rootCauseCategory: "Hardware / Physical",
            rootCauseSummary: "Impedance mismatch and bend radius violation on CAT6A riser cable at 42 meters."
        )
        let crcEvents = [
            TimelineEventRecord(
                investigationId: crcId,
                timestamp: now - 7100,
                title: "SNMP CRC Threshold Alert",
                detail: "PortChannel12 ifInErrors exceeded 5,000 threshold in 5-minute polling window.",
                category: "Diagnostic"
            ),
            TimelineEventRecord(
                investigationId: crcId,
                timestamp: now - 4500,
                title: "Cable Diagnostic TDR Execution",
                detail: "TDR test revealed impedance mismatch at 42 meters on member interface Gi1/0/48.",
                category: "Diagnostic"
            )
        ]
        let crcEvidence = [
            EvidenceItemRecord(
                id: "ev-crc-01",
                investigationId: crcId,
                title: "Interface Error Counter Dump",
                evidenceType: "cliOutput",
                filename: "show_interfaces_counters_errors.txt",
                sha256: "ca978112ca1bbdcafac231b39a23dc4da786eff8147c4e72b9807785afee48bb",
                byteSize: 840,
                content: "Port        Align-Err    FCS-Err   Xmit-Err    Rcv-Err   UnderSize\nGi1/0/48            0       8492          0       8492           0\nPo12                0       8492          0       8492           0",
                sourceWorkbench: "Config Workbench"
            )
        ]
        let crcHypotheses = [
            HypothesisRecord(
                id: "hyp-crc-01",
                investigationId: crcId,
                statement: "Duplex mismatch between access switch stack and core distributor.",
                status: "Refuted",
                proposedTest: "Verify speed/duplex negotiation on both ends.",
                findings: "Both ends auto-negotiated to 1000baseT Full-Duplex.",
                updatedAt: now - 5000
            ),
            HypothesisRecord(
                id: "hyp-crc-02",
                investigationId: crcId,
                statement: "Cable physical damage in riser shaft.",
                status: "Confirmed",
                proposedTest: "Run copper Time-Domain Reflectometry (TDR).",
                findings: "TDR reports fault open/reflection at 42m.",
                updatedAt: now - 4400
            )
        ]
        let crcActions = [
            ActionItemRecord(
                id: "act-crc-01",
                investigationId: crcId,
                title: "Remove Gi1/0/48 from PortChannel 12 to stop CRC corruption",
                phase: "Mitigation",
                isCompleted: true,
                assignee: "Marcus Vance",
                completedAt: now - 4000
            ),
            ActionItemRecord(
                id: "act-crc-02",
                investigationId: crcId,
                title: "Re-terminate CAT6A riser cable on patch panel keystone jack",
                phase: "PostMortem",
                isCompleted: false,
                assignee: "Cabling Contractor"
            )
        ]
        let crcRCA = InvestigationRCARecord(
            id: "rca-crc-01",
            investigationId: crcId,
            problemStatement: "VoIP call jitter and dropped packets on Floor 3 access switch stack.",
            why1: "Why? PortChannel 12 dropped 4.2% of packets.",
            why2: "Why? Member port Gi1/0/48 accumulated 8,492 FCS CRC checksum errors.",
            why3: "Why? High signal attenuation and crosstalk on twisted pair 3-6.",
            why4: "Why? Cable conductor pinched behind riser cable tray door at 42 meters.",
            why5: "Root Cause: Physical cable compression during HVAC duct installation.",
            rootCause: "Crushed CAT6A riser cable causing high capacitance and bit errors.",
            preventativeStrategy: "Inspect riser pathway and install protective conduit."
        )
        let crcBundle = InvestigationBundle(
            version: "2.0",
            exportedAt: Date(),
            exportedBy: "Marcus Vance",
            investigation: crcInv,
            timelineEvents: crcEvents,
            evidenceItems: crcEvidence,
            hypotheses: crcHypotheses,
            actionItems: crcActions,
            rca: crcRCA,
            notes: "Pending cabling contractor inspection."
        )

        // 3. Wi-Fi 6 802.1X Handshake Timeout Incident
        let wifiId = "demo-wifi-incident-03"
        let wifiInv = InvestigationRecord(
            id: wifiId,
            title: "Building C Wi-Fi 6 802.1X EAP Handshake Drop",
            description: "MacBook and iPhone clients encountering RADIUS timeout during AP roaming between AP-C102 and AP-C103.",
            status: "Resolved",
            severity: "Medium",
            createdAt: now - 14400,
            updatedAt: now - 1800,
            resolvedAt: now - 1800,
            resolution: "Restarted primary FreeRADIUS service and adjusted EAP-TLS retransmission timer from 3s to 5s.",
            commander: "Elena Rostova",
            affectedServices: "Corp-Secure Wi-Fi 6, 802.1X EAP-TLS",
            affectedDevices: "wlc-core-01, radius-srv01",
            blastRadius: "240 wireless roaming clients",
            detectedAt: now - 14400,
            mitigatedAt: now - 3600,
            rootCauseCategory: "Firmware / Software Bug",
            rootCauseSummary: "Deadlock in FreeRADIUS thread pool during CRL revocation list sync."
        )
        let wifiEvents = [
            TimelineEventRecord(
                investigationId: wifiId,
                timestamp: now - 14000,
                title: "4-Way Handshake Timeout Burst",
                detail: "WLC syslog reported 802.1X auth timeout on SSID 'Corp-Secure' for 28 concurrent clients.",
                category: "Syslog"
            ),
            TimelineEventRecord(
                investigationId: wifiId,
                timestamp: now - 3600,
                title: "RADIUS Server Failover Triggered",
                detail: "Switched WLC auth group to secondary FreeRADIUS node. Client auth latency dropped from 4,200ms to 18ms.",
                category: "Action"
            ),
            TimelineEventRecord(
                investigationId: wifiId,
                timestamp: now - 1800,
                title: "Incident Resolved",
                detail: "Roaming success rate restored to 99.8% across Building C.",
                category: "StatusChange"
            )
        ]
        let wifiEvidence = [
            EvidenceItemRecord(
                id: "ev-wifi-01",
                investigationId: wifiId,
                title: "WLC 802.1X Client Trace Log",
                evidenceType: "syslog",
                filename: "wlc_eap_timeout_trace.log",
                sha256: "3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855e",
                byteSize: 920,
                content: "*dot1x-ev: EAP: sending EAP-Request/Identity to client a4:83:e7:12:34:56\n*dot1x-ev: RADIUS: Access-Request sent to 10.10.5.10:1812\n*dot1x-err: RADIUS: No response from server (Timeout 5000ms)\n*dot1x-ev: Client a4:83:e7:12:34:56 state transitioned to AUTH_FAILED",
                sourceWorkbench: "Syslog Workspace"
            )
        ]
        let wifiHypotheses = [
            HypothesisRecord(
                id: "hyp-wifi-01",
                investigationId: wifiId,
                statement: "Client certificate expired on user devices.",
                status: "Refuted",
                proposedTest: "Check client cert validity dates.",
                findings: "User certificates are valid for 240 more days.",
                updatedAt: now - 13000
            ),
            HypothesisRecord(
                id: "hyp-wifi-02",
                investigationId: wifiId,
                statement: "Primary FreeRADIUS server thread starvation during daily CRL refresh.",
                status: "Confirmed",
                proposedTest: "Inspect radiusd thread state and memory.",
                findings: "RADIUS server worker threads blocked waiting for CRL download lock.",
                updatedAt: now - 4000
            )
        ]
        let wifiActions = [
            ActionItemRecord(
                id: "act-wifi-01",
                investigationId: wifiId,
                title: "Failover WLC to backup RADIUS server",
                phase: "Mitigation",
                isCompleted: true,
                assignee: "Elena Rostova",
                completedAt: now - 3600
            ),
            ActionItemRecord(
                id: "act-wifi-02",
                investigationId: wifiId,
                title: "Patch FreeRADIUS to version 3.2.3 with asynchronous CRL fetching",
                phase: "PostMortem",
                isCompleted: true,
                assignee: "Identity Services Eng",
                completedAt: now - 1800
            )
        ]
        let wifiRCA = InvestigationRCARecord(
            id: "rca-wifi-01",
            investigationId: wifiId,
            problemStatement: "Building C Wi-Fi clients failed 802.1X authentication and dropped off network.",
            why1: "Why? 4-way handshake timed out between AP and client.",
            why2: "Why? WLC did not receive RADIUS Access-Accept within 5 seconds.",
            why3: "Why? FreeRADIUS server stopped answering authentication queries.",
            why4: "Why? Worker thread pool locked waiting for single-threaded CRL download.",
            why5: "Root Cause: CRL distribution point URL was slow, causing synchronous deadlock of all RADIUS auth workers.",
            rootCause: "Synchronous CRL download blocking worker thread pool in legacy FreeRADIUS release.",
            preventativeStrategy: "Upgrade FreeRADIUS to 3.2.3; configure OCSP stapling and asynchronous CRL background caching."
        )
        let wifiBundle = InvestigationBundle(
            version: "2.0",
            exportedAt: Date(),
            exportedBy: "Elena Rostova",
            investigation: wifiInv,
            timelineEvents: wifiEvents,
            evidenceItems: wifiEvidence,
            hypotheses: wifiHypotheses,
            actionItems: wifiActions,
            rca: wifiRCA,
            notes: "Resolved successfully."
        )

        // 4. STP Root Bridge Loop Incident (P1 Critical)
        let stpId = "demo-stp-incident-04"
        let stpInv = InvestigationRecord(
            id: stpId,
            title: "Datacenter Core Spanning Tree Protocol (STP) Root Bridge Flap",
            description: "Unmanaged switch plugged into access port triggered STP Topology Change Notifications (TCNs) and root bridge claim on VLAN 10.",
            status: "Resolved",
            severity: "Critical",
            createdAt: now - 21600,
            updatedAt: now - 7200,
            resolvedAt: now - 7200,
            resolution: "Enabled BPDU Guard on all access ports and configured Root Guard on distribution downlinks.",
            commander: "Jordan Blake (Lead Architect)",
            affectedServices: "Core Storage SAN, VMware ESXi Clusters, Internal DNS",
            affectedDevices: "dist-sw01, dist-sw02, acc-sw08",
            blastRadius: "Entire Datacenter Pod 2 (48 physical hosts, 420 VMs)",
            detectedAt: now - 21600,
            mitigatedAt: now - 18000,
            rootCauseCategory: "Configuration Drift",
            rootCauseSummary: "Access port Gi2/0/12 lacked 'spanning-tree bpduguard enable' and received rogue superior BPDU."
        )
        let stpEvents = [
            TimelineEventRecord(
                investigationId: stpId,
                timestamp: now - 21600,
                title: "STP Topology Change Notification Storm",
                detail: "%SPANTREE-2-CH_ALL: Spanning Tree Topology Change detected on VLAN 10 (Bridge ID claim: 4096.0011.2233.4455)",
                category: "Syslog"
            ),
            TimelineEventRecord(
                investigationId: stpId,
                timestamp: now - 18000,
                title: "Port Disabled via PortFast BPDU Guard",
                detail: "Interface Gi2/0/12 administratively shut down; root bridge ownership restored to core-sw01 (Priority 0).",
                category: "Action"
            )
        ]
        let stpEvidence = [
            EvidenceItemRecord(
                id: "ev-stp-01",
                investigationId: stpId,
                title: "Spanning Tree Root Bridge State",
                evidenceType: "cliOutput",
                filename: "show_spanning_tree_vlan_10.txt",
                sha256: "4a44dc5566778899aabbccddeeff00112233445566778899aabbccddeeff0011",
                byteSize: 1100,
                content: "VLAN0010\n  Spanning tree enabled protocol rstp\n  Root ID    Priority    4096\n             Address     0011.2233.4455\n             Cost        4\n             Port        256 (GigabitEthernet2/0/12)\n             Hello Time   2 sec  Max Age 20 sec  Forward Delay 15 sec",
                sourceWorkbench: "Config Workbench"
            )
        ]
        let stpHypotheses = [
            HypothesisRecord(
                id: "hyp-stp-01",
                investigationId: stpId,
                statement: "Distribution switch rebooted and lost root configuration.",
                status: "Refuted",
                proposedTest: "Check switch uptime and running-config.",
                findings: "Uptime was 340 days; priority remained at 0 in config.",
                updatedAt: now - 20000
            ),
            HypothesisRecord(
                id: "hyp-stp-02",
                investigationId: stpId,
                statement: "Rogue switch with priority 4096 connected to edge access port.",
                status: "Confirmed",
                proposedTest: "Trace root port on dist-sw01.",
                findings: "Root port was pointing to access switch acc-sw08 port Gi2/0/12 where a test switch was plugged in without BPDU Guard.",
                updatedAt: now - 18500
            )
        ]
        let stpActions = [
            ActionItemRecord(
                id: "act-stp-01",
                investigationId: stpId,
                title: "Shut down rogue port Gi2/0/12 on acc-sw08",
                phase: "Mitigation",
                isCompleted: true,
                assignee: "Jordan Blake",
                completedAt: now - 18000
            ),
            ActionItemRecord(
                id: "act-stp-02",
                investigationId: stpId,
                title: "Deploy global BPDU Guard audit across all 18 access switch stacks",
                phase: "PostMortem",
                isCompleted: true,
                assignee: "Jordan Blake",
                completedAt: now - 7200
            )
        ]
        let stpRCA = InvestigationRCARecord(
            id: "rca-stp-01",
            investigationId: stpId,
            problemStatement: "Datacenter Pod 2 experienced total broadcast storm and packet drop across all storage and management VLANs.",
            why1: "Why? Core switches flapped forwarding states and flooded broadcast packets.",
            why2: "Why? Root bridge election shifted away from core switch to edge switch.",
            why3: "Why? A rogue bridge BPDU with priority 4096 was accepted on access port Gi2/0/12.",
            why4: "Why did the access port accept BPDUs? The port lacked BPDU Guard configuration.",
            why5: "Root Cause: Access switch port provisioning template omitted 'spanning-tree bpduguard enable'.",
            rootCause: "Missing BPDU Guard hardening on access layer switchports.",
            preventativeStrategy: "Run CIS / STIG Hardening Auditor in Config Workbench and enforce Spanning Tree BPDU Guard globally."
        )
        let stpBundle = InvestigationBundle(
            version: "2.0",
            exportedAt: Date(),
            exportedBy: "Jordan Blake",
            investigation: stpInv,
            timelineEvents: stpEvents,
            evidenceItems: stpEvidence,
            hypotheses: stpHypotheses,
            actionItems: stpActions,
            rca: stpRCA,
            notes: "Post-mortem completed and compliance playbook enforced."
        )

        return [bgpBundle, crcBundle, wifiBundle, stpBundle]
    }
}
