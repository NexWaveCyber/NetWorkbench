import Foundation
import NetworkCore
import PersistenceKit

public enum IncidentPostMortemGenerator {

    // MARK: - Markdown Post-Mortem

    public static func generateMarkdown(
        investigation: Investigation,
        timeline: [TimelineEventRecord],
        evidence: [EvidenceItem],
        hypotheses: [InvestigationHypothesis],
        actionItems: [InvestigationActionItem],
        rca: InvestigationRCA?
    ) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short

        var md = "# 📋 Incident Post-Mortem: \(investigation.title)\n\n"
        md += "> **Confidential & Proprietary** — Internal Network Operations & Reliability Engineering Review\n\n"

        // Section 1: Executive Summary & SLA Metrics
        md += "## 1. Incident Overview & Key Metrics\n\n"
        md += "| Metric | Details |\n"
        md += "| :--- | :--- |\n"
        md += "| **Incident ID** | `\(investigation.id)` |\n"
        md += "| **Severity / Priority** | `\(investigation.severity.priorityPill)` |\n"
        md += "| **Lifecycle Status** | `\(investigation.status.rawValue)` |\n"
        md += "| **Incident Commander** | `\(investigation.commander ?? "Unassigned")` |\n"
        md += "| **Detection Time** | \(df.string(from: investigation.detectedAt)) |\n"
        if let mit = investigation.mitigatedAt {
            md += "| **Mitigation Time** | \(df.string(from: mit)) |\n"
        }
        if let res = investigation.resolvedAt {
            md += "| **Resolution Time** | \(df.string(from: res)) |\n"
        }
        md += "| **Total Outage Duration** | **\(String(format: "%.1f", investigation.durationMinutes)) minutes** |\n"
        if let mttm = investigation.mttmMinutes {
            md += "| **MTTM (Time to Mitigate)** | \(String(format: "%.1f", mttm)) minutes |\n"
        }
        if let mttr = investigation.mttrMinutes {
            md += "| **MTTR (Time to Resolve)** | \(String(format: "%.1f", mttr)) minutes |\n"
        }
        md += "| **SLA Target Compliance** | \(investigation.isSLAOverdue ? "⚠️ **SLA Breached**" : "✅ Within SLA Target (\(Int(investigation.severity.slaTargetMinutes))m)") |\n"
        md += "| **Blast Radius** | \(investigation.blastRadius ?? "Unspecified") |\n"
        md += "| **Affected Services** | \(investigation.affectedServices.isEmpty ? "None specified" : investigation.affectedServices.joined(separator: ", ")) |\n"
        md += "| **Affected Devices** | \(investigation.affectedDevices.isEmpty ? "None specified" : investigation.affectedDevices.joined(separator: ", ")) |\n\n"

        // Section 2: Executive Narrative & Impact
        md += "## 2. Executive Narrative & Impact\n\n"
        md += "\(investigation.description.isEmpty ? "No description provided." : investigation.description)\n\n"
        if let res = investigation.resolution, !res.isEmpty {
            md += "### Resolution Summary\n"
            md += "\(res)\n\n"
        }

        // Section 3: Root Cause Analysis (5-Whys)
        md += "## 3. Root Cause Analysis (RCA)\n\n"
        if let rca = rca, !rca.problemStatement.isEmpty {
            md += "### Problem Statement\n"
            md += "> \(rca.problemStatement)\n\n"
            md += "### The 5-Whys Causal Chain\n\n"
            if !rca.why1.isEmpty { md += "1. **Why?** \(rca.why1)\n" }
            if !rca.why2.isEmpty { md += "2. **Why?** \(rca.why2)\n" }
            if !rca.why3.isEmpty { md += "3. **Why?** \(rca.why3)\n" }
            if !rca.why4.isEmpty { md += "4. **Why?** \(rca.why4)\n" }
            if !rca.why5.isEmpty { md += "5. **Why?** \(rca.why5)\n" }
            md += "\n"
            if !rca.rootCause.isEmpty {
                md += "**Identified Root Cause**: \(rca.rootCause)\n\n"
            }
            if !rca.preventativeStrategy.isEmpty {
                md += "**Preventative Engineering Strategy**: \(rca.preventativeStrategy)\n\n"
            }
        } else if let summary = investigation.rootCauseSummary {
            md += "**Root Cause Category**: `\(investigation.rootCauseCategory?.rawValue ?? "Unclassified")`\n\n"
            md += "**Root Cause**: \(summary)\n\n"
        } else {
            md += "_Root cause analysis is currently in progress or not formally recorded._\n\n"
        }

        // Section 4: Hypothesis Testing Matrix
        if !hypotheses.isEmpty {
            md += "## 4. Hypothesis Testing Matrix\n\n"
            md += "| Hypothesis | Status | Proposed Verification Test | Findings |\n"
            md += "| :--- | :---: | :--- | :--- |\n"
            for h in hypotheses {
                let badge = h.status == .confirmed ? "✅ Confirmed" : (h.status == .refuted ? "❌ Refuted" : "⏳ \(h.status.rawValue)")
                md += "| \(h.statement) | \(badge) | \(h.proposedTest.isEmpty ? "—" : h.proposedTest) | \(h.findings.isEmpty ? "—" : h.findings) |\n"
            }
            md += "\n"
        }

        // Section 5: Chronological Incident Timeline
        md += "## 5. Chronological Incident Timeline\n\n"
        if timeline.isEmpty {
            md += "_No timeline events recorded._\n\n"
        } else {
            md += "| Timestamp | Category | Event / Observation | Details |\n"
            md += "| :--- | :---: | :--- | :--- |\n"
            let sorted = timeline.sorted { $0.timestamp < $1.timestamp }
            for e in sorted {
                let timeStr = Date(timeIntervalSince1970: e.timestamp).formatted(date: .omitted, time: .standard)
                md += "| `\(timeStr)` | `\(e.category)` | **\(e.title)** | \(e.detail.replacingOccurrences(of: "\n", with: " ")) |\n"
            }
            md += "\n"
        }

        // Section 6: Action Items & Remediation Checklist
        if !actionItems.isEmpty {
            md += "## 6. Action Items & Remediation Plan\n\n"
            md += "| Phase | Action Item | Assignee | Status | Completed At |\n"
            md += "| :---: | :--- | :---: | :---: | :---: |\n"
            for act in actionItems {
                let statusStr = act.isCompleted ? "✅ Done" : "⏳ Open"
                let compStr = act.completedAt != nil ? df.string(from: act.completedAt!) : "—"
                md += "| `\(act.phase.displayName)` | \(act.title) | \(act.assignee ?? "Unassigned") | \(statusStr) | \(compStr) |\n"
            }
            md += "\n"
        }

        // Section 7: Forensic Evidence Chain-of-Custody
        if !evidence.isEmpty {
            md += "## 7. Forensic Evidence & Chain-of-Custody\n\n"
            md += "| Evidence Artifact | Type | Size | SHA-256 Checksum | Source |\n"
            md += "| :--- | :---: | :---: | :--- | :---: |\n"
            for ev in evidence {
                let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(ev.byteSize), countStyle: .file)
                md += "| **\(ev.filename)**<br>_\(ev.title)_ | `\(ev.evidenceType.displayName)` | \(sizeStr) | `\(ev.sha256)` | `\(ev.sourceWorkbench)` |\n"
            }
            md += "\n"
        }

        md += "---\n"
        md += "_Generated by NexWave Studio Mac Network Workbench — Incident Management & Evidence Engine_\n"
        return md
    }

    // MARK: - Printable / Executive HTML Report

    public static func generateHTML(
        investigation: Investigation,
        timeline: [TimelineEventRecord],
        evidence: [EvidenceItem],
        hypotheses: [InvestigationHypothesis],
        actionItems: [InvestigationActionItem],
        rca: InvestigationRCA?
    ) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short

        let sevColor: String
        switch investigation.severity {
        case .critical: sevColor = "#ef4444"
        case .high: sevColor = "#f97316"
        case .medium: sevColor = "#f59e0b"
        case .low: sevColor = "#3b82f6"
        }

        var html = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="UTF-8">
        <title>Incident Post-Mortem — \(investigation.title)</title>
        <style>
            :root {
                --bg: #0f172a;
                --card-bg: #1e293b;
                --text-primary: #f8fafc;
                --text-secondary: #94a3b8;
                --accent: #00d2ff;
                --border: rgba(255,255,255,0.08);
                --emerald: #10b981;
                --crimson: #ef4444;
            }
            @media print {
                body { background: #fff !important; color: #000 !important; }
                .card { background: #f8fafc !important; border: 1px solid #e2e8f0 !important; }
            }
            body {
                font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
                background-color: var(--bg);
                color: var(--text-primary);
                line-height: 1.5;
                padding: 40px;
                max-width: 1040px;
                margin: 0 auto;
            }
            .header {
                border-bottom: 2px solid var(--border);
                padding-bottom: 24px;
                margin-bottom: 32px;
            }
            .badge {
                display: inline-block;
                padding: 4px 10px;
                border-radius: 9999px;
                font-size: 11px;
                font-weight: 700;
                text-transform: uppercase;
                letter-spacing: 0.5px;
            }
            .kpi-grid {
                display: grid;
                grid-template-columns: repeat(4, 1fr);
                gap: 16px;
                margin-bottom: 32px;
            }
            .card {
                background: var(--card-bg);
                border: 1px solid var(--border);
                border-radius: 10px;
                padding: 16px;
            }
            .kpi-title { font-size: 11px; color: var(--text-secondary); text-transform: uppercase; font-weight: 600; margin-bottom: 4px; }
            .kpi-val { font-size: 22px; font-weight: 800; font-family: ui-monospace, Menlo, monospace; color: var(--accent); }
            table { width: 100%; border-collapse: collapse; margin-bottom: 24px; }
            th, td { padding: 10px 14px; text-align: left; border-bottom: 1px solid var(--border); font-size: 13px; }
            th { font-size: 11px; text-transform: uppercase; color: var(--text-secondary); font-weight: 600; }
            .hash { font-family: ui-monospace, Menlo, monospace; font-size: 11px; word-break: break-all; color: var(--text-secondary); }
            .why-step {
                display: flex;
                align-items: flex-start;
                gap: 12px;
                margin-bottom: 12px;
                background: rgba(255,255,255,0.02);
                padding: 10px 14px;
                border-radius: 6px;
                border-left: 3px solid var(--accent);
            }
            .why-num { font-weight: 800; color: var(--accent); }
        </style>
        </head>
        <body>
            <div class="header">
                <div style="display: flex; justify-content: space-between; align-items: flex-start;">
                    <div>
                        <div style="font-size: 12px; font-weight: 700; color: var(--accent); letter-spacing: 1px;">INCIDENT POST-MORTEM REVIEW</div>
                        <h1 style="margin: 6px 0 8px 0; font-size: 26px;">\(investigation.title)</h1>
                        <div style="color: var(--text-secondary); font-size: 13px;">ID: \(investigation.id) &bull; Lead: \(investigation.commander ?? "NOC Team")</div>
                    </div>
                    <div>
                        <span class="badge" style="background: \(sevColor)20; color: \(sevColor); border: 1px solid \(sevColor)40;">\(investigation.severity.priorityPill)</span>
                        <span class="badge" style="background: #10b98120; color: #10b981; border: 1px solid #10b98140; margin-left: 6px;">\(investigation.status.rawValue)</span>
                    </div>
                </div>
            </div>

            <div class="kpi-grid">
                <div class="card">
                    <div class="kpi-title">Outage Duration</div>
                    <div class="kpi-val">\(String(format: "%.0f", investigation.durationMinutes))m</div>
                </div>
                <div class="card">
                    <div class="kpi-title">Time to Mitigate</div>
                    <div class="kpi-val">\(investigation.mttmMinutes != nil ? String(format: "%.0fm", investigation.mttmMinutes!) : "N/A")</div>
                </div>
                <div class="card">
                    <div class="kpi-title">Time to Resolve</div>
                    <div class="kpi-val">\(investigation.mttrMinutes != nil ? String(format: "%.0fm", investigation.mttrMinutes!) : "N/A")</div>
                </div>
                <div class="card">
                    <div class="kpi-title">SLA Compliance</div>
                    <div class="kpi-val" style="color: \(investigation.isSLAOverdue ? "#ef4444" : "#10b981");">\(investigation.isSLAOverdue ? "Breached" : "Passed")</div>
                </div>
            </div>

            <div class="card" style="margin-bottom: 32px;">
                <h3 style="margin-top: 0; font-size: 15px;">Executive Summary</h3>
                <p style="color: var(--text-secondary); font-size: 13px; margin: 0;">\(investigation.description.isEmpty ? "No description provided." : investigation.description)</p>
                \(investigation.resolution != nil ? "<div style='margin-top: 12px; padding: 10px; background: rgba(16,185,129,0.08); border-radius: 6px; border-left: 3px solid #10b981; font-size: 13px;'><strong>Resolution:</strong> \(investigation.resolution!)</div>" : "")
            </div>
        """

        // 5-Whys section in HTML
        if let rca = rca, !rca.why1.isEmpty {
            html += """
            <div class="card" style="margin-bottom: 32px;">
                <h3 style="margin-top: 0; font-size: 15px;">Root Cause Analysis (5-Whys)</h3>
                <div class="why-step"><span class="why-num">1.</span> <div><strong>Why:</strong> \(rca.why1)</div></div>
                \(rca.why2.isEmpty ? "" : "<div class='why-step'><span class='why-num'>2.</span> <div><strong>Why:</strong> \(rca.why2)</div></div>")
                \(rca.why3.isEmpty ? "" : "<div class='why-step'><span class='why-num'>3.</span> <div><strong>Why:</strong> \(rca.why3)</div></div>")
                \(rca.why4.isEmpty ? "" : "<div class='why-step'><span class='why-num'>4.</span> <div><strong>Why:</strong> \(rca.why4)</div></div>")
                \(rca.why5.isEmpty ? "" : "<div class='why-step'><span class='why-num'>5.</span> <div><strong>Root Cause:</strong> \(rca.why5)</div></div>")
                <div style="margin-top: 14px; padding: 12px; background: rgba(0,210,255,0.08); border-radius: 6px; font-size: 13px;">
                    <strong>Preventative Strategy:</strong> \(rca.preventativeStrategy.isEmpty ? "Hardened monitoring and failover redundancy." : rca.preventativeStrategy)
                </div>
            </div>
            """
        }

        // Evidence Ledger in HTML
        if !evidence.isEmpty {
            html += """
            <div class="card" style="margin-bottom: 32px;">
                <h3 style="margin-top: 0; font-size: 15px;">Forensic Evidence Ledger (\(evidence.count) Artifacts)</h3>
                <table>
                    <thead>
                        <tr>
                            <th>File Name</th>
                            <th>Type</th>
                            <th>Size</th>
                            <th>SHA-256 Fingerprint</th>
                        </tr>
                    </thead>
                    <tbody>
            """
            for ev in evidence {
                let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(ev.byteSize), countStyle: .file)
                html += """
                        <tr>
                            <td><strong>\(ev.filename)</strong><br><span style="color:var(--text-secondary); font-size:11px;">\(ev.title)</span></td>
                            <td><span class="badge" style="background:rgba(255,255,255,0.08);">\(ev.evidenceType.displayName)</span></td>
                            <td>\(sizeStr)</td>
                            <td class="hash">\(ev.sha256)</td>
                        </tr>
                """
            }
            html += """
                    </tbody>
                </table>
            </div>
            """
        }

        html += """
            <div style="text-align: center; color: var(--text-secondary); font-size: 11px; margin-top: 40px;">
                NexWave Studio Mac Network Workbench &bull; Generated on \(df.string(from: Date()))
            </div>
        </body>
        </html>
        """
        return html
    }

    // MARK: - Slack / Jira Incident Triage

    public static func generateSlackJiraTriage(
        investigation: Investigation,
        timeline: [TimelineEventRecord],
        evidenceCount: Int,
        rca: InvestigationRCA?
    ) -> String {
        let icon: String
        switch investigation.severity {
        case .critical: icon = "🚨"
        case .high: icon = "⚠️"
        case .medium: icon = "🟡"
        case .low: icon = "ℹ️"
        }

        var text = "\(icon) *INCIDENT TRIAGE: [\(investigation.severity.priorityPill.uppercased())] \(investigation.title)*\n"
        text += "*Status*: `\(investigation.status.rawValue)` | *Commander*: `\(investigation.commander ?? "Unassigned")`\n"
        text += "*Duration*: `\(String(format: "%.0f", investigation.durationMinutes))m` | *SLA*: \(investigation.isSLAOverdue ? "⚠️ *BREACHED*" : "✅ Target Met")\n"
        if let blast = investigation.blastRadius, !blast.isEmpty {
            text += "*Blast Radius*: \(blast)\n"
        }
        if !investigation.affectedServices.isEmpty {
            text += "*Affected Services*: \(investigation.affectedServices.joined(separator: ", "))\n"
        }
        text += "------------------------------------------------------------\n"
        if !investigation.description.isEmpty {
            text += "*Summary*: \(investigation.description)\n"
        }
        if let rca = rca, !rca.rootCause.isEmpty {
            text += "*Identified Root Cause*: \(rca.rootCause)\n"
        }
        if let res = investigation.resolution, !res.isEmpty {
            text += "*Resolution*: \(res)\n"
        }
        text += "------------------------------------------------------------\n"
        text += "*Key Milestones & Timeline (\(timeline.count) Events, \(evidenceCount) Evidence Artifacts)*:\n"
        let sorted = timeline.sorted { $0.timestamp < $1.timestamp }
        for ev in sorted.suffix(6) {
            let timeStr = Date(timeIntervalSince1970: ev.timestamp).formatted(date: .omitted, time: .standard)
            text += "• `\(timeStr)` [\(ev.category)] *\(ev.title)*: \(ev.detail)\n"
        }
        text += "------------------------------------------------------------\n"
        text += "_Exported via NexWave Studio Mac Network Workbench v1.1_\n"
        return text
    }
}
