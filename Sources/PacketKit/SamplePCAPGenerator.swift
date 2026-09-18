import Foundation

public enum SamplePCAPGenerator {

    public static func generateSampleCapture() -> Data {
        var data = Data()

        // 1. Classic PCAP Global Header (24 bytes in Host Byte Order)
        appendHostUInt32(&data, 0xa1b2c3d4) // magic
        appendHostUInt16(&data, 2)          // major
        appendHostUInt16(&data, 4)          // minor
        appendHostUInt32(&data, 0)          // thiszone
        appendHostUInt32(&data, 0)          // sigfigs
        appendHostUInt32(&data, 65535)      // snaplen
        appendHostUInt32(&data, 1)          // linktype (Ethernet)

        let baseEpoch: UInt32 = 1718000000 // Sample timestamp

        // Helper to append a packet with PCAP packet header (Host Byte Order)
        func appendPacket(deltaSec: UInt32, deltaUsec: UInt32, frame: Data) {
            appendHostUInt32(&data, baseEpoch + deltaSec)
            appendHostUInt32(&data, deltaUsec)
            appendHostUInt32(&data, UInt32(frame.count))
            appendHostUInt32(&data, UInt32(frame.count))
            data.append(frame)
        }

        let macHost: [UInt8] = [0x00, 0x1A, 0x2B, 0x3C, 0x4D, 0x5E]
        let macGw: [UInt8] = [0x00, 0x50, 0x56, 0xC0, 0x00, 0x01]
        let macBcast: [UInt8] = [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]

        let ipHost = [192, 168, 1, 100]
        let ipGw = [192, 168, 1, 1]
        let ipServer = [93, 184, 216, 34]
        let ipDNS = [8, 8, 8, 8]

        // --- Packet 1: ARP Request ---
        var p1 = Data()
        p1.append(contentsOf: macBcast)
        p1.append(contentsOf: macHost)
        appendNetUInt16(&p1, 0x0806) // EtherType ARP
        appendNetUInt16(&p1, 1)      // Hardware type Ethernet
        appendNetUInt16(&p1, 0x0800) // Protocol IPv4
        p1.append(6)                 // HW size
        p1.append(4)                 // Proto size
        appendNetUInt16(&p1, 1)      // Opcode Request
        p1.append(contentsOf: macHost)
        p1.append(contentsOf: ipHost.map { UInt8($0) })
        p1.append(contentsOf: [0, 0, 0, 0, 0, 0])
        p1.append(contentsOf: ipGw.map { UInt8($0) })
        appendPacket(deltaSec: 0, deltaUsec: 100_000, frame: p1)

        // --- Packet 2: ARP Reply ---
        var p2 = Data()
        p2.append(contentsOf: macHost)
        p2.append(contentsOf: macGw)
        appendNetUInt16(&p2, 0x0806)
        appendNetUInt16(&p2, 1)
        appendNetUInt16(&p2, 0x0800)
        p2.append(6)
        p2.append(4)
        appendNetUInt16(&p2, 2) // Opcode Reply
        p2.append(contentsOf: macGw)
        p2.append(contentsOf: ipGw.map { UInt8($0) })
        p2.append(contentsOf: macHost)
        p2.append(contentsOf: ipHost.map { UInt8($0) })
        appendPacket(deltaSec: 0, deltaUsec: 105_000, frame: p2)

        // Helper to build an IPv4 frame with TCP/UDP payload
        func makeIPv4Frame(
            srcMAC: [UInt8],
            dstMAC: [UInt8],
            srcIP: [Int],
            dstIP: [Int],
            proto: UInt8,
            payload: Data
        ) -> Data {
            var frame = Data()
            frame.append(contentsOf: dstMAC)
            frame.append(contentsOf: srcMAC)
            appendNetUInt16(&frame, 0x0800) // EtherType IPv4

            let ipTotalLen = 20 + payload.count
            frame.append(0x45) // Version 4, IHL 5 (20B)
            frame.append(0x00) // DSCP
            appendNetUInt16(&frame, UInt16(ipTotalLen))
            appendNetUInt16(&frame, 0x1234) // Ident
            appendNetUInt16(&frame, 0x4000) // Don't Fragment
            frame.append(64)                // TTL
            frame.append(proto)
            appendNetUInt16(&frame, 0x0000) // Checksum dummy
            frame.append(contentsOf: srcIP.map { UInt8($0) })
            frame.append(contentsOf: dstIP.map { UInt8($0) })
            frame.append(payload)
            return frame
        }

        func makeTCPPayload(
            srcPort: UInt16,
            dstPort: UInt16,
            seq: UInt32,
            ack: UInt32,
            flags: UInt8,
            window: UInt16,
            dataBytes: Data = Data()
        ) -> Data {
            var seg = Data()
            appendNetUInt16(&seg, srcPort)
            appendNetUInt16(&seg, dstPort)
            appendNetUInt32(&seg, seq)
            appendNetUInt32(&seg, ack)
            seg.append(0x50) // Data Offset 5 (20B)
            seg.append(flags)
            appendNetUInt16(&seg, window)
            appendNetUInt16(&seg, 0x0000) // Checksum
            appendNetUInt16(&seg, 0x0000) // Urgent pointer
            seg.append(dataBytes)
            return seg
        }

        func makeUDPPayload(srcPort: UInt16, dstPort: UInt16, dataBytes: Data) -> Data {
            var seg = Data()
            appendNetUInt16(&seg, srcPort)
            appendNetUInt16(&seg, dstPort)
            appendNetUInt16(&seg, UInt16(8 + dataBytes.count))
            appendNetUInt16(&seg, 0x0000)
            seg.append(dataBytes)
            return seg
        }

        // --- Packet 3: DNS Query ---
        var dnsQ = Data()
        appendNetUInt16(&dnsQ, 0x1A2B) // TxID
        appendNetUInt16(&dnsQ, 0x0100) // Standard Query
        appendNetUInt16(&dnsQ, 1)      // 1 Question
        appendNetUInt16(&dnsQ, 0)      // 0 Answer
        appendNetUInt16(&dnsQ, 0)
        appendNetUInt16(&dnsQ, 0)
        // api.example.com
        dnsQ.append(contentsOf: [3, 0x61, 0x70, 0x69]) // api
        dnsQ.append(contentsOf: [7, 0x65, 0x78, 0x61, 0x6d, 0x70, 0x6c, 0x65]) // example
        dnsQ.append(contentsOf: [3, 0x63, 0x6f, 0x6d]) // com
        dnsQ.append(0) // end of name
        appendNetUInt16(&dnsQ, 1) // Type A
        appendNetUInt16(&dnsQ, 1) // Class IN
        let p3 = makeIPv4Frame(srcMAC: macHost, dstMAC: macGw, srcIP: ipHost, dstIP: ipGw, proto: 17, payload: makeUDPPayload(srcPort: 52410, dstPort: 53, dataBytes: dnsQ))
        appendPacket(deltaSec: 0, deltaUsec: 200_000, frame: p3)

        // --- Packet 4: DNS Response ---
        var dnsR = Data()
        appendNetUInt16(&dnsR, 0x1A2B)
        appendNetUInt16(&dnsR, 0x8180) // Standard Response, NoError
        appendNetUInt16(&dnsR, 1)      // 1 Question
        appendNetUInt16(&dnsR, 1)      // 1 Answer
        appendNetUInt16(&dnsR, 0)
        appendNetUInt16(&dnsR, 0)
        dnsR.append(contentsOf: [3, 0x61, 0x70, 0x69, 7, 0x65, 0x78, 0x61, 0x6d, 0x70, 0x6c, 0x65, 3, 0x63, 0x6f, 0x6d, 0])
        appendNetUInt16(&dnsR, 1)
        appendNetUInt16(&dnsR, 1)
        // Answer
        appendNetUInt16(&dnsR, 0xC00C) // pointer to name
        appendNetUInt16(&dnsR, 1)      // Type A
        appendNetUInt16(&dnsR, 1)      // Class IN
        appendNetUInt32(&dnsR, 300)    // TTL 300s
        appendNetUInt16(&dnsR, 4)      // Data length 4
        dnsR.append(contentsOf: ipServer.map { UInt8($0) })
        let p4 = makeIPv4Frame(srcMAC: macGw, dstMAC: macHost, srcIP: ipGw, dstIP: ipHost, proto: 17, payload: makeUDPPayload(srcPort: 53, dstPort: 52410, dataBytes: dnsR))
        appendPacket(deltaSec: 0, deltaUsec: 215_000, frame: p4)

        // --- Packet 5: TCP SYN (49214 -> 443) ---
        let tcpSyn = makeTCPPayload(srcPort: 49214, dstPort: 443, seq: 1000, ack: 0, flags: 0x02, window: 65535)
        let p5 = makeIPv4Frame(srcMAC: macHost, dstMAC: macGw, srcIP: ipHost, dstIP: ipServer, proto: 6, payload: tcpSyn)
        appendPacket(deltaSec: 0, deltaUsec: 300_000, frame: p5)

        // --- Packet 6: TCP SYN-ACK (443 -> 49214) ---
        let tcpSynAck = makeTCPPayload(srcPort: 443, dstPort: 49214, seq: 5000, ack: 1001, flags: 0x12, window: 65535)
        let p6 = makeIPv4Frame(srcMAC: macGw, dstMAC: macHost, srcIP: ipServer, dstIP: ipHost, proto: 6, payload: tcpSynAck)
        appendPacket(deltaSec: 0, deltaUsec: 320_000, frame: p6)

        // --- Packet 7: TCP ACK (49214 -> 443) ---
        let tcpAck = makeTCPPayload(srcPort: 49214, dstPort: 443, seq: 1001, ack: 5001, flags: 0x10, window: 65535)
        let p7 = makeIPv4Frame(srcMAC: macHost, dstMAC: macGw, srcIP: ipHost, dstIP: ipServer, proto: 6, payload: tcpAck)
        appendPacket(deltaSec: 0, deltaUsec: 321_000, frame: p7)

        // --- Packet 8: TLS ClientHello with SNI api.example.com ---
        var tlsRecord = Data([0x16, 0x03, 0x01, 0x00, 0x4B]) // ContentType 22 (Handshake), TLS 1.0, length 75
        var clientHello = Data([0x01, 0x00, 0x00, 0x47, 0x03, 0x03]) // Handshake Type 1, length 71, TLS 1.2
        clientHello.append(Data(repeating: 0xAA, count: 32)) // Random
        clientHello.append(0x00) // Session ID len 0
        appendNetUInt16(&clientHello, 2) // Cipher suites len 2
        appendNetUInt16(&clientHello, 0x1301) // TLS_AES_128_GCM_SHA256
        clientHello.append(0x01) // Comp methods len 1
        clientHello.append(0x00) // null comp
        // Extension: server_name
        var sniExt = Data()
        appendNetUInt16(&sniExt, 0x0000) // Extension type server_name
        let sniHost = "api.example.com"
        let sniHostBytes = Data(sniHost.utf8)
        let extLen = 5 + sniHostBytes.count
        appendNetUInt16(&sniExt, UInt16(extLen))
        appendNetUInt16(&sniExt, UInt16(3 + sniHostBytes.count)) // ServerNameList len
        sniExt.append(0x00) // host_name type
        appendNetUInt16(&sniExt, UInt16(sniHostBytes.count))
        sniExt.append(sniHostBytes)
        // Extensions wrapper
        appendNetUInt16(&clientHello, UInt16(sniExt.count))
        clientHello.append(sniExt)
        tlsRecord.append(clientHello)

        let tcpTls = makeTCPPayload(srcPort: 49214, dstPort: 443, seq: 1001, ack: 5001, flags: 0x18, window: 65535, dataBytes: tlsRecord)
        let p8 = makeIPv4Frame(srcMAC: macHost, dstMAC: macGw, srcIP: ipHost, dstIP: ipServer, proto: 6, payload: tcpTls)
        appendPacket(deltaSec: 0, deltaUsec: 330_000, frame: p8)

        // --- Packet 9: TCP ACK from Server ---
        let nextAck = 1001 + UInt32(tlsRecord.count)
        let tcpAck2 = makeTCPPayload(srcPort: 443, dstPort: 49214, seq: 5001, ack: nextAck, flags: 0x10, window: 65535)
        let p9 = makeIPv4Frame(srcMAC: macGw, dstMAC: macHost, srcIP: ipServer, dstIP: ipHost, proto: 6, payload: tcpAck2)
        appendPacket(deltaSec: 0, deltaUsec: 350_000, frame: p9)

        // --- Packet 10: TCP Retransmission of Packet 8 (Anomaly) ---
        appendPacket(deltaSec: 0, deltaUsec: 500_000, frame: p8)

        // --- Packet 11: TCP Zero Window Stall (Anomaly) ---
        let tcpZeroWin = makeTCPPayload(srcPort: 443, dstPort: 49214, seq: 5001, ack: nextAck, flags: 0x10, window: 0)
        let p11 = makeIPv4Frame(srcMAC: macGw, dstMAC: macHost, srcIP: ipServer, dstIP: ipHost, proto: 6, payload: tcpZeroWin)
        appendPacket(deltaSec: 0, deltaUsec: 510_000, frame: p11)

        // --- Packet 12: TCP Window Update ---
        let tcpWinUpd = makeTCPPayload(srcPort: 443, dstPort: 49214, seq: 5001, ack: nextAck, flags: 0x10, window: 32768)
        let p12 = makeIPv4Frame(srcMAC: macGw, dstMAC: macHost, srcIP: ipServer, dstIP: ipHost, proto: 6, payload: tcpWinUpd)
        appendPacket(deltaSec: 0, deltaUsec: 520_000, frame: p12)

        // --- Packet 13: HTTP GET Request ---
        let httpReq = Data("GET /health HTTP/1.1\r\nHost: api.example.com\r\n\r\n".utf8)
        let tcpHttp = makeTCPPayload(srcPort: 51200, dstPort: 80, seq: 2001, ack: 8001, flags: 0x18, window: 65535, dataBytes: httpReq)
        let p13 = makeIPv4Frame(srcMAC: macHost, dstMAC: macGw, srcIP: ipHost, dstIP: ipServer, proto: 6, payload: tcpHttp)
        appendPacket(deltaSec: 1, deltaUsec: 100_000, frame: p13)

        // --- Packet 14: TCP Connection Reset (RST Anomaly) ---
        let tcpRst = makeTCPPayload(srcPort: 80, dstPort: 51200, seq: 8001, ack: 2001 + UInt32(httpReq.count), flags: 0x14, window: 0)
        let p14 = makeIPv4Frame(srcMAC: macGw, dstMAC: macHost, srcIP: ipServer, dstIP: ipHost, proto: 6, payload: tcpRst)
        appendPacket(deltaSec: 1, deltaUsec: 110_000, frame: p14)

        // --- Packet 15: ICMP Echo Request ---
        var icmpReq = Data([8, 0, 0, 0, 0x11, 0x22, 0x00, 0x01]) // Type 8, Code 0, Ident, Seq 1
        icmpReq.append(Data("abcdefghijklmnopqrstuvwabcdefghi".utf8))
        let p15 = makeIPv4Frame(srcMAC: macHost, dstMAC: macGw, srcIP: ipHost, dstIP: ipDNS, proto: 1, payload: icmpReq)
        appendPacket(deltaSec: 1, deltaUsec: 200_000, frame: p15)

        // --- Packet 16: ICMP Echo Reply ---
        var icmpReply = Data([0, 0, 0, 0, 0x11, 0x22, 0x00, 0x01]) // Type 0, Code 0, Ident, Seq 1
        icmpReply.append(Data("abcdefghijklmnopqrstuvwabcdefghi".utf8))
        let p16 = makeIPv4Frame(srcMAC: macGw, dstMAC: macHost, srcIP: ipDNS, dstIP: ipHost, proto: 1, payload: icmpReply)
        appendPacket(deltaSec: 1, deltaUsec: 212_000, frame: p16)

        // --- Packet 17: DHCP Discover ---
        var dhcpDisc = Data(count: 240)
        dhcpDisc[0] = 1 // BootRequest
        dhcpDisc[1] = 1 // Ethernet (10Mb)
        dhcpDisc[2] = 6 // HW addr length
        dhcpDisc[3] = 0 // Hops
        // XID = 0x3903F326
        dhcpDisc[4] = 0x39; dhcpDisc[5] = 0x03; dhcpDisc[6] = 0xF3; dhcpDisc[7] = 0x26
        // Client MAC at offset 28
        for i in 0..<6 { dhcpDisc[28 + i] = macHost[i] }
        // Magic Cookie at offset 236
        dhcpDisc[236] = 0x63; dhcpDisc[237] = 0x82; dhcpDisc[238] = 0x53; dhcpDisc[239] = 0x63
        // Option 53: DHCP Message Type = Discover (1)
        dhcpDisc.append(contentsOf: [53, 1, 1])
        // Option 12: Host Name = "MacBookPro"
        let hostNameBytes = Data("MacBookPro".utf8)
        dhcpDisc.append(contentsOf: [12, UInt8(hostNameBytes.count)])
        dhcpDisc.append(hostNameBytes)
        // Option 255: End
        dhcpDisc.append(255)
        let p17 = makeIPv4Frame(srcMAC: macHost, dstMAC: macBcast, srcIP: [0, 0, 0, 0], dstIP: [255, 255, 255, 255], proto: 17, payload: makeUDPPayload(srcPort: 68, dstPort: 67, dataBytes: dhcpDisc))
        appendPacket(deltaSec: 1, deltaUsec: 300_000, frame: p17)

        // --- Packet 18: DHCP Offer ---
        var dhcpOffer = Data(count: 240)
        dhcpOffer[0] = 2 // BootReply
        dhcpOffer[1] = 1
        dhcpOffer[2] = 6
        dhcpOffer[3] = 0
        dhcpOffer[4] = 0x39; dhcpOffer[5] = 0x03; dhcpOffer[6] = 0xF3; dhcpOffer[7] = 0x26
        // yiaddr (Your IP) = 192.168.1.100
        for i in 0..<4 { dhcpOffer[16 + i] = UInt8(ipHost[i]) }
        // siaddr (Server IP) = 192.168.1.1
        for i in 0..<4 { dhcpOffer[20 + i] = UInt8(ipGw[i]) }
        for i in 0..<6 { dhcpOffer[28 + i] = macHost[i] }
        dhcpOffer[236] = 0x63; dhcpOffer[237] = 0x82; dhcpOffer[238] = 0x53; dhcpOffer[239] = 0x63
        // Option 53: Offer (2)
        dhcpOffer.append(contentsOf: [53, 1, 2])
        // Option 54: Server ID = 192.168.1.1
        dhcpOffer.append(contentsOf: [54, 4, 192, 168, 1, 1])
        // Option 51: Lease = 86400s
        dhcpOffer.append(contentsOf: [51, 4, 0x00, 0x01, 0x51, 0x80])
        // Option 1: Subnet = 255.255.255.0
        dhcpOffer.append(contentsOf: [1, 4, 255, 255, 255, 0])
        // Option 3: Router = 192.168.1.1
        dhcpOffer.append(contentsOf: [3, 4, 192, 168, 1, 1])
        // Option 6: DNS = 8.8.8.8
        dhcpOffer.append(contentsOf: [6, 4, 8, 8, 8, 8])
        dhcpOffer.append(255)
        let p18 = makeIPv4Frame(srcMAC: macGw, dstMAC: macHost, srcIP: ipGw, dstIP: ipHost, proto: 17, payload: makeUDPPayload(srcPort: 67, dstPort: 68, dataBytes: dhcpOffer))
        appendPacket(deltaSec: 1, deltaUsec: 325_000, frame: p18)

        // --- Packet 19: BGP Keepalive ---
        var bgpKeepalive = Data(repeating: 0xFF, count: 16) // Marker
        appendNetUInt16(&bgpKeepalive, 19) // Length
        bgpKeepalive.append(4) // Type 4: KEEPALIVE
        let tcpBgp = makeTCPPayload(srcPort: 179, dstPort: 54120, seq: 10001, ack: 20001, flags: 0x18, window: 65535, dataBytes: bgpKeepalive)
        let p19 = makeIPv4Frame(srcMAC: macGw, dstMAC: macHost, srcIP: ipGw, dstIP: ipHost, proto: 6, payload: tcpBgp)
        appendPacket(deltaSec: 1, deltaUsec: 400_000, frame: p19)

        // --- Packet 20: NTP Client Request ---
        var ntpReq = Data(count: 48)
        ntpReq[0] = 0x23 // LI 0, VN 4, Mode 3 (Client)
        let p20 = makeIPv4Frame(srcMAC: macHost, dstMAC: macGw, srcIP: ipHost, dstIP: [129, 6, 15, 28], proto: 17, payload: makeUDPPayload(srcPort: 51234, dstPort: 123, dataBytes: ntpReq))
        appendPacket(deltaSec: 1, deltaUsec: 500_000, frame: p20)

        // --- Packet 21: NTP Server Response ---
        var ntpResp = Data(count: 48)
        ntpResp[0] = 0x24 // LI 0, VN 4, Mode 4 (Server)
        ntpResp[1] = 1    // Stratum 1 (Primary reference)
        ntpResp[2] = 6    // Poll 6
        ntpResp[3] = 0xEC // Precision -20
        // RefID = "NIST"
        let nistBytes = Data("NIST".utf8)
        for i in 0..<4 { ntpResp[12 + i] = nistBytes[i] }
        let p21 = makeIPv4Frame(srcMAC: macGw, dstMAC: macHost, srcIP: [129, 6, 15, 28], dstIP: ipHost, proto: 17, payload: makeUDPPayload(srcPort: 123, dstPort: 51234, dataBytes: ntpResp))
        appendPacket(deltaSec: 1, deltaUsec: 535_000, frame: p21)

        return data
    }

    // Host byte order for PCAP headers
    private static func appendHostUInt16(_ data: inout Data, _ value: UInt16) {
        var host = value
        withUnsafeBytes(of: &host) { data.append(contentsOf: $0) }
    }

    private static func appendHostUInt32(_ data: inout Data, _ value: UInt32) {
        var host = value
        withUnsafeBytes(of: &host) { data.append(contentsOf: $0) }
    }

    // Network byte order (big endian) for on-wire packet fields
    private static func appendNetUInt16(_ data: inout Data, _ value: UInt16) {
        var big = value.bigEndian
        data.append(Data(bytes: &big, count: 2))
    }

    private static func appendNetUInt32(_ data: inout Data, _ value: UInt32) {
        var big = value.bigEndian
        data.append(Data(bytes: &big, count: 4))
    }
}
