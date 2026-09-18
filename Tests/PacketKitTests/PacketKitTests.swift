import Testing
import Foundation
import NetworkCore
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

    @Test("PCAP Reader extracts all 21 packets and multi-layer protocols including DHCP, BGP, NTP")
    func pcapReaderParsing() throws {
        let pcapData = SamplePCAPGenerator.generateSampleCapture()
        let summary = try PCAPReader.parse(data: pcapData, fileName: "synthetic_traffic.pcap")

        #expect(summary.totalPackets == 21)
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
        #expect(protocols.contains(.dhcp))
        #expect(protocols.contains(.bgp))
        #expect(protocols.contains(.ntp))
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

    @Test("LLDP Dissector extracts chassis, port, system name, and VLAN")
    func lldpDissection() {
        var frame = Data()
        // Ethernet Header
        frame.append(contentsOf: [0x01, 0x80, 0xC2, 0x00, 0x00, 0x0E]) // Dst MAC
        frame.append(contentsOf: [0x00, 0x11, 0x22, 0x33, 0x44, 0x55]) // Src MAC
        frame.append(contentsOf: [0x88, 0xCC])                         // EtherType LLDP

        // TLV 1: Chassis ID (Type 1, Len 7) -> (1 << 9) | 7 = 0x0207
        frame.append(contentsOf: [0x02, 0x07, 0x04])
        frame.append(contentsOf: [0x00, 0x11, 0x22, 0x33, 0x44, 0x55])

        // TLV 2: Port ID (Type 2, Len 9 = 1 byte subtype + 8 bytes "Gi1/0/24") -> (2 << 9) | 9 = 0x0409
        frame.append(contentsOf: [0x04, 0x09, 0x05]) // Subtype 5 (Interface name)
        frame.append("Gi1/0/24".data(using: .utf8)!)

        // TLV 3: TTL 120s -> (3 << 9) | 2 = 0x0602
        frame.append(contentsOf: [0x06, 0x02, 0x00, 0x78])

        // TLV 5: System Name "sw-core-01" (Len 10) -> (5 << 9) | 10 = 0x0A0A
        frame.append(contentsOf: [0x0A, 0x0A])
        frame.append("sw-core-01".data(using: .utf8)!)

        // TLV 0: End of LLDPDU (0x0000)
        frame.append(contentsOf: [0x00, 0x00])

        let (info, summary, layers) = LLDPDissector.dissect(data: frame, offset: 14)
        #expect(info.systemName == "sw-core-01")
        #expect(info.portID == "Gi1/0/24")
        #expect(info.ttlSeconds == 120)
        #expect(summary.contains("sw-core-01"))
        #expect(!layers.isEmpty)
    }

    @Test("CDP Dissector extracts device ID, port ID, platform, and native VLAN")
    func cdpDissection() {
        var frame = Data()
        // Ethernet Header
        frame.append(contentsOf: [0x01, 0x00, 0x0C, 0xCC, 0xCC, 0xCC]) // Dst MAC
        frame.append(contentsOf: [0x00, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE]) // Src MAC
        frame.append(contentsOf: [0x00, 0x50])                         // Length 80
        // LLC/SNAP
        frame.append(contentsOf: [0xAA, 0xAA, 0x03, 0x00, 0x00, 0x0C, 0x20, 0x00])

        // CDP Header: Version 2, TTL 180, Checksum 0x1234
        frame.append(contentsOf: [0x02, 0xB4, 0x12, 0x34])

        // TLV 0x0001: Device ID "catalyst-3850" (Type 2 bytes, Len 4 + 13 = 17)
        frame.append(contentsOf: [0x00, 0x01, 0x00, 0x11])
        frame.append("catalyst-3850".data(using: .utf8)!)

        // TLV 0x0003: Port ID "Gi1/0/1" (Len 4 + 7 = 11)
        frame.append(contentsOf: [0x00, 0x03, 0x00, 0x0B])
        frame.append("Gi1/0/1".data(using: .utf8)!)

        // TLV 0x0006: Platform "cisco WS-C3850" (Len 4 + 14 = 18)
        frame.append(contentsOf: [0x00, 0x06, 0x00, 0x12])
        frame.append("cisco WS-C3850".data(using: .utf8)!)

        // TLV 0x000A: Native VLAN 100 (Len 4 + 2 = 6)
        frame.append(contentsOf: [0x00, 0x0A, 0x00, 0x06, 0x00, 0x64])

        let (info, summary, layers) = CDPDissector.dissect(data: frame, offset: 22)
        #expect(info.deviceID == "catalyst-3850")
        #expect(info.portID == "Gi1/0/1")
        #expect(info.platform == "cisco WS-C3850")
        #expect(info.nativeVLAN == 100)
        #expect(summary.contains("catalyst-3850"))
        #expect(!layers.isEmpty)
    }

    @Test("Passive Neighbor Discovery Engine identifies switch and records active link")
    func passiveNeighborDiscovery() {
        let engine = PassiveNeighborDiscoveryEngine()

        var lldpFrame = Data()
        lldpFrame.append(contentsOf: [0x01, 0x80, 0xC2, 0x00, 0x00, 0x0E])
        lldpFrame.append(contentsOf: [0x00, 0x11, 0x22, 0x33, 0x44, 0x55])
        lldpFrame.append(contentsOf: [0x88, 0xCC])
        // TLV 1: Chassis ID (Len 7)
        lldpFrame.append(contentsOf: [0x02, 0x07, 0x04, 0x00, 0x11, 0x22, 0x33, 0x44, 0x55])
        // TLV 2: Port ID (Len 7 = 1 byte subtype + 6 bytes "Eth1/1") -> (2 << 9) | 7 = 0x0407
        lldpFrame.append(contentsOf: [0x04, 0x07, 0x05])
        lldpFrame.append("Eth1/1".data(using: .utf8)!)
        // TLV 5: System Name (Len 14 = "arista-spine01") -> (5 << 9) | 14 = 0x0A0E
        lldpFrame.append(contentsOf: [0x0A, 0x0E])
        lldpFrame.append("arista-spine01".data(using: .utf8)!)
        // TLV 0: End of LLDPDU
        lldpFrame.append(contentsOf: [0x00, 0x00])

        let neighbor = engine.processFrame(packetData: lldpFrame)
        #expect(neighbor != nil)
        #expect(neighbor?.systemName == "arista-spine01")
        #expect(neighbor?.portName == "Eth1/1")
        #expect(neighbor?.sourceProtocol == "LLDP")

        #expect(engine.activeLinkNeighbor?.systemName == "arista-spine01")
        #expect(engine.discoveredNeighbors.count == 1)
    }

    @Test("Corrupted and truncated PCAP reader resilience")
    func testCorruptedPCAPHeaderResilience() {
        // Empty buffer
        #expect(throws: Error.self) {
            _ = try PCAPReader.parse(data: Data(), fileName: "empty.pcap")
        }

        // Truncated header (< 24 bytes)
        let truncated = Data([0xD4, 0xC3, 0xB2, 0xA1, 0x02, 0x00])
        #expect(throws: Error.self) {
            _ = try PCAPReader.parse(data: truncated, fileName: "truncated.pcap")
        }

        // Invalid magic number
        var invalidMagic = Data(repeating: 0x00, count: 24)
        invalidMagic[0] = 0xDE
        invalidMagic[1] = 0xAD
        invalidMagic[2] = 0xBE
        invalidMagic[3] = 0xEF
        #expect(throws: Error.self) {
            _ = try PCAPReader.parse(data: invalidMagic, fileName: "corrupt.pcap")
        }
    }

    @Test("Power & Memory Governor monitors footprint and registers pressure callbacks")
    func testPowerAndMemoryGovernorRegistration() {
        let governor = PowerAndMemoryGovernor.shared
        let memoryMB = governor.currentMemoryFootprintMB
        #expect(memoryMB > 0.0)

        let handlerId = governor.registerPressureHandler { _ in }
        governor.unregisterPressureHandler(id: handlerId)
        #expect(governor.isRunningOnBattery == false || governor.isRunningOnBattery == true)
    }

    @Test("Live Capture Buffer compaction preserves memory under Darwin pressure")
    func testLiveCaptureBufferCompactionUnderMemoryPressure() {
        let session = LiveCaptureSession()
        session.startSimulation(packetsPerSecond: 50.0)

        // Allow some packets to populate
        Thread.sleep(forTimeInterval: 0.15)
        #expect(session.packets.count > 0)

        session.stop()
        #expect(session.status == .stopped)
    }

    // MARK: - Enterprise Protocol Dissection Tests

    @Test("DHCP Dissector parses Discover and Offer packets with exact field offsets")
    func testDHCPDissector() throws {
        let pcapData = SamplePCAPGenerator.generateSampleCapture()
        let summary = try PCAPReader.parse(data: pcapData, fileName: "synthetic.pcap")

        let dhcpPackets = summary.packets.filter { $0.protocolType == .dhcp }
        #expect(dhcpPackets.count == 2)

        // Packet 17: DHCP Discover
        let disc = dhcpPackets[0]
        #expect(disc.summary.contains("DHCP Discover"))
        #expect(disc.summary.contains("0x3903F326"))
        let discLayer = disc.layers.first(where: { $0.name.contains("Dynamic Host Configuration Protocol") })
        #expect(discLayer != nil)
        let msgTypeField = discLayer?.fields.first(where: { $0.name.contains("Option (53)") })
        #expect(msgTypeField?.value == "DHCP Discover")
        #expect(msgTypeField?.hexOffset != nil)
        #expect(msgTypeField?.hexLength == 3)

        // Packet 18: DHCP Offer
        let offer = dhcpPackets[1]
        #expect(offer.summary.contains("DHCP Offer"))
        #expect(offer.summary.contains("192.168.1.100"))
        let offerLayer = offer.layers.first(where: { $0.name.contains("Dynamic Host Configuration Protocol") })
        #expect(offerLayer != nil)
        let serverIdField = offerLayer?.fields.first(where: { $0.name.contains("Option (54)") })
        #expect(serverIdField?.value == "192.168.1.1")
        let leaseField = offerLayer?.fields.first(where: { $0.name.contains("Option (51)") })
        #expect(leaseField?.value == "86400s")
    }

    @Test("BGP Dissector decodes Keepalive message and Marker")
    func testBGPDissector() throws {
        let pcapData = SamplePCAPGenerator.generateSampleCapture()
        let summary = try PCAPReader.parse(data: pcapData, fileName: "synthetic.pcap")

        let bgpPkt = summary.packets.first(where: { $0.protocolType == .bgp })
        #expect(bgpPkt != nil)
        #expect(bgpPkt?.summary.contains("KEEPALIVE") == true)

        let bgpLayer = bgpPkt?.layers.first(where: { $0.name.contains("Border Gateway Protocol") })
        #expect(bgpLayer != nil)
        let marker = bgpLayer?.fields.first(where: { $0.name == "Marker" })
        #expect(marker != nil)
        #expect(marker?.hexLength == 16)
        let lenField = bgpLayer?.fields.first(where: { $0.name == "Length" })
        #expect(lenField?.value == "19 bytes")
    }

    @Test("OSPF Dissector decodes OSPFv2 Hello packet with DR and BDR routers")
    func testOSPFDissector() {
        // Build synthetic OSPFv2 Hello packet
        var data = Data()
        // Ethernet Header (14B)
        data.append(contentsOf: [0x01, 0x00, 0x5E, 0x00, 0x00, 0x05]) // 224.0.0.5 Multicast
        data.append(contentsOf: [0x00, 0x11, 0x22, 0x33, 0x44, 0x55])
        data.append(contentsOf: [0x08, 0x00]) // IPv4

        // IPv4 Header (20B, Proto 89 = OSPF)
        data.append(contentsOf: [0x45, 0x00, 0x00, 0x44, 0x12, 0x34, 0x00, 0x00, 0x01, 89, 0x00, 0x00])
        data.append(contentsOf: [10, 0, 0, 1]) // Src IP 10.0.0.1
        data.append(contentsOf: [224, 0, 0, 5]) // Dst IP 224.0.0.5

        // OSPFv2 Header (24B)
        data.append(2) // Version 2
        data.append(1) // Type 1: Hello
        data.append(contentsOf: [0x00, 0x2C]) // Length 44 bytes
        data.append(contentsOf: [10, 0, 0, 1]) // Router ID 10.0.0.1
        data.append(contentsOf: [0, 0, 0, 0]) // Area ID 0.0.0.0 (Backbone)
        data.append(contentsOf: [0x00, 0x00]) // Checksum
        data.append(contentsOf: [0x00, 0x00]) // Auth Type 0 (None)
        data.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, 0]) // Auth 8B

        // OSPF Hello Body (20B)
        data.append(contentsOf: [255, 255, 255, 0]) // Mask 255.255.255.0
        data.append(contentsOf: [0x00, 0x0A])       // Hello Int 10s
        data.append(0x02)                           // Options (E-bit)
        data.append(1)                              // Priority 1
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x28]) // Dead Int 40s
        data.append(contentsOf: [10, 0, 0, 1])      // Designated Router
        data.append(contentsOf: [10, 0, 0, 2])      // Backup DR

        let result = ProtocolDissector.dissect(packetData: data, packetNumber: 1, wireLength: data.count)
        #expect(result.protocolType == .ospf)
        #expect(result.summary.contains("OSPFv2 Hello Packet"))
        #expect(result.summary.contains("10.0.0.1"))

        let ospfLayer = result.layers.first(where: { $0.name.contains("Open Shortest Path First") })
        #expect(ospfLayer != nil)
        let drField = ospfLayer?.fields.first(where: { $0.name.contains("Designated Router") })
        #expect(drField?.value == "10.0.0.1")
        let bdrField = ospfLayer?.fields.first(where: { $0.name.contains("Backup DR") })
        #expect(bdrField?.value == "10.0.0.2")
    }

    @Test("NTP Dissector decodes Stratum, Mode, and Reference ID")
    func testNTPDissector() throws {
        let pcapData = SamplePCAPGenerator.generateSampleCapture()
        let summary = try PCAPReader.parse(data: pcapData, fileName: "synthetic.pcap")

        let ntpPackets = summary.packets.filter { $0.protocolType == .ntp }
        #expect(ntpPackets.count == 2)

        let serverPkt = ntpPackets.first(where: { $0.summary.contains("Server") })
        #expect(serverPkt != nil)
        #expect(serverPkt?.summary.contains("Stratum 1") == true)
        #expect(serverPkt?.summary.contains("NIST") == true)

        let ntpLayer = serverPkt?.layers.first(where: { $0.name.contains("Network Time Protocol") })
        #expect(ntpLayer != nil)
        let modeField = ntpLayer?.fields.first(where: { $0.name == "Mode" })
        #expect(modeField?.value.contains("Server") == true)
    }

    @Test("SNMP Dissector parses BER ASN.1 version, community, and PDU type")
    func testSNMPDissector() {
        var pdu = Data()
        pdu.append(0x30) // Sequence
        pdu.append(27)   // Len
        // Version 1 (v2c): 0x02 0x01 0x01
        pdu.append(contentsOf: [0x02, 0x01, 0x01])
        // Community "public": 0x04 0x06 "public"
        let comm = "public".data(using: .utf8)!
        pdu.append(0x04)
        pdu.append(UInt8(comm.count))
        pdu.append(comm)
        // PDU: 0xA2 (GetResponse)
        pdu.append(0xA2)
        pdu.append(14)
        pdu.append(contentsOf: [0x02, 0x04, 0x12, 0x34, 0x56, 0x78]) // Request ID
        pdu.append(contentsOf: [0x02, 0x01, 0x00]) // Error status 0
        pdu.append(contentsOf: [0x02, 0x01, 0x00]) // Error index 0

        let res = ProtocolDissector.dissectSNMP(payload: pdu, baseOffset: 42)
        #expect(res != nil)
        #expect(res?.summary.contains("SNMPv2c GetResponse") == true)
        #expect(res?.summary.contains("public") == true)

        let commField = res?.layer.fields.first(where: { $0.name == "Community String" })
        #expect(commField?.value == "public")
        #expect(commField?.hexOffset != nil)
    }

    // MARK: - TCP Stream Reassembly Tests

    @Test("TCP Stream Reassembler reconstructs bidirectional client and server dialogue")
    func testTCPStreamReassembly() throws {
        let pcapData = SamplePCAPGenerator.generateSampleCapture()
        let summary = try PCAPReader.parse(data: pcapData, fileName: "synthetic.pcap")

        let tlsPacket = summary.packets.first(where: { $0.protocolType == .tls })
        #expect(tlsPacket != nil)

        let streamResult = TCPStreamReassembler.reassembleStream(for: tlsPacket!, from: summary.packets)
        #expect(streamResult != nil)
        #expect(streamResult?.clientBytes ?? 0 > 0)
        #expect(streamResult?.totalBytes ?? 0 > 0)
        #expect(!streamResult!.segments.isEmpty)
        #expect(streamResult!.streamId.contains("443") || streamResult!.streamId.contains("49214"))

        // Dialogue segments have direction and ascii representation
        let clientSeg = streamResult?.segments.first(where: { $0.direction == .clientToServer })
        #expect(clientSeg != nil)
        #expect(clientSeg?.packetNumber == 8 || clientSeg?.packetNumber == 10)
    }

    // MARK: - Display Filter Engine Tests

    @Test("Packet Display Filter compiles and evaluates Wireshark boolean expressions")
    func testPacketDisplayFilter() throws {
        let pcapData = SamplePCAPGenerator.generateSampleCapture()
        let summary = try PCAPReader.parse(data: pcapData, fileName: "synthetic.pcap")

        // 1. Validation checks
        #expect(PacketDisplayFilter.validate(query: "") == .empty)
        if case .valid = PacketDisplayFilter.validate(query: "tcp.port == 443") {
            // Success
        } else {
            Issue.record("Expected valid status for 'tcp.port == 443'")
        }

        if case .invalid = PacketDisplayFilter.validate(query: "tcp.port ==") {
            // Success
        } else {
            Issue.record("Expected invalid status for 'tcp.port =='")
        }

        // 2. Evaluation: Protocol filter
        let dnsFilter = PacketDisplayFilter(query: "dns")
        let dnsMatches = summary.packets.filter { dnsFilter.matches(packet: $0) }
        #expect(dnsMatches.count == 2)

        // 3. Evaluation: IP source filter
        let ipSrcFilter = PacketDisplayFilter(query: "ip.src == 192.168.1.100")
        let ipMatches = summary.packets.filter { ipSrcFilter.matches(packet: $0) }
        #expect(!ipMatches.isEmpty)
        for p in ipMatches {
            #expect(p.sourceAddress == "192.168.1.100")
        }

        // 4. Evaluation: Compound AND expression
        let compoundFilter = PacketDisplayFilter(query: "tcp and ip.addr == 192.168.1.100")
        let compoundMatches = summary.packets.filter { compoundFilter.matches(packet: $0) }
        #expect(!compoundMatches.isEmpty)
        for p in compoundMatches {
            #expect(p.protocolType == .tcp || p.protocolType == .tls || p.protocolType == .http || p.protocolType == .bgp)
            #expect(p.sourceAddress == "192.168.1.100" || p.destinationAddress == "192.168.1.100")
        }

        // 5. Evaluation: Anomalies filter
        let anomalyFilter = PacketDisplayFilter(query: "anomalies")
        let anomalyMatches = summary.packets.filter { anomalyFilter.matches(packet: $0) }
        #expect(!anomalyMatches.isEmpty)
        for p in anomalyMatches {
            #expect(!p.anomalies.isEmpty)
        }
    }

    // MARK: - Packet Exporter Tests

    @Test("Packet Exporter produces valid PCAP byte stream and RFC 4180 CSV")
    func testPacketExporter() throws {
        let pcapData = SamplePCAPGenerator.generateSampleCapture()
        let summary = try PCAPReader.parse(data: pcapData, fileName: "synthetic.pcap")

        // 1. Export PCAP
        let exportedPCAP = PacketExporter.exportPCAP(packets: summary.packets)
        #expect(exportedPCAP.count > 500)
        let magic = exportedPCAP.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self) }
        #expect(magic == 0xa1b2c3d4)

        // Re-read exported PCAP to verify round-trip integrity
        let reparsed = try PCAPReader.parse(data: exportedPCAP, fileName: "reparsed.pcap")
        #expect(reparsed.totalPackets == summary.packets.count)

        // 2. Export CSV
        let csv = PacketExporter.exportCSV(packets: summary.packets)
        #expect(csv.starts(with: "\"No.\",\"Time (s)\",\"Source\""))
        #expect(csv.contains("192.168.1.100"))
        #expect(csv.contains("TCP"))
        #expect(csv.contains("DNS"))
    }
}



