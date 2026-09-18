import Foundation

/// Pure-Swift RFC 4180 CSV and JSON data exporter for SNMP Studio.
public struct SNMPExporter: Sendable {

    /// Exports SNMP variable bindings (such as MIB walk or get results) to RFC 4180 CSV format.
    public static func exportVarBindsToCSV(
        _ varBinds: [SNMPVarBind],
        dictionary: MIBDictionary = .shared
    ) -> String {
        var lines: [String] = ["OID,Symbolic Name,Syntax Type,Value"]

        for vb in varBinds {
            let symbol = dictionary.resolve(oid: vb.oid)
            let syntax = syntaxForValue(vb.value)
            let valStr = escapeCSV(vb.value.description)
            lines.append("\(escapeCSV(vb.oid)),\(escapeCSV(symbol)),\(escapeCSV(syntax)),\(valStr)")
        }

        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// Exports SNMP variable bindings to formatted JSON Data.
    public static func exportVarBindsToJSON(
        _ varBinds: [SNMPVarBind],
        dictionary: MIBDictionary = .shared
    ) throws -> Data {
        let items = varBinds.map { vb -> [String: Any] in
            [
                "oid": vb.oid,
                "symbol": dictionary.resolve(oid: vb.oid),
                "syntax": syntaxForValue(vb.value),
                "value": vb.value.description
            ]
        }
        return try JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted, .sortedKeys])
    }

    /// Exports captured SNMP traps and informs to RFC 4180 CSV.
    public static func exportTrapsToCSV(
        _ traps: [SNMPTrapRecord],
        dictionary: MIBDictionary = .shared
    ) -> String {
        var lines: [String] = ["Timestamp,Source Address,Port,SNMP Version,Severity,Type,Trap OID,Trap Name,Enterprise OID,VarBinds Count,Summary"]
        let isoFormatter = ISO8601DateFormatter()

        for t in traps {
            let ts = isoFormatter.string(from: t.timestamp)
            let trapName = dictionary.resolve(oid: t.trapOID)
            let typeStr = t.isInform ? "Inform" : (t.version == .v1 ? "v1 Trap (\(t.genericTrap?.displayName ?? "Generic"))" : "v2c/v3 Trap")
            let summary = t.varBinds.map { "\($0.oid)=\($0.value.description)" }.joined(separator: "; ")

            let row = [
                escapeCSV(ts),
                escapeCSV(t.sourceAddress),
                "\(t.sourcePort)",
                escapeCSV(t.version.displayString),
                escapeCSV(t.severity.rawValue),
                escapeCSV(typeStr),
                escapeCSV(t.trapOID),
                escapeCSV(trapName),
                escapeCSV(t.enterpriseOID),
                "\(t.varBinds.count)",
                escapeCSV(summary)
            ].joined(separator: ",")
            lines.append(row)
        }

        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// Exports captured SNMP traps to JSON Data.
    public static func exportTrapsToJSON(_ traps: [SNMPTrapRecord]) throws -> Data {
        let isoFormatter = ISO8601DateFormatter()
        let items = traps.map { t -> [String: Any] in
            [
                "id": t.id.uuidString,
                "timestamp": isoFormatter.string(from: t.timestamp),
                "sourceAddress": t.sourceAddress,
                "sourcePort": t.sourcePort,
                "version": t.version.displayString,
                "community": t.community,
                "severity": t.severity.rawValue,
                "isInform": t.isInform,
                "trapOID": t.trapOID,
                "enterpriseOID": t.enterpriseOID,
                "timeStampTicks": t.timeStampTicks,
                "varBinds": t.varBinds.map { ["oid": $0.oid, "value": $0.value.description] }
            ]
        }
        return try JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted, .sortedKeys])
    }

    /// Exports interface telemetry metrics to RFC 4180 CSV.
    public static func exportTelemetryToCSV(_ metrics: [SNMPInterfaceMetric]) -> String {
        var lines: [String] = ["Timestamp,Index,Name,Admin Status,Oper Status,Speed Mbps,In Octets,Out Octets,In Errors,Out Errors,In Discards,Out Discards"]
        let isoFormatter = ISO8601DateFormatter()

        for m in metrics {
            let ts = isoFormatter.string(from: m.timestamp)
            let row = [
                escapeCSV(ts),
                "\(m.index)",
                escapeCSV(m.name),
                escapeCSV(m.adminStatus),
                escapeCSV(m.operStatus),
                String(format: "%.1f", m.speedMbps),
                "\(m.inOctets)",
                "\(m.outOctets)",
                "\(m.inErrors)",
                "\(m.outErrors)",
                "\(m.inDiscards)",
                "\(m.outDiscards)"
            ].joined(separator: ",")
            lines.append(row)
        }

        return lines.joined(separator: "\r\n") + "\r\n"
    }

    private static func syntaxForValue(_ val: SNMPValue) -> String {
        switch val {
        case .integer: return "INTEGER"
        case .octetString: return "DisplayString"
        case .rawBytes: return "OCTET STRING"
        case .oid: return "OBJECT IDENTIFIER"
        case .ipAddress: return "IpAddress"
        case .counter32: return "Counter32"
        case .gauge32: return "Gauge32"
        case .timeTicks: return "TimeTicks"
        case .counter64: return "Counter64"
        case .null: return "NULL"
        case .noSuchObject: return "noSuchObject"
        case .noSuchInstance: return "noSuchInstance"
        case .endOfMibView: return "endOfMibView"
        }
    }

    private static func escapeCSV(_ str: String) -> String {
        if str.contains(",") || str.contains("\"") || str.contains("\n") || str.contains("\r") {
            let escaped = str.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return str
    }
}
