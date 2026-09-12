import Testing
import Foundation
@testable import PacketKit

@Suite("PacketKit Tests")
struct PacketKitTests {

    @Test("Sample Generator produces valid PCAP magic and non-empty byte buffer")
    func sampleGeneratorIntegrity() {
        let pcapData = SamplePCAPGenerator.generateSampleCapture()
        #expect(pcapData.count > 500)

        let magic = pcapData.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self) }
        #expect(magic == 0xa1b2c3d4)
    }

    @Test("PCAP Reader extracts all 16 packets and multi-layer protocols")
    func pcapReaderParsing() throws {
        let pcapData = SamplePCAPGenerator.generateSampleCapture()
        let summary = try PCAPReader.parse(data: pcapData, fileName: "synthetic_traffic.pcap")

        #expect(summary.totalPackets == 16)
        #expect(summary.totalBytes > 1000)
        #expect(summary.duration >= 0.0)

        // Verify protocol detection
        let protocols = Set(summary.packets.map(\.protocolType))
        #expect(protocols.contains(.arp))
        #expect(protocols.contains(.dns))
        #expect(protocols.contains(.tcp))
        #expect(protocols.contains(.tls))
        #expect(protocols.contains(.http))
        #expect(protocols.contains(.icmp))
    }

    @Test("TCP Anomaly Detector flags retransmission, zero window, and connection reset")
    func tcpAnomalyDetection() throws {
        let pcapData = SamplePCAPGenerator.generateSampleCapture()
        let summary = try PCAPReader.parse(data: pcapData, fileName: "synthetic_traffic.pcap")

        // Anomaly events should be detected
        #expect(!summary.anomalies.isEmpty)

        // Check Packet 10: Retransmission of Packet 8
        let p10 = summary.packets.first(where: { $0.number == 10 })
        #expect(p10 != nil)
        let hasRetrans = p10?.anomalies.contains(where: {
            if case .retransmission(let orig) = $0 {
                return orig == 8
            }
            return false
        }) ?? false
        #expect(hasRetrans == true)

        // Check Packet 11: Zero Window
        let p11 = summary.packets.first(where: { $0.number == 11 })
        #expect(p11 != nil)
        let hasZeroWin = p11?.anomalies.contains(where: { $0 == .zeroWindow }) ?? false
        #expect(hasZeroWin == true)

        // Check Packet 14: RST flag
        let p14 = summary.packets.first(where: { $0.number == 14 })
        #expect(p14 != nil)
        let hasRst = p14?.anomalies.contains(where: { $0 == .connectionReset }) ?? false
        #expect(hasRst == true)
    }

    @Test("Flow Tracker calculates Top Talkers and Protocol Distribution")
    func flowTrackerCalculations() throws {
        let pcapData = SamplePCAPGenerator.generateSampleCapture()
        let summary = try PCAPReader.parse(data: pcapData, fileName: "synthetic_traffic.pcap")

        #expect(!summary.topTalkers.isEmpty)
        let topTalker = summary.topTalkers[0]
        #expect(!topTalker.ipAddress.isEmpty)
        #expect(topTalker.totalBytes > 0)

        #expect(!summary.protocolDistribution.isEmpty)
        let totalPct = summary.protocolDistribution.reduce(0.0) { $0 + $1.percentage }
        #expect(totalPct > 99.0 && totalPct < 101.0) // ~100%

        #expect(!summary.flows.isEmpty)
        let mainFlow = summary.flows.first(where: { $0.source.contains("443") || $0.destination.contains("443") })
        #expect(mainFlow != nil)
    }

    @Test("PCAPNG Reader parses Section Header and Enhanced Packet Blocks")
    func pcapngReaderParsing() throws {
        var data = Data()

        // 1. Section Header Block (SHB) 0x0A0D0D0A, length 28 bytes
        func appendU32(_ val: UInt32) {
            var v = val
            withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }

        appendU32(0x0A0D0D0A) // Type
        appendU32(28)         // Total Len
        appendU32(0x1A2B3C4D) // Byte order magic
        appendU32(0x00010000) // Major 1, Minor 0
        appendU32(0xFFFFFFFF) // Section len -1 (unspecified)
        appendU32(0xFFFFFFFF)
        appendU32(28)         // Total Len

        // 2. Enhanced Packet Block (EPB) 0x00000006
        // Min EPB len = 28 + packetData padded + 4 totalLen = 28 + 60 (dummy ethernet) + 4 = 92
        let dummyPacket = Data(repeating: 0x00, count: 60)
        let epbLen: UInt32 = 28 + UInt32(dummyPacket.count) + 4

        appendU32(0x00000006) // Type EPB
        appendU32(epbLen)     // Total Len
        appendU32(0)          // Interface ID
        appendU32(0)          // tsHigh
        appendU32(1000000)    // tsLow (1s)
        appendU32(UInt32(dummyPacket.count)) // capLen
        appendU32(UInt32(dummyPacket.count)) // origLen
        data.append(dummyPacket)
        appendU32(epbLen)     // Total Len

        let summary = try PCAPNGReader.parse(data: data, fileName: "test.pcapng")
        #expect(summary.totalPackets == 1)
        #expect(summary.formatName.contains("PCAPNG"))
    }

    @Test("Wireshark Bridge exposes valid download URL and system check")
    func wiresharkBridge() {
        #expect(WiresharkBridge.downloadURL.absoluteString == "https://www.wireshark.org/download.html")
        // Check property does not crash
        _ = WiresharkBridge.isWiresharkInstalled
    }
}
