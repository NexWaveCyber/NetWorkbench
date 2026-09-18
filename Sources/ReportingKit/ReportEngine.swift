import Foundation
import NetworkCore
import DiagnosticsEngine
import InvestigationKit
import DeviceKit
import ConfigKit
import PacketKit

public enum ReportEngine {

    // MARK: - Investigation / Diagnostic Report
    public static func generateDiagnosticReport(
        result: DiagnosticResult,
        format: ReportFormat = .markdown,
        investigation: Investigation? = nil
    ) -> ExportedReport {
        let meta = ReportMetadata()
        let targetStr = result.target.displayString
        let title = "Diagnostic Evidence Report — \(targetStr)"

        let rawContent: String
        switch format {
        case .markdown:
            rawContent = formatDiagnosticMarkdown(result: result, investigation: investigation, meta: meta)
        case .json:
            rawContent = formatDiagnosticJSON(result: result, investigation: investigation, meta: meta)
        case .printableHTML:
            rawContent = formatDiagnosticHTML(result: result, investigation: investigation, meta: meta)
        }

        let sanitizedContent = ReportRedactor.sanitize(rawContent)
        return ExportedReport(title: title, format: format, metadata: meta, content: sanitizedContent)
    }

    // MARK: - Packet Capture Summary Report
    public static func generatePacketReport(
        summary: PacketCaptureSummary,
        format: ReportFormat = .markdown
    ) -> ExportedReport {
        let meta = ReportMetadata()
        let title = "Packet Capture Triage Report — \(summary.fileName)"

        let rawContent: String
        switch format {
        case .markdown:
            rawContent = formatPacketMarkdown(summary: summary, meta: meta)
        case .json:
            rawContent = formatPacketJSON(summary: summary, meta: meta)
        case .printableHTML:
            rawContent = formatPacketHTML(summary: summary, meta: meta)
        }

        let sanitizedContent = ReportRedactor.sanitize(rawContent)
        return ExportedReport(title: title, format: format, metadata: meta, content: sanitizedContent)
    }

    // MARK: - Device Fleet Audit Report
    public static func generateDeviceAuditReport(
        devices: [NetworkDevice],
        format: ReportFormat = .markdown
    ) -> ExportedReport {
        let meta = ReportMetadata()
        let title = "Network Device Fleet Audit Report"

        let rawContent: String
        switch format {
        case .markdown:
            rawContent = formatDeviceMarkdown(devices: devices, meta: meta)
        case .json:
            rawContent = formatDeviceJSON(devices: devices, meta: meta)
        case .printableHTML:
            rawContent = formatDeviceHTML(devices: devices, meta: meta)
        }

        let sanitizedContent = ReportRedactor.sanitize(rawContent)
        return ExportedReport(title: title, format: format, metadata: meta, content: sanitizedContent)
    }

    // MARK: - Config Diff Audit Report
    public static func generateConfigDiffReport(
        diff: StructuralDiffReport,
        baselineName: String = "Baseline",
        targetName: String = "Target",
        format: ReportFormat = .markdown
    ) -> ExportedReport {
        let meta = ReportMetadata()
        let title = "Configuration Structural Audit Report — \(baselineName) vs \(targetName)"

        let rawContent: String
        switch format {
        case .markdown:
            rawContent = formatDiffMarkdown(diff: diff, baselineName: baselineName, targetName: targetName, meta: meta)
        case .json:
            rawContent = formatDiffJSON(diff: diff, baselineName: baselineName, targetName: targetName, meta: meta)
        case .printableHTML:
            rawContent = formatDiffHTML(diff: diff, baselineName: baselineName, targetName: targetName, meta: meta)
        }

        let sanitizedContent = ReportRedactor.sanitize(rawContent)
        return ExportedReport(title: title, format: format, metadata: meta, content: sanitizedContent)
    }

    // MARK: - Internal Formatters: Packet Capture
    private static func formatPacketMarkdown(summary: PacketCaptureSummary, meta: ReportMetadata) -> String {
        var md = """
        # Packet Capture Triage Report
        > **Capture File**: `\(summary.fileName)` (\(summary.formatName))  
        > **Generated**: \(meta.generatedAt.formatted(date: .abbreviated, time: .standard))  
        > **Host**: `\(meta.authorHost)` | **NexWave Version**: `\(meta.appVersion)`

        ---

        ## Executive Summary
        * **Total Packets**: \(summary.totalPackets)
        * **Total Volume**: \(ByteCountFormatter.string(fromByteCount: Int64(summary.totalBytes), countStyle: .binary))
        * **Capture Duration**: \(String(format: "%.2f", summary.duration))s
        * **Average Throughput**: \(String(format: "%.3f", summary.averageBitrateMbps)) Mbps
        * **Anomalies Detected**: \(summary.anomalies.count)

        ---

        ## Protocol Breakdown

        | Protocol | Packets | Bytes | Bandwidth Share |
        | :--- | :--- | :--- | :--- |
        """

        for p in summary.protocolDistribution {
            md += "\n| `\(p.protocolType.description)` | \(p.packetCount) | \(ByteCountFormatter.string(fromByteCount: Int64(p.byteCount), countStyle: .binary)) | \(String(format: "%.1f", p.percentage))% |"
        }

        if !summary.anomalies.isEmpty {
            md += "\n\n---\n\n## Detected TCP & Transport Anomalies\n\n"
            md += "| Packet # | Time (+s) | Source | Destination | Severity | Anomaly Description |\n"
            md += "| :--- | :--- | :--- | :--- | :--- | :--- |\n"
            for a in summary.anomalies {
                md += "| #\(a.packetNumber) | +\(String(format: "%.3f", a.relativeTime))s | `\(a.source)` | `\(a.destination)` | **\(a.severity.rawValue)** | \(a.description) |\n"
            }
        }

        if !summary.topTalkers.isEmpty {
            md += "\n\n---\n\n## Top Talkers\n\n"
            md += "| Endpoint IP | Packets | Sent | Received | Total Bytes |\n"
            md += "| :--- | :--- | :--- | :--- | :--- |\n"
            for t in summary.topTalkers.prefix(10) {
                md += "| `\(t.ipAddress)` | \(t.packetCount) | \(ByteCountFormatter.string(fromByteCount: Int64(t.sentBytes), countStyle: .binary)) | \(ByteCountFormatter.string(fromByteCount: Int64(t.receivedBytes), countStyle: .binary)) | \(ByteCountFormatter.string(fromByteCount: Int64(t.totalBytes), countStyle: .binary)) |\n"
            }
        }

        return md
    }

    private static func formatPacketJSON(summary: PacketCaptureSummary, meta: ReportMetadata) -> String {
        let dict: [String: Any] = [
            "reportId": meta.reportID.uuidString,
            "generatedAt": meta.generatedAt.ISO8601Format(),
            "fileName": summary.fileName,
            "format": summary.formatName,
            "totalPackets": summary.totalPackets,
            "totalBytes": summary.totalBytes,
            "duration": summary.duration,
            "bitrateMbps": summary.averageBitrateMbps,
            "anomalies": summary.anomalies.map { [
                "packet": $0.packetNumber,
                "time": $0.relativeTime,
                "source": $0.source,
                "dest": $0.destination,
                "severity": $0.severity.rawValue,
                "description": $0.description
            ]},
            "topTalkers": summary.topTalkers.map { [
                "ip": $0.ipAddress,
                "totalBytes": $0.totalBytes,
                "packetCount": $0.packetCount
            ]}
        ]
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{}"
    }

    private static func formatPacketHTML(summary: PacketCaptureSummary, meta: ReportMetadata) -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <title>Packet Capture Triage Report — \(summary.fileName)</title>
            <style>
                body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; margin: 40px; color: #1e293b; line-height: 1.6; }
                table { width: 100%; border-collapse: collapse; margin-top: 20px; }
                th, td { text-align: left; padding: 10px; border-bottom: 1px solid #e2e8f0; }
                th { background-color: #f8fafc; }
            </style>
        </head>
        <body>
            <h1>Packet Capture Triage Report</h1>
            <p>File: <strong>\(summary.fileName)</strong> (\(summary.formatName)) | Total Packets: <strong>\(summary.totalPackets)</strong></p>
            <h2>Top Talkers</h2>
            <table>
                <tr><th>IP Address</th><th>Packets</th><th>Total Bytes</th></tr>
                \(summary.topTalkers.prefix(10).map { "<tr><td><code>\($0.ipAddress)</code></td><td>\($0.packetCount)</td><td>\($0.totalBytes)</td></tr>" }.joined())
            </table>
        </body>
        </html>
        """
    }

    // MARK: - Internal Formatters: Diagnostic
    private static func formatDiagnosticMarkdown(
        result: DiagnosticResult,
        investigation: Investigation?,
        meta: ReportMetadata
    ) -> String {
        var md = """
        # Diagnostic Evidence Report
        > **Generated**: \(meta.generatedAt.formatted(date: .abbreviated, time: .standard))  
        > **Host**: `\(meta.authorHost)` | **NexWave Version**: `\(meta.appVersion)`  
        > **Sanitization**: `\(meta.isSanitized ? "ENFORCED (Zero-Leak)" : "Disabled")`

        ---

        ## Executive Summary
        * **Target**: `\(result.target.displayString)` (\(result.target.targetType.rawValue))
        * **Verdict**: **\(result.overallStatus.rawValue)**
        * **Statement**: \(result.overallSummary)
        """

        if let inv = investigation {
            md += """

            * **Investigation**: #\(inv.id.prefix(8)) (\(inv.title))
            * **Severity**: **\(inv.severity.rawValue)** | **Status**: \(inv.status.rawValue)
            """
            if let res = inv.resolution {
                md += "\n* **Resolution**: \(res)"
            }
        }

        md += "\n\n---\n\n## Analytical Findings\n\n"
        md += "| Classification | Severity | Finding | Fault Domain | Confidence |\n"
        md += "| :--- | :--- | :--- | :--- | :--- |\n"
        for f in result.findings {
            md += "| `\(f.classification.rawValue)` | **\(f.severity.rawValue)** | \(f.statement) | \(f.faultDomain) | \(f.confidence.rawValue) |\n"
        }

        md += "\n---\n\n## Multi-Layer Telemetry Observations\n\n"

        if let dns = result.dns {
            md += """
            ### 1. DNS Resolution
            * **Status**: \(dns.isHealthy ? "Healthy" : "Degraded / Failed")
            * **Lookup Latency**: \(String(format: "%.2f", dns.queryTimeMs)) ms
            * **IPv4 Answers**: \(dns.ipv4Addresses.map(\.description).joined(separator: ", "))
            * **IPv6 Answers**: \(dns.ipv6Addresses.isEmpty ? "None" : dns.ipv6Addresses.map(\.description).joined(separator: ", "))

            """
        }

        if let lat = result.latency {
            md += """
            ### 2. Transport Latency & RFC 3550 Jitter
            * **Probes**: Sent \(lat.sent), Received \(lat.received) (Loss: \(String(format: "%.1f", lat.lossPercentage))%)
            * **Min / Max / Avg**: \(String(format: "%.1f", lat.minMs)) / \(String(format: "%.1f", lat.maxMs)) / \(String(format: "%.1f", lat.avgMs)) ms
            * **P50 (Median)**: \(String(format: "%.1f", lat.medianMs)) ms | **P95**: \(String(format: "%.1f", lat.p95Ms)) ms
            * **RFC 3550 Jitter**: \(String(format: "%.1f", lat.jitterMs)) ms

            """
        }

        if let http = result.http {
            let dnsStr = http.dnsTimeMs.map { String(format: "%.1f ms", $0) } ?? "N/A"
            let tcpStr = http.connectTimeMs.map { String(format: "%.1f ms", $0) } ?? "N/A"
            let tlsStr = http.tlsTimeMs.map { String(format: "%.1f ms", $0) } ?? "N/A"
            let ttfbStr = http.ttfbMs.map { String(format: "%.1f ms", $0) } ?? "N/A"

            md += """
            ### 3. Application / HTTP Telemetry
            * **Status Code**: \(http.statusCode)
            * **Total Time**: \(String(format: "%.1f", http.totalTimeMs)) ms
            * **DNS Phase**: \(dnsStr)
            * **TCP Connect**: \(tcpStr)
            * **TLS Handshake**: \(tlsStr)
            * **TTFB (Server Processing)**: \(ttfbStr)

            """
        }

        return md
    }

    private static func formatDiagnosticJSON(
        result: DiagnosticResult,
        investigation: Investigation?,
        meta: ReportMetadata
    ) -> String {
        var dict: [String: Any] = [
            "reportId": meta.reportID.uuidString,
            "generatedAt": meta.generatedAt.ISO8601Format(),
            "appVersion": meta.appVersion,
            "host": meta.authorHost,
            "target": result.target.displayString,
            "overallStatus": result.overallStatus.rawValue,
            "summary": result.overallSummary,
            "findings": result.findings.map { [
                "classification": $0.classification.rawValue,
                "severity": $0.severity.rawValue,
                "statement": $0.statement,
                "faultDomain": $0.faultDomain,
                "confidence": $0.confidence.rawValue
            ]}
        ]

        if let inv = investigation {
            dict["investigation"] = [
                "id": inv.id,
                "title": inv.title,
                "status": inv.status.rawValue,
                "severity": inv.severity.rawValue,
                "resolution": inv.resolution ?? ""
            ]
        }

        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{}"
    }

    private static func formatDiagnosticHTML(
        result: DiagnosticResult,
        investigation: Investigation?,
        meta: ReportMetadata
    ) -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <title>Diagnostic Evidence Report — \(result.target.displayString)</title>
            <style>
                body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; margin: 40px; color: #1e293b; line-height: 1.6; }
                h1 { color: #0f172a; border-bottom: 2px solid #e2e8f0; padding-bottom: 8px; }
                .meta { color: #64748b; font-size: 0.9em; margin-bottom: 24px; }
                .badge { display: inline-block; padding: 4px 8px; border-radius: 4px; font-weight: bold; background: #e0f2fe; color: #0284c7; }
                table { width: 100%; border-collapse: collapse; margin: 20px 0; }
                th, td { text-align: left; padding: 10px; border-bottom: 1px solid #e2e8f0; }
                th { background-color: #f8fafc; color: #475569; }
            </style>
        </head>
        <body>
            <h1>Diagnostic Evidence Report</h1>
            <div class="meta">
                Target: <strong>\(result.target.displayString)</strong> |
                Status: <span class="badge">\(result.overallStatus.rawValue)</span> |
                Generated: \(meta.generatedAt.formatted(date: .abbreviated, time: .standard))
            </div>
            <p><strong>Summary:</strong> \(result.overallSummary)</p>
            <h2>Analytical Findings</h2>
            <table>
                <tr><th>Classification</th><th>Severity</th><th>Finding</th><th>Domain</th></tr>
                \(result.findings.map { "<tr><td><code>\($0.classification.rawValue)</code></td><td>\($0.severity.rawValue)</td><td>\($0.statement)</td><td>\($0.faultDomain)</td></tr>" }.joined())
            </table>
        </body>
        </html>
        """
    }

    // MARK: - Internal Formatters: Device Fleet
    private static func formatDeviceMarkdown(devices: [NetworkDevice], meta: ReportMetadata) -> String {
        var md = """
        # Network Device Fleet Audit Report
        > **Generated**: \(meta.generatedAt.formatted(date: .abbreviated, time: .standard)) | **Total Devices**: \(devices.count)  
        > **Host**: `\(meta.authorHost)` | **NexWave Version**: `\(meta.appVersion)`

        ---

        ## Fleet Inventory

        | Name | IP Address | Vendor | Role | Status | Tags |
        | :--- | :--- | :--- | :--- | :--- | :--- |
        """

        for d in devices {
            let tags = d.tags.isEmpty ? "-" : d.tags.joined(separator: ", ")
            md += "\n| **\(d.name)** | `\(d.ipAddress)` | \(d.vendor.rawValue) | \(d.role.rawValue) | \(d.status.rawValue) | \(tags) |"
        }

        return md
    }

    private static func formatDeviceJSON(devices: [NetworkDevice], meta: ReportMetadata) -> String {
        let dict: [String: Any] = [
            "reportId": meta.reportID.uuidString,
            "generatedAt": meta.generatedAt.ISO8601Format(),
            "deviceCount": devices.count,
            "devices": devices.map { [
                "id": $0.id.uuidString,
                "name": $0.name,
                "ip": $0.ipAddress,
                "vendor": $0.vendor.rawValue,
                "role": $0.role.rawValue,
                "status": $0.status.rawValue,
                "tags": $0.tags
            ]}
        ]
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{}"
    }

    private static func formatDeviceHTML(devices: [NetworkDevice], meta: ReportMetadata) -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <title>Network Device Fleet Audit</title>
            <style>
                body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; margin: 40px; color: #1e293b; }
                table { width: 100%; border-collapse: collapse; margin-top: 20px; }
                th, td { text-align: left; padding: 10px; border-bottom: 1px solid #e2e8f0; }
                th { background-color: #f8fafc; }
            </style>
        </head>
        <body>
            <h1>Network Device Fleet Audit</h1>
            <p>Total Enrolled Devices: <strong>\(devices.count)</strong></p>
            <table>
                <tr><th>Name</th><th>IP Address</th><th>Vendor</th><th>Role</th><th>Status</th></tr>
                \(devices.map { "<tr><td><strong>\($0.name)</strong></td><td><code>\($0.ipAddress)</code></td><td>\($0.vendor.rawValue)</td><td>\($0.role.rawValue)</td><td>\($0.status.rawValue)</td></tr>" }.joined())
            </table>
        </body>
        </html>
        """
    }

    // MARK: - Internal Formatters: Config Diff
    private static func formatDiffMarkdown(
        diff: StructuralDiffReport,
        baselineName: String,
        targetName: String,
        meta: ReportMetadata
    ) -> String {
        var md = """
        # Configuration Structural Audit Report
        > **Baseline**: `\(baselineName)` | **Target**: `\(targetName)`  
        > **Generated**: \(meta.generatedAt.formatted(date: .abbreviated, time: .standard))  
        > **Deltas**: +\(diff.semanticChanges.filter { $0.changeType == .added }.count) Added, -\(diff.semanticChanges.filter { $0.changeType == .removed }.count) Removed, ~\(diff.semanticChanges.filter { $0.changeType == .modified }.count) Modified

        ---

        ## Semantic Changes

        | Category | Change | Details |
        | :--- | :--- | :--- |
        """

        for c in diff.semanticChanges {
            md += "\n| \(c.category.rawValue) | **\(c.changeType.rawValue)** | \(c.title): \(c.detail) |"
        }

        md += "\n\n---\n\n## Line-by-Line Unified Diff\n\n```diff\n"
        for line in diff.diffLines {
            switch line.kind {
            case .added: md += "+ \(line.text)\n"
            case .removed: md += "- \(line.text)\n"
            case .modified: md += "~ \(line.text)\n"
            case .unchanged: md += "  \(line.text)\n"
            case .reordered: md += "^ \(line.text)\n"
            }
        }
        md += "```\n"

        return md
    }

    private static func formatDiffJSON(
        diff: StructuralDiffReport,
        baselineName: String,
        targetName: String,
        meta: ReportMetadata
    ) -> String {
        let dict: [String: Any] = [
            "reportId": meta.reportID.uuidString,
            "generatedAt": meta.generatedAt.ISO8601Format(),
            "baseline": baselineName,
            "target": targetName,
            "changes": diff.semanticChanges.map { [
                "category": $0.category.rawValue,
                "changeType": $0.changeType.rawValue,
                "title": $0.title,
                "detail": $0.detail
            ]}
        ]
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{}"
    }

    private static func formatDiffHTML(
        diff: StructuralDiffReport,
        baselineName: String,
        targetName: String,
        meta: ReportMetadata
    ) -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <title>Configuration Structural Audit</title>
            <style>
                body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; margin: 40px; color: #1e293b; }
                table { width: 100%; border-collapse: collapse; margin-top: 20px; }
                th, td { text-align: left; padding: 10px; border-bottom: 1px solid #e2e8f0; }
                th { background-color: #f8fafc; }
            </style>
        </head>
        <body>
            <h1>Configuration Structural Audit</h1>
            <p>Comparing <strong>\(baselineName)</strong> with <strong>\(targetName)</strong></p>
            <table>
                <tr><th>Category</th><th>Type</th><th>Details</th></tr>
                \(diff.semanticChanges.map { "<tr><td>\($0.category.rawValue)</td><td><strong>\($0.changeType.rawValue)</strong></td><td>\($0.title): \($0.detail)</td></tr>" }.joined())
            </table>
        </body>
        </html>
        """
    }
}
