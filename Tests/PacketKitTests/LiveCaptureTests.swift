import Testing
import Foundation
@testable import PacketKit

@Suite("Live Packet Capture Tests")
struct LiveCaptureTests {

    @Test("Interface Discovery enumerates network adapters")
    func interfaceDiscovery() {
        let ifaces = LiveCaptureEngine.discoverInterfaces()
        #expect(!ifaces.isEmpty)
        let hasLoopback = ifaces.contains(where: { $0.isLoopback || $0.name == "lo0" })
        #expect(hasLoopback == true)
    }

    @Test("BPF Access status check")
    func bpfAccessCheck() {
        let status = LiveCaptureEngine.checkBPFAccess()
        #expect(status == .accessible || status != .unsupported)
    }

    @Test("Streaming Chunk Consumer reassembles fragmented PCAP chunks")
    func streamingChunkConsumer() {
        let session = LiveCaptureSession()
        session.maxBufferSize = 100

        let sampleData = SamplePCAPGenerator.generateSampleCapture()

        // Feed the PCAP data in small 64-byte chunks to test streaming fragmentation
        var offset = 0
        let chunkSize = 64
        while offset < sampleData.count {
            let end = min(offset + chunkSize, sampleData.count)
            let chunk = sampleData.subdata(in: offset..<end)
            session.consumeChunk(chunk)
            offset = end
        }

        #expect(session.packets.count == 21)
        #expect(session.totalPacketsCaptured == 21)
        #expect(session.totalBytesCaptured > 1000)

        // Verify that protocol dissection occurred on streaming packets
        let protocols = Set(session.packets.map(\.protocolType))
        #expect(protocols.contains(.arp))
        #expect(protocols.contains(.tcp))
    }

    @Test("Ring Buffer evicts oldest packets when exceeding maxBufferSize")
    func ringBufferEviction() {
        let session = LiveCaptureSession()
        session.maxBufferSize = 5

        let sampleData = SamplePCAPGenerator.generateSampleCapture()
        session.consumeChunk(sampleData) // Contains 21 packets

        // Ring buffer should clamp to maxBufferSize = 5
        #expect(session.packets.count == 5)
        #expect(session.totalPacketsCaptured == 21)

        // The remaining packets should be the newest packets (e.g. 17, 18, 19, 20, 21)
        let numbers = session.packets.map(\.number)
        #expect(numbers == [17, 18, 19, 20, 21])
    }

    @Test("Live Buffer PCAP export roundtrips with PCAPReader")
    func liveBufferExportRoundtrip() throws {
        let session = LiveCaptureSession()
        let sampleData = SamplePCAPGenerator.generateSampleCapture()
        session.consumeChunk(sampleData)

        let exportedPCAP = session.exportCurrentBufferAsPCAP()
        #expect(exportedPCAP.count >= 24)

        // Magic number verification
        let magic = exportedPCAP.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self) }
        #expect(magic == 0xa1b2c3d4)

        // Parse through PCAPReader
        let summary = try PCAPReader.parse(data: exportedPCAP, fileName: "exported_live.pcap")
        #expect(summary.totalPackets == 21)
    }

    @Test("Simulated stream generates multi-protocol packets and anomalies")
    func simulationStream() async {
        let session = LiveCaptureSession()
        session.startSimulation(packetsPerSecond: 100.0)

        // Sleep briefly to let simulation emit packets
        try? await Task.sleep(nanoseconds: 150_000_000)
        session.stop()

        #expect(!session.packets.isEmpty)
        #expect(session.totalPacketsCaptured > 0)
    }
}
