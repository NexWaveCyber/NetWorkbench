import Foundation

public enum PacketExporter {

    /// Exports an array of PacketRecord instances to standard classic PCAP format (Ethernet Link Type).
    public static func exportPCAP(packets: [PacketRecord]) -> Data {
        var data = Data()

        // 1. PCAP Global Header (24 bytes, Host Byte Order)
        var magic: UInt32 = 0xa1b2c3d4
        var verMaj: UInt16 = 2
        var verMin: UInt16 = 4
        var thiszone: UInt32 = 0
        var sigfigs: UInt32 = 0
        var snaplen: UInt32 = 65535
        var linktype: UInt32 = 1 // Ethernet

        withUnsafeBytes(of: &magic) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &verMaj) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &verMin) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &thiszone) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &sigfigs) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &snaplen) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &linktype) { data.append(contentsOf: $0) }

        // 2. Packet Headers & Payload
        for p in packets {
            let epoch = p.timestamp.timeIntervalSince1970
            var sec = UInt32(max(0, epoch))
            var usec = UInt32(max(0, (epoch - Double(sec)) * 1_000_000))
            var capLen = UInt32(p.rawBytes.count)
            var origLen = UInt32(p.wireLength)

            withUnsafeBytes(of: &sec) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: &usec) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: &capLen) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: &origLen) { data.append(contentsOf: $0) }
            data.append(p.rawBytes)
        }

        return data
    }

    /// Exports an array of PacketRecord instances to RFC 4180 compliant CSV format.
    public static func exportCSV(packets: [PacketRecord]) -> String {
        var csv = "\"No.\",\"Time (s)\",\"Source\",\"Destination\",\"Protocol\",\"Length\",\"Summary\",\"TCP Flags\",\"TCP Seq\",\"TCP Ack\",\"Anomalies\"\r\n"

        for p in packets {
            let src = p.sourcePort != nil ? "\(p.sourceAddress):\(p.sourcePort!)" : p.sourceAddress
            let dst = p.destinationPort != nil ? "\(p.destinationAddress):\(p.destinationPort!)" : p.destinationAddress
            let proto = p.protocolType.description
            let flags = p.tcpFlags?.flagSummary ?? ""
            let seq = p.tcpSeq.map { "\($0)" } ?? ""
            let ack = p.tcpAck.map { "\($0)" } ?? ""
            let anomalyList = p.anomalies.map { $0.title }.joined(separator: "; ")

            let row = [
                escapeCSV("\(p.number)"),
                escapeCSV(String(format: "%.6f", p.relativeTime)),
                escapeCSV(src),
                escapeCSV(dst),
                escapeCSV(proto),
                escapeCSV("\(p.wireLength)"),
                escapeCSV(p.summary),
                escapeCSV(flags),
                escapeCSV(seq),
                escapeCSV(ack),
                escapeCSV(anomalyList)
            ].joined(separator: ",")

            csv.append(row + "\r\n")
        }

        return csv
    }

    private static func escapeCSV(_ text: String) -> String {
        let escaped = text.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
