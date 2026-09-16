import Foundation
import PersistenceKit

/// Manages serialization, file packaging, and database import for `.nwi` investigation bundles
public enum InvestigationBundleManager {

    /// Creates an `.nwi` JSON/archive bundle payload
    public static func createBundle(
        investigation: InvestigationRecord,
        timelineEvents: [TimelineEventRecord] = [],
        diagnostics: [DiagnosticHistoryRecord] = [],
        configFiles: [AttachedConfigFile] = [],
        pcapData: Data? = nil,
        notes: String = ""
    ) throws -> Data {
        let bundle = InvestigationBundle(
            investigation: investigation,
            timelineEvents: timelineEvents,
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
        diagnostics: [DiagnosticHistoryRecord] = [],
        configFiles: [AttachedConfigFile] = [],
        pcapData: Data? = nil,
        notes: String = "",
        to url: URL
    ) throws {
        let data = try createBundle(
            investigation: investigation,
            timelineEvents: timelineEvents,
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
        historyRepo: DiagnosticHistoryRepository? = nil
    ) throws {
        try investigationRepo.insert(bundle.investigation)
        for event in bundle.timelineEvents {
            try investigationRepo.addTimelineEvent(event)
        }
        if let hRepo = historyRepo {
            for diag in bundle.diagnosticSnapshots {
                try hRepo.record(diag)
            }
        }
    }

    /// Formats an investigation bundle into a clean Slack / Jira incident triage markdown post
    public static func exportSlackJiraSummary(bundle: InvestigationBundle) -> String {
        exportSlackJiraSummary(
            investigation: bundle.investigation,
            timeline: bundle.timelineEvents,
            notes: bundle.notes
        )
    }

    /// Formats an investigation record and timeline into a clean Slack / Jira markdown triage snippet
    public static func exportSlackJiraSummary(
        investigation: InvestigationRecord,
        timeline: [TimelineEventRecord],
        notes: String = ""
    ) -> String {
        let formatter = ISO8601DateFormatter()
        let createdDate = Date(timeIntervalSince1970: investigation.createdAt)
        let icon: String
        switch investigation.severity.lowercased() {
        case "critical": icon = "🚨"
        case "high": icon = "⚠️"
        case "medium": icon = "🟡"
        default: icon = "ℹ️"
        }

        var text = "\(icon) *INCIDENT TRIAGE: [\(investigation.severity.uppercased())] \(investigation.title)*\n"
        text += "*Status*: \(investigation.status) | *Logged*: \(formatter.string(from: createdDate))\n"
        if !investigation.description.isEmpty {
            text += "*Summary*: \(investigation.description)\n"
        }
        text += "------------------------------------------------------------\n"
        text += "*Chronological Timeline Findings (\(timeline.count) Events)*:\n"

        if timeline.isEmpty {
            text += "• No chronological events recorded yet.\n"
        } else {
            let sortedEvents = timeline.sorted { $0.timestamp < $1.timestamp }
            for event in sortedEvents.prefix(8) {
                let timeStr = Date(timeIntervalSince1970: event.timestamp).formatted(date: .omitted, time: .standard)
                text += "• `\(timeStr)` [\(event.category)] *\(event.title)*: \(event.detail)\n"
            }
            if sortedEvents.count > 8 {
                text += "• ... and \(sortedEvents.count - 8) additional diagnostic events in `.nwi` bundle.\n"
            }
        }

        if !notes.isEmpty {
            text += "------------------------------------------------------------\n"
            text += "*Engineering Notes / Next Steps*:\n\(notes)\n"
        }

        text += "------------------------------------------------------------\n"
        text += "_Exported via NexWave Studio Mac Network Workbench v1.1_\n"
        return text
    }

    /// Pre-packaged realistic enterprise network incidents for training, drills, and demo triage
    public static func createDemoInvestigations() -> [InvestigationBundle] {
        let now = Date().timeIntervalSince1970

        // 1. Critical BGP Flap Incident
        let bgpId = UUID().uuidString
        let bgpInv = InvestigationRecord(
            id: bgpId,
            title: "Core BGP Route Flap & Tier-1 Upstream Packet Loss",
            description: "Transit BGP peer AS65001 (198.51.100.1) experiencing repeated hold timer expiries and route withdrawals on TenGigE0/0/1.",
            status: "Monitoring",
            severity: "Critical",
            createdAt: now - 3600,
            updatedAt: now - 300
        )
        let bgpEvents = [
            TimelineEventRecord(
                investigationId: bgpId,
                timestamp: now - 3540,
                title: "BGP Session Down",
                detail: "%BGP-5-ADJCHANGE: neighbor 198.51.100.1 Down - BGP Notification sent (Hold Timer Expired)",
                category: "Diagnostic"
            ),
            TimelineEventRecord(
                investigationId: bgpId,
                timestamp: now - 3400,
                title: "FCS / CRC Error Burst",
                detail: "Interface TenGigE0/0/1 input errors spiked to 842 CRC errs/sec. Optical RX power at -21.4 dBm (Threshold: -18.0 dBm).",
                category: "Diagnostic"
            ),
            TimelineEventRecord(
                investigationId: bgpId,
                timestamp: now - 1800,
                title: "Rerouted Traffic to Secondary Transit",
                detail: "Prepended AS path to AS65001; primary traffic successfully shifted to AS65002 backup peer.",
                category: "Manual"
            )
        ]
        let bgpBundle = InvestigationBundle(
            version: "1.1",
            exportedAt: Date(),
            exportedBy: "NOC Lead Engineer",
            investigation: bgpInv,
            timelineEvents: bgpEvents,
            notes: "Pending vendor optic replacement on patch panel rack 4 shelf B."
        )

        // 2. Switch Stack FCS / CRC Alignment Escalation
        let crcId = UUID().uuidString
        let crcInv = InvestigationRecord(
            id: crcId,
            title: "Access Stack IDF-3 CRC Alignment Error Escalation",
            description: "PortChannel 12 trunk uplink accumulating CRC and runt frames during peak building shifts.",
            status: "Open",
            severity: "High",
            createdAt: now - 7200,
            updatedAt: now - 1200
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
                title: "Cable Diagnostic Test",
                detail: "TDR test revealed impedance mismatch at 42 meters on member interface Gi1/0/48.",
                category: "Diagnostic"
            )
        ]
        let crcBundle = InvestigationBundle(
            version: "1.1",
            exportedAt: Date(),
            exportedBy: "Infrastructure Eng",
            investigation: crcInv,
            timelineEvents: crcEvents,
            notes: "Dispatched field technician to inspect CAT6A patch cable and keystone jack."
        )

        // 3. Wi-Fi 6 802.1X Handshake Timeout Incident
        let wifiId = UUID().uuidString
        let wifiInv = InvestigationRecord(
            id: wifiId,
            title: "Building C Wi-Fi 6 802.1X EAP Handshake Drop",
            description: "MacBook and iPhone clients encountering RADIUS timeout during AP roaming between AP-C102 and AP-C103.",
            status: "Resolved",
            severity: "Medium",
            createdAt: now - 14400,
            updatedAt: now - 1800,
            resolvedAt: now - 1800,
            resolution: "Restarted primary FreeRADIUS service and adjusted EAP-TLS retransmission timer from 3s to 5s."
        )
        let wifiEvents = [
            TimelineEventRecord(
                investigationId: wifiId,
                timestamp: now - 14000,
                title: "4-Way Handshake Timeout",
                detail: "WLC syslog reported 802.1X auth timeout on SSID 'Corp-Secure' for 28 concurrent clients.",
                category: "Diagnostic"
            ),
            TimelineEventRecord(
                investigationId: wifiId,
                timestamp: now - 1800,
                title: "RADIUS Server Recovery",
                detail: "Auth latency normalized to 18ms. Roaming success rate restored to 99.8%.",
                category: "StatusChange"
            )
        ]
        let wifiBundle = InvestigationBundle(
            version: "1.1",
            exportedAt: Date(),
            exportedBy: "Wireless Specialist",
            investigation: wifiInv,
            timelineEvents: wifiEvents,
            notes: "Verified seamless roaming with 802.11k/v fast BSS transition."
        )

        return [bgpBundle, crcBundle, wifiBundle]
    }
}

