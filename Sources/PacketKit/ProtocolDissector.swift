import Foundation

public struct DissectionResult: Sendable {
    public let protocolType: PacketProtocol
    public let sourceAddress: String
    public let destinationAddress: String
    public let sourcePort: Int?
    public let destinationPort: Int?
    public let summary: String
    public let tcpFlags: TCPFlags?
    public let tcpSeq: UInt32?
    public let tcpAck: UInt32?
    public let tcpWindow: UInt16?
    public let payloadLength: Int
    public let layers: [DissectedLayer]

    public init(
        protocolType: PacketProtocol,
        sourceAddress: String,
        destinationAddress: String,
        sourcePort: Int? = nil,
        destinationPort: Int? = nil,
        summary: String,
        tcpFlags: TCPFlags? = nil,
        tcpSeq: UInt32? = nil,
        tcpAck: UInt32? = nil,
        tcpWindow: UInt16? = nil,
        payloadLength: Int = 0,
        layers: [DissectedLayer] = []
    ) {
        self.protocolType = protocolType
        self.sourceAddress = sourceAddress
        self.destinationAddress = destinationAddress
        self.sourcePort = sourcePort
        self.destinationPort = destinationPort
        self.summary = summary
        self.tcpFlags = tcpFlags
        self.tcpSeq = tcpSeq
        self.tcpAck = tcpAck
        self.tcpWindow = tcpWindow
        self.payloadLength = payloadLength
        self.layers = layers
    }
}

public enum ProtocolDissector {

    public static func dissect(packetData: Data, packetNumber: Int, wireLength: Int) -> DissectionResult {
        var layers: [DissectedLayer] = []
        var offset = 0

        // 1. Frame Layer
        let frameFields = [
            LayerField(name: "Frame Number", value: "\(packetNumber)", hexOffset: 0, hexLength: packetData.count),
            LayerField(name: "Frame Length on Wire", value: "\(wireLength) bytes", hexOffset: 0, hexLength: packetData.count),
            LayerField(name: "Captured Length", value: "\(packetData.count) bytes", hexOffset: 0, hexLength: packetData.count)
        ]
        layers.append(DissectedLayer(name: "Frame \(packetNumber)", summary: "\(wireLength) bytes on wire, \(packetData.count) bytes captured", fields: frameFields))

        // Ensure minimum Ethernet II header length (14 bytes)
        guard packetData.count >= 14 else {
            return DissectionResult(
                protocolType: .other("Short Frame"),
                sourceAddress: "Unknown",
                destinationAddress: "Unknown",
                summary: "Malformed or truncated frame (\(packetData.count) bytes)",
                layers: layers
            )
        }

        // 2. Ethernet II Layer
        let dstMAC = formatMAC(data: packetData.subdata(in: 0..<6))
        let srcMAC = formatMAC(data: packetData.subdata(in: 6..<12))
        var etherType = UInt16(packetData[12]) << 8 | UInt16(packetData[13])
        offset = 14

        var vlanID: Int? = nil
        if etherType == 0x8100 && packetData.count >= 18 { // 802.1Q VLAN
            let tci = UInt16(packetData[14]) << 8 | UInt16(packetData[15])
            vlanID = Int(tci & 0x0FFF)
            etherType = UInt16(packetData[16]) << 8 | UInt16(packetData[17])
            offset = 18
        }

        var ethFields = [
            LayerField(name: "Destination MAC", value: dstMAC, hexOffset: 0, hexLength: 6),
            LayerField(name: "Source MAC", value: srcMAC, hexOffset: 6, hexLength: 6),
            LayerField(name: "EtherType", value: String(format: "0x%04X", etherType), hexOffset: offset - 2, hexLength: 2)
        ]
        if let vlan = vlanID {
            ethFields.append(LayerField(name: "802.1Q VLAN ID", value: "\(vlan)", hexOffset: 14, hexLength: 2))
        }
        layers.append(DissectedLayer(name: "Ethernet II", summary: "Src: \(srcMAC), Dst: \(dstMAC)", fields: ethFields))

        // 3. Demux Network Layer
        switch etherType {
        case 0x0806: // ARP
            return dissectARP(data: packetData, offset: offset, layers: layers)

        case 0x0800: // IPv4
            return dissectIPv4(data: packetData, offset: offset, layers: layers)

        case 0x86DD: // IPv6
            return dissectIPv6(data: packetData, offset: offset, layers: layers)

        case 0x88CC: // IEEE 802.1AB LLDP
            let (_, summary, lldpLayers) = LLDPDissector.dissect(data: packetData, offset: offset)
            PassiveNeighborDiscoveryEngine.shared.processFrame(packetData: packetData)
            return DissectionResult(
                protocolType: .other("LLDP"),
                sourceAddress: srcMAC,
                destinationAddress: dstMAC,
                summary: summary,
                payloadLength: packetData.count - offset,
                layers: layers + lldpLayers
            )

        default:
            if dstMAC == "01:00:0c:cc:cc:cc" || (packetData.count > offset + 8 && packetData[offset] == 0xAA && packetData[offset + 1] == 0xAA) {
                let cdpOffset = (packetData.count >= offset + 8 && packetData[offset] == 0xAA) ? offset + 8 : offset
                let (_, summary, cdpLayers) = CDPDissector.dissect(data: packetData, offset: cdpOffset)
                PassiveNeighborDiscoveryEngine.shared.processFrame(packetData: packetData)
                return DissectionResult(
                    protocolType: .other("CDP"),
                    sourceAddress: srcMAC,
                    destinationAddress: dstMAC,
                    summary: summary,
                    payloadLength: packetData.count - offset,
                    layers: layers + cdpLayers
                )
            }

            return DissectionResult(
                protocolType: .other(String(format: "EtherType 0x%04X", etherType)),
                sourceAddress: srcMAC,
                destinationAddress: dstMAC,
                summary: "EtherType: \(String(format: "0x%04X", etherType)) (\(packetData.count - offset) bytes payload)",
                layers: layers
            )
        }
    }

    // MARK: - ARP Dissection
    private static func dissectARP(data: Data, offset: Int, layers: [DissectedLayer]) -> DissectionResult {
        var updatedLayers = layers
        guard data.count >= offset + 28 else {
            return DissectionResult(
                protocolType: .arp,
                sourceAddress: "ARP",
                destinationAddress: "Broadcast",
                summary: "Malformed ARP Header",
                layers: layers
            )
        }

        let hType = UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
        let pType = UInt16(data[offset + 2]) << 8 | UInt16(data[offset + 3])
        let opcode = UInt16(data[offset + 6]) << 8 | UInt16(data[offset + 7])
        let senderMAC = formatMAC(data: data.subdata(in: (offset + 8)..<(offset + 14)))
        let senderIP = formatIPv4(data: data.subdata(in: (offset + 14)..<(offset + 18)))
        let targetMAC = formatMAC(data: data.subdata(in: (offset + 18)..<(offset + 24)))
        let targetIP = formatIPv4(data: data.subdata(in: (offset + 24)..<(offset + 28)))

        let opString = (opcode == 1) ? "Request" : (opcode == 2 ? "Reply" : "Unknown (\(opcode))")
        let summary = (opcode == 1) ? "Who has \(targetIP)? Tell \(senderIP)" : "\(senderIP) is at \(senderMAC)"

        let arpFields = [
            LayerField(name: "Hardware Type", value: String(format: "0x%04X (%d)", hType, hType), hexOffset: offset, hexLength: 2),
            LayerField(name: "Protocol Type", value: String(format: "0x%04X", pType), hexOffset: offset + 2, hexLength: 2),
            LayerField(name: "Hardware Size", value: "\(data[offset + 4])", hexOffset: offset + 4, hexLength: 1),
            LayerField(name: "Protocol Size", value: "\(data[offset + 5])", hexOffset: offset + 5, hexLength: 1),
            LayerField(name: "Opcode", value: "\(opString) (\(opcode))", hexOffset: offset + 6, hexLength: 2),
            LayerField(name: "Sender MAC", value: senderMAC, hexOffset: offset + 8, hexLength: 6),
            LayerField(name: "Sender IP", value: senderIP, hexOffset: offset + 14, hexLength: 4),
            LayerField(name: "Target MAC", value: targetMAC, hexOffset: offset + 18, hexLength: 6),
            LayerField(name: "Target IP", value: targetIP, hexOffset: offset + 24, hexLength: 4)
        ]
        updatedLayers.append(DissectedLayer(name: "Address Resolution Protocol (\(opString))", summary: summary, fields: arpFields))

        return DissectionResult(
            protocolType: .arp,
            sourceAddress: senderIP,
            destinationAddress: targetIP,
            summary: summary,
            layers: updatedLayers
        )
    }

    // MARK: - IPv4 Dissection
    private static func dissectIPv4(data: Data, offset: Int, layers: [DissectedLayer]) -> DissectionResult {
        var updatedLayers = layers
        guard data.count >= offset + 20 else {
            return DissectionResult(
                protocolType: .other("IPv4"),
                sourceAddress: "Unknown",
                destinationAddress: "Unknown",
                summary: "Truncated IPv4 Header",
                layers: layers
            )
        }

        let firstByte = data[offset]
        let version = firstByte >> 4
        let ihl = Int(firstByte & 0x0F) * 4
        let totalLen = Int(UInt16(data[offset + 2]) << 8 | UInt16(data[offset + 3]))
        let ident = UInt16(data[offset + 4]) << 8 | UInt16(data[offset + 5])
        let ttl = data[offset + 8]
        let protocolNum = data[offset + 9]
        let checksum = UInt16(data[offset + 10]) << 8 | UInt16(data[offset + 11])
        let srcIP = formatIPv4(data: data.subdata(in: (offset + 12)..<(offset + 16)))
        let dstIP = formatIPv4(data: data.subdata(in: (offset + 16)..<(offset + 20)))

        let ipFields = [
            LayerField(name: "Version", value: "\(version)", hexOffset: offset, hexLength: 1),
            LayerField(name: "Header Length", value: "\(ihl) bytes", hexOffset: offset, hexLength: 1),
            LayerField(name: "Total Length", value: "\(totalLen) bytes", hexOffset: offset + 2, hexLength: 2),
            LayerField(name: "Identification", value: String(format: "0x%04X (%d)", ident, ident), hexOffset: offset + 4, hexLength: 2),
            LayerField(name: "Time to Live (TTL)", value: "\(ttl)", hexOffset: offset + 8, hexLength: 1),
            LayerField(name: "Protocol", value: "\(protocolNum)", hexOffset: offset + 9, hexLength: 1),
            LayerField(name: "Header Checksum", value: String(format: "0x%04X", checksum), hexOffset: offset + 10, hexLength: 2),
            LayerField(name: "Source IP", value: srcIP, hexOffset: offset + 12, hexLength: 4),
            LayerField(name: "Destination IP", value: dstIP, hexOffset: offset + 16, hexLength: 4)
        ]
        updatedLayers.append(DissectedLayer(name: "Internet Protocol Version 4", summary: "Src: \(srcIP), Dst: \(dstIP)", fields: ipFields))

        let transportOffset = offset + ihl
        guard data.count >= transportOffset else {
            return DissectionResult(
                protocolType: .other("IPv4"),
                sourceAddress: srcIP,
                destinationAddress: dstIP,
                summary: "IPv4 Fragment or Truncated Payload",
                layers: updatedLayers
            )
        }

        // OSPFv2 (Protocol 89)
        if protocolNum == 89 {
            return dissectOSPF(data: data, offset: transportOffset, srcIP: srcIP, dstIP: dstIP, layers: updatedLayers)
        }

        return dissectTransport(
            data: data,
            offset: transportOffset,
            protocolNum: protocolNum,
            srcIP: srcIP,
            dstIP: dstIP,
            ipTotalLen: totalLen,
            ipHeaderLen: ihl,
            layers: updatedLayers
        )
    }

    // MARK: - IPv6 Dissection
    private static func dissectIPv6(data: Data, offset: Int, layers: [DissectedLayer]) -> DissectionResult {
        var updatedLayers = layers
        guard data.count >= offset + 40 else {
            return DissectionResult(
                protocolType: .other("IPv6"),
                sourceAddress: "Unknown",
                destinationAddress: "Unknown",
                summary: "Truncated IPv6 Header",
                layers: layers
            )
        }

        let payloadLen = Int(UInt16(data[offset + 4]) << 8 | UInt16(data[offset + 5]))
        let nextHeader = data[offset + 6]
        let hopLimit = data[offset + 7]
        let srcIP = formatIPv6(data: data.subdata(in: (offset + 8)..<(offset + 24)))
        let dstIP = formatIPv6(data: data.subdata(in: (offset + 24)..<(offset + 40)))

        let ipFields = [
            LayerField(name: "Traffic Class & Flow Label", value: String(format: "0x%02X%02X%02X%02X", data[offset], data[offset+1], data[offset+2], data[offset+3]), hexOffset: offset, hexLength: 4),
            LayerField(name: "Payload Length", value: "\(payloadLen) bytes", hexOffset: offset + 4, hexLength: 2),
            LayerField(name: "Next Header", value: "\(nextHeader)", hexOffset: offset + 6, hexLength: 1),
            LayerField(name: "Hop Limit", value: "\(hopLimit)", hexOffset: offset + 7, hexLength: 1),
            LayerField(name: "Source IPv6", value: srcIP, hexOffset: offset + 8, hexLength: 16),
            LayerField(name: "Destination IPv6", value: dstIP, hexOffset: offset + 24, hexLength: 16)
        ]
        updatedLayers.append(DissectedLayer(name: "Internet Protocol Version 6", summary: "Src: \(srcIP), Dst: \(dstIP)", fields: ipFields))

        let transportOffset = offset + 40

        // OSPFv3 (Next Header 89)
        if nextHeader == 89 {
            return dissectOSPF(data: data, offset: transportOffset, srcIP: srcIP, dstIP: dstIP, layers: updatedLayers)
        }

        return dissectTransport(
            data: data,
            offset: transportOffset,
            protocolNum: nextHeader,
            srcIP: srcIP,
            dstIP: dstIP,
            ipTotalLen: payloadLen + 40,
            ipHeaderLen: 40,
            layers: updatedLayers
        )
    }

    // MARK: - Transport Layer Dissection (TCP, UDP, ICMP)
    private static func dissectTransport(
        data: Data,
        offset: Int,
        protocolNum: UInt8,
        srcIP: String,
        dstIP: String,
        ipTotalLen: Int,
        ipHeaderLen: Int,
        layers: [DissectedLayer]
    ) -> DissectionResult {
        var updatedLayers = layers

        switch protocolNum {
        case 6: // TCP
            guard data.count >= offset + 20 else {
                return DissectionResult(
                    protocolType: .tcp,
                    sourceAddress: srcIP,
                    destinationAddress: dstIP,
                    summary: "Truncated TCP Segment",
                    layers: updatedLayers
                )
            }

            let srcPort = Int(UInt16(data[offset]) << 8 | UInt16(data[offset + 1]))
            let dstPort = Int(UInt16(data[offset + 2]) << 8 | UInt16(data[offset + 3]))
            let seq = UInt32(data[offset + 4]) << 24 | UInt32(data[offset + 5]) << 16 | UInt32(data[offset + 6]) << 8 | UInt32(data[offset + 7])
            let ack = UInt32(data[offset + 8]) << 24 | UInt32(data[offset + 9]) << 16 | UInt32(data[offset + 10]) << 8 | UInt32(data[offset + 11])
            let dataOffset = Int(data[offset + 12] >> 4) * 4
            let rawFlags = data[offset + 13]
            let tcpFlags = TCPFlags(rawValue: rawFlags)
            let win = UInt16(data[offset + 14]) << 8 | UInt16(data[offset + 15])
            let chk = UInt16(data[offset + 16]) << 8 | UInt16(data[offset + 17])

            let payloadOffset = offset + dataOffset
            let actualPayloadLen = max(0, min(data.count - payloadOffset, ipTotalLen - ipHeaderLen - dataOffset))

            let tcpFields = [
                LayerField(name: "Source Port", value: "\(srcPort)", hexOffset: offset, hexLength: 2),
                LayerField(name: "Destination Port", value: "\(dstPort)", hexOffset: offset + 2, hexLength: 2),
                LayerField(name: "Sequence Number (raw)", value: "\(seq)", hexOffset: offset + 4, hexLength: 4),
                LayerField(name: "Acknowledgment Number (raw)", value: "\(ack)", hexOffset: offset + 8, hexLength: 4),
                LayerField(name: "Header Length", value: "\(dataOffset) bytes", hexOffset: offset + 12, hexLength: 1),
                LayerField(name: "Flags", value: "\(tcpFlags.flagSummary) (0x\(String(format: "%02X", rawFlags)))", hexOffset: offset + 13, hexLength: 1),
                LayerField(name: "Window Size", value: "\(win)", hexOffset: offset + 14, hexLength: 2),
                LayerField(name: "Checksum", value: String(format: "0x%04X", chk), hexOffset: offset + 16, hexLength: 2),
                LayerField(name: "Payload Length", value: "\(actualPayloadLen) bytes", hexOffset: payloadOffset, hexLength: actualPayloadLen)
            ]
            updatedLayers.append(DissectedLayer(name: "Transmission Control Protocol", summary: "\(srcPort) → \(dstPort) \(tcpFlags.flagSummary)", fields: tcpFields))

            // Application Protocol Demuxing
            var appProto: PacketProtocol = .tcp
            var summaryDetail: String? = nil

            if payloadOffset < data.count && actualPayloadLen > 0 {
                let payload = data.subdata(in: payloadOffset..<min(data.count, payloadOffset + actualPayloadLen))

                // BGP Check (Port 179)
                if (srcPort == 179 || dstPort == 179) && payload.count >= 19 {
                    if let bgpResult = dissectBGP(payload: payload, baseOffset: payloadOffset) {
                        appProto = .bgp
                        summaryDetail = bgpResult.summary
                        updatedLayers.append(bgpResult.layer)
                    }
                }
                // TLS check (443, 8443)
                else if (srcPort == 443 || dstPort == 443 || srcPort == 8443 || dstPort == 8443) && payload.count >= 5 && payload[0] == 0x16 {
                    appProto = .tls
                    if let tlsInfo = dissectTLS(payload: payload, baseOffset: payloadOffset) {
                        summaryDetail = tlsInfo.summary
                        updatedLayers.append(tlsInfo.layer)
                    }
                }
                // HTTP check (80, 8080)
                else if (srcPort == 80 || dstPort == 80 || srcPort == 8080 || dstPort == 8080) {
                    if let httpStr = String(data: payload.prefix(64), encoding: .utf8)?.components(separatedBy: "\r\n").first,
                       (httpStr.hasPrefix("GET ") || httpStr.hasPrefix("POST ") || httpStr.hasPrefix("HTTP/") || httpStr.hasPrefix("PUT ") || httpStr.hasPrefix("HEAD ")) {
                        appProto = .http
                        summaryDetail = httpStr
                        let httpFields = [LayerField(name: "First Line", value: httpStr, hexOffset: payloadOffset, hexLength: min(payload.count, 64))]
                        updatedLayers.append(DissectedLayer(name: "Hypertext Transfer Protocol", summary: httpStr, fields: httpFields))
                    }
                }
            }

            let summary = summaryDetail ?? "\(srcPort) → \(dstPort) \(tcpFlags.flagSummary) Seq=\(seq) Ack=\(ack) Win=\(win) Len=\(actualPayloadLen)"

            return DissectionResult(
                protocolType: appProto,
                sourceAddress: srcIP,
                destinationAddress: dstIP,
                sourcePort: srcPort,
                destinationPort: dstPort,
                summary: summary,
                tcpFlags: tcpFlags,
                tcpSeq: seq,
                tcpAck: ack,
                tcpWindow: win,
                payloadLength: actualPayloadLen,
                layers: updatedLayers
            )

        case 17: // UDP
            guard data.count >= offset + 8 else {
                return DissectionResult(
                    protocolType: .udp,
                    sourceAddress: srcIP,
                    destinationAddress: dstIP,
                    summary: "Truncated UDP Datagram",
                    layers: updatedLayers
                )
            }

            let srcPort = Int(UInt16(data[offset]) << 8 | UInt16(data[offset + 1]))
            let dstPort = Int(UInt16(data[offset + 2]) << 8 | UInt16(data[offset + 3]))
            let udpLen = Int(UInt16(data[offset + 4]) << 8 | UInt16(data[offset + 5]))
            let chk = UInt16(data[offset + 6]) << 8 | UInt16(data[offset + 7])

            let payloadOffset = offset + 8
            let actualPayloadLen = max(0, min(data.count - payloadOffset, udpLen - 8))

            let udpFields = [
                LayerField(name: "Source Port", value: "\(srcPort)", hexOffset: offset, hexLength: 2),
                LayerField(name: "Destination Port", value: "\(dstPort)", hexOffset: offset + 2, hexLength: 2),
                LayerField(name: "Length", value: "\(udpLen) bytes", hexOffset: offset + 4, hexLength: 2),
                LayerField(name: "Checksum", value: String(format: "0x%04X", chk), hexOffset: offset + 6, hexLength: 2),
                LayerField(name: "Payload Length", value: "\(actualPayloadLen) bytes", hexOffset: payloadOffset, hexLength: actualPayloadLen)
            ]
            updatedLayers.append(DissectedLayer(name: "User Datagram Protocol", summary: "\(srcPort) → \(dstPort) Len=\(actualPayloadLen)", fields: udpFields))

            var appProto: PacketProtocol = .udp
            var summary = "\(srcPort) → \(dstPort) Len=\(actualPayloadLen)"

            if actualPayloadLen > 0 && payloadOffset < data.count {
                let payload = data.subdata(in: payloadOffset..<min(data.count, payloadOffset + actualPayloadLen))

                // DHCP Check (Ports 67, 68)
                if (srcPort == 67 || dstPort == 67 || srcPort == 68 || dstPort == 68) && payload.count >= 240 {
                    if let dhcpResult = dissectDHCP(payload: payload, baseOffset: payloadOffset) {
                        appProto = .dhcp
                        summary = dhcpResult.summary
                        updatedLayers.append(dhcpResult.layer)
                    }
                }
                // NTP Check (Port 123)
                else if (srcPort == 123 || dstPort == 123) && payload.count >= 48 {
                    if let ntpResult = dissectNTP(payload: payload, baseOffset: payloadOffset) {
                        appProto = .ntp
                        summary = ntpResult.summary
                        updatedLayers.append(ntpResult.layer)
                    }
                }
                // SNMP Check (Ports 161, 162)
                else if (srcPort == 161 || dstPort == 161 || srcPort == 162 || dstPort == 162) && payload.count >= 10 {
                    if let snmpResult = dissectSNMP(payload: payload, baseOffset: payloadOffset) {
                        appProto = .snmp
                        summary = snmpResult.summary
                        updatedLayers.append(snmpResult.layer)
                    }
                }
                // DNS Check (Ports 53, 853)
                else if (srcPort == 53 || dstPort == 53 || srcPort == 853 || dstPort == 853) && payload.count >= 12 {
                    if let dnsResult = dissectDNS(payload: payload, baseOffset: payloadOffset) {
                        appProto = .dns
                        summary = dnsResult.summary
                        updatedLayers.append(dnsResult.layer)
                    }
                }
            }

            return DissectionResult(
                protocolType: appProto,
                sourceAddress: srcIP,
                destinationAddress: dstIP,
                sourcePort: srcPort,
                destinationPort: dstPort,
                summary: summary,
                payloadLength: actualPayloadLen,
                layers: updatedLayers
            )

        case 1, 58: // ICMP / ICMPv6
            guard data.count >= offset + 4 else {
                return DissectionResult(
                    protocolType: (protocolNum == 1) ? .icmp : .icmpv6,
                    sourceAddress: srcIP,
                    destinationAddress: dstIP,
                    summary: "Truncated ICMP Header",
                    layers: updatedLayers
                )
            }

            let type = data[offset]
            let code = data[offset + 1]
            let chk = UInt16(data[offset + 2]) << 8 | UInt16(data[offset + 3])

            var typeName = "Type \(type), Code \(code)"
            if protocolNum == 1 {
                if type == 8 { typeName = "Echo (ping) request" }
                else if type == 0 { typeName = "Echo (ping) reply" }
                else if type == 3 { typeName = "Destination unreachable (code \(code))" }
                else if type == 11 { typeName = "Time-to-live exceeded (code \(code))" }
            } else {
                if type == 128 { typeName = "Echo Request" }
                else if type == 129 { typeName = "Echo Reply" }
                else if type == 1 { typeName = "Destination Unreachable" }
                else if type == 3 { typeName = "Time Exceeded" }
            }

            let icmpFields = [
                LayerField(name: "Type", value: "\(type) (\(typeName))", hexOffset: offset, hexLength: 1),
                LayerField(name: "Code", value: "\(code)", hexOffset: offset + 1, hexLength: 1),
                LayerField(name: "Checksum", value: String(format: "0x%04X", chk), hexOffset: offset + 2, hexLength: 2)
            ]
            let layerName = (protocolNum == 1) ? "Internet Control Message Protocol" : "Internet Control Message Protocol v6"
            updatedLayers.append(DissectedLayer(name: layerName, summary: typeName, fields: icmpFields))

            return DissectionResult(
                protocolType: (protocolNum == 1) ? .icmp : .icmpv6,
                sourceAddress: srcIP,
                destinationAddress: dstIP,
                summary: "\(typeName)",
                layers: updatedLayers
            )

        default:
            return DissectionResult(
                protocolType: .other("Proto \(protocolNum)"),
                sourceAddress: srcIP,
                destinationAddress: dstIP,
                summary: "IP Protocol: \(protocolNum)",
                layers: updatedLayers
            )
        }
    }

    // MARK: - DNS Dissection
    private static func dissectDNS(payload: Data, baseOffset: Int) -> (summary: String, layer: DissectedLayer)? {
        guard payload.count >= 12 else { return nil }

        let txId = UInt16(payload[0]) << 8 | UInt16(payload[1])
        let flags = UInt16(payload[2]) << 8 | UInt16(payload[3])
        let isResponse = (flags & 0x8000) != 0
        let qdCount = UInt16(payload[4]) << 8 | UInt16(payload[5])
        let anCount = UInt16(payload[6]) << 8 | UInt16(payload[7])
        let rcode = flags & 0x000F

        // Extract first query domain name if possible
        var qName = ""
        var idx = 12
        while idx < payload.count {
            let labelLen = Int(payload[idx])
            if labelLen == 0 { break }
            if (labelLen & 0xC0) != 0 { // pointer
                idx += 1
                break
            }
            idx += 1
            if idx + labelLen <= payload.count,
               let label = String(data: payload.subdata(in: idx..<(idx + labelLen)), encoding: .utf8) {
                if !qName.isEmpty { qName.append(".") }
                qName.append(label)
                idx += labelLen
            } else {
                break
            }
        }

        let qTypeStr = (qName.isEmpty) ? "" : " \(qName)"
        let rcodeStr = (rcode == 0) ? "NoError" : (rcode == 3 ? "NXDomain" : "Error(\(rcode))")
        let summary: String
        if isResponse {
            summary = String(format: "Standard query response 0x%04X%@ (%@, %d answers)", txId, qTypeStr, rcodeStr, anCount)
        } else {
            summary = String(format: "Standard query 0x%04X%@", txId, qTypeStr)
        }

        let dnsFields = [
            LayerField(name: "Transaction ID", value: String(format: "0x%04X", txId), hexOffset: baseOffset, hexLength: 2),
            LayerField(name: "Type", value: isResponse ? "Response" : "Query", hexOffset: baseOffset + 2, hexLength: 2),
            LayerField(name: "Questions", value: "\(qdCount)", hexOffset: baseOffset + 4, hexLength: 2),
            LayerField(name: "Answer RRs", value: "\(anCount)", hexOffset: baseOffset + 6, hexLength: 2),
            LayerField(name: "Query Name", value: qName.isEmpty ? "None" : qName, hexOffset: baseOffset + 12, hexLength: max(1, idx - 12)),
            LayerField(name: "Response Code", value: rcodeStr, hexOffset: baseOffset + 2, hexLength: 2)
        ]
        let layer = DissectedLayer(name: "Domain Name System (\(isResponse ? "response" : "query"))", summary: summary, fields: dnsFields)
        return (summary, layer)
    }

    // MARK: - TLS Dissection
    private static func dissectTLS(payload: Data, baseOffset: Int) -> (summary: String, layer: DissectedLayer)? {
        guard payload.count >= 6 else { return nil }

        let contentType = payload[0]
        let versionMajor = payload[1]
        let versionMinor = payload[2]
        let recLen = Int(UInt16(payload[3]) << 8 | UInt16(payload[4]))

        guard contentType == 0x16 else { return nil } // Handshake

        let handshakeType = payload[5]
        var handshakeName = "Handshake (\(handshakeType))"
        var sni: String? = nil

        if handshakeType == 1 {
            handshakeName = "Client Hello"
            sni = extractSNI(data: payload.dropFirst(5))
        } else if handshakeType == 2 {
            handshakeName = "Server Hello"
        }

        let summary = "TLSv\(versionMajor).\(versionMinor) \(handshakeName)\(sni.map { " (SNI: \($0))" } ?? "")"

        var tlsFields = [
            LayerField(name: "Content Type", value: "Handshake (22)", hexOffset: baseOffset, hexLength: 1),
            LayerField(name: "Version", value: "TLS \(versionMajor).\(versionMinor)", hexOffset: baseOffset + 1, hexLength: 2),
            LayerField(name: "Record Length", value: "\(recLen) bytes", hexOffset: baseOffset + 3, hexLength: 2),
            LayerField(name: "Handshake Type", value: handshakeName, hexOffset: baseOffset + 5, hexLength: 1)
        ]
        if let serverName = sni {
            tlsFields.append(LayerField(name: "Server Name Indication (SNI)", value: serverName, hexOffset: baseOffset + 5, hexLength: payload.count - 5))
        }

        let layer = DissectedLayer(name: "Transport Layer Security", summary: summary, fields: tlsFields)
        return (summary, layer)
    }

    private static func extractSNI(data: Data) -> String? {
        guard data.count > 43 else { return nil }
        var pos = 38
        guard pos < data.count else { return nil }
        let sessionIDLen = Int(data[pos])
        pos += 1 + sessionIDLen
        guard pos + 2 <= data.count else { return nil }
        let cipherSuiteLen = Int(UInt16(data[pos]) << 8 | UInt16(data[pos + 1]))
        pos += 2 + cipherSuiteLen
        guard pos + 1 <= data.count else { return nil }
        let compMethodsLen = Int(data[pos])
        pos += 1 + compMethodsLen
        guard pos + 2 <= data.count else { return nil }
        let extensionsLen = Int(UInt16(data[pos]) << 8 | UInt16(data[pos + 1]))
        pos += 2

        let end = min(data.count, pos + extensionsLen)
        while pos + 4 <= end {
            let extType = UInt16(data[pos]) << 8 | UInt16(data[pos + 1])
            let extLen = Int(UInt16(data[pos + 2]) << 8 | UInt16(data[pos + 3]))
            pos += 4
            if extType == 0x0000 && pos + extLen <= end {
                if extLen > 5 && data[pos + 2] == 0 {
                    let nameLen = Int(UInt16(data[pos + 3]) << 8 | UInt16(data[pos + 4]))
                    if pos + 5 + nameLen <= end {
                        let nameData = data.subdata(in: (pos + 5)..<(pos + 5 + nameLen))
                        return String(data: nameData, encoding: .utf8)
                    }
                }
            }
            pos += extLen
        }
        return nil
    }

    // MARK: - DHCP / BOOTP Dissection (RFC 2131)
    public static func dissectDHCP(payload: Data, baseOffset: Int) -> (summary: String, layer: DissectedLayer)? {
        guard payload.count >= 240 else { return nil }

        let op = payload[0]
        let hType = payload[1]
        let hLen = payload[2]
        let hops = payload[3]
        let xid = UInt32(payload[4]) << 24 | UInt32(payload[5]) << 16 | UInt32(payload[6]) << 8 | UInt32(payload[7])
        let secs = UInt16(payload[8]) << 8 | UInt16(payload[9])
        let flags = UInt16(payload[10]) << 8 | UInt16(payload[11])

        let ciaddr = formatIPv4(data: payload.subdata(in: 12..<16))
        let yiaddr = formatIPv4(data: payload.subdata(in: 16..<20))
        let siaddr = formatIPv4(data: payload.subdata(in: 20..<24))
        let giaddr = formatIPv4(data: payload.subdata(in: 24..<28))
        let chaddr = formatMAC(data: payload.subdata(in: 28..<min(payload.count, 28 + Int(hLen))))

        // Check DHCP Magic Cookie 0x63 0x82 0x53 0x63
        let hasMagicCookie = payload[236] == 0x63 && payload[237] == 0x82 && payload[238] == 0x53 && payload[239] == 0x63

        var msgTypeName = (op == 1) ? "BootRequest" : "BootReply"
        var hostname: String? = nil

        var optFields: [LayerField] = []

        if hasMagicCookie && payload.count > 240 {
            var optIdx = 240
            while optIdx < payload.count {
                let code = payload[optIdx]
                if code == 255 { break } // End Option
                if code == 0 { // Pad
                    optIdx += 1
                    continue
                }
                guard optIdx + 1 < payload.count else { break }
                let len = Int(payload[optIdx + 1])
                optIdx += 2
                guard optIdx + len <= payload.count else { break }

                let optData = payload.subdata(in: optIdx..<(optIdx + len))
                let optHexOffset = baseOffset + optIdx - 2
                let optHexLen = len + 2

                switch code {
                case 53: // DHCP Message Type
                    if len >= 1 {
                        let typeVal = optData[0]
                        switch typeVal {
                        case 1: msgTypeName = "DHCP Discover"
                        case 2: msgTypeName = "DHCP Offer"
                        case 3: msgTypeName = "DHCP Request"
                        case 4: msgTypeName = "DHCP Decline"
                        case 5: msgTypeName = "DHCP ACK"
                        case 6: msgTypeName = "DHCP NAK"
                        case 7: msgTypeName = "DHCP Release"
                        case 8: msgTypeName = "DHCP Inform"
                        default: msgTypeName = "DHCP Type \(typeVal)"
                        }
                        optFields.append(LayerField(name: "Option (53) DHCP Message Type", value: msgTypeName, hexOffset: optHexOffset, hexLength: optHexLen))
                    }
                case 54: // Server Identifier
                    if len == 4 {
                        let sId = formatIPv4(data: optData)
                        optFields.append(LayerField(name: "Option (54) Server Identifier", value: sId, hexOffset: optHexOffset, hexLength: optHexLen))
                    }
                case 51: // Lease Time
                    if len == 4 {
                        let lTime = UInt32(optData[0]) << 24 | UInt32(optData[1]) << 16 | UInt32(optData[2]) << 8 | UInt32(optData[3])
                        optFields.append(LayerField(name: "Option (51) IP Address Lease Time", value: "\(lTime)s", hexOffset: optHexOffset, hexLength: optHexLen))
                    }
                case 1: // Subnet Mask
                    if len == 4 {
                        let sMask = formatIPv4(data: optData)
                        optFields.append(LayerField(name: "Option (1) Subnet Mask", value: sMask, hexOffset: optHexOffset, hexLength: optHexLen))
                    }
                case 3: // Router
                    if len >= 4 {
                        let rtr = formatIPv4(data: optData.prefix(4))
                        optFields.append(LayerField(name: "Option (3) Router", value: rtr, hexOffset: optHexOffset, hexLength: optHexLen))
                    }
                case 6: // Domain Name Server
                    var dnsList: [String] = []
                    for d in stride(from: 0, to: len, by: 4) {
                        if d + 4 <= len {
                            dnsList.append(formatIPv4(data: optData.subdata(in: d..<(d + 4))))
                        }
                    }
                    optFields.append(LayerField(name: "Option (6) DNS Servers", value: dnsList.joined(separator: ", "), hexOffset: optHexOffset, hexLength: optHexLen))
                case 12: // Host Name
                    if let hn = String(data: optData, encoding: .utf8) {
                        hostname = hn
                        optFields.append(LayerField(name: "Option (12) Host Name", value: hn, hexOffset: optHexOffset, hexLength: optHexLen))
                    }
                default:
                    optFields.append(LayerField(name: "Option (\(code))", value: "\(len) bytes", hexOffset: optHexOffset, hexLength: optHexLen))
                }
                optIdx += len
            }
        }

        var dhcpFields = [
            LayerField(name: "Message Type (Opcode)", value: "\(op == 1 ? "BootRequest (1)" : "BootReply (2)")", hexOffset: baseOffset, hexLength: 1),
            LayerField(name: "Hardware Type", value: String(format: "0x%02X (%d)", hType, hType), hexOffset: baseOffset + 1, hexLength: 1),
            LayerField(name: "Hardware Address Length", value: "\(hLen)", hexOffset: baseOffset + 2, hexLength: 1),
            LayerField(name: "Hops", value: "\(hops)", hexOffset: baseOffset + 3, hexLength: 1),
            LayerField(name: "Transaction ID (XID)", value: String(format: "0x%08X", xid), hexOffset: baseOffset + 4, hexLength: 4),
            LayerField(name: "Seconds Elapsed", value: "\(secs)", hexOffset: baseOffset + 8, hexLength: 2),
            LayerField(name: "Bootp Flags", value: String(format: "0x%04X", flags), hexOffset: baseOffset + 10, hexLength: 2),
            LayerField(name: "Client IP Address (ciaddr)", value: ciaddr, hexOffset: baseOffset + 12, hexLength: 4),
            LayerField(name: "Your (Client) IP Address (yiaddr)", value: yiaddr, hexOffset: baseOffset + 16, hexLength: 4),
            LayerField(name: "Next Server IP (siaddr)", value: siaddr, hexOffset: baseOffset + 20, hexLength: 4),
            LayerField(name: "Relay Agent IP (giaddr)", value: giaddr, hexOffset: baseOffset + 24, hexLength: 4),
            LayerField(name: "Client MAC Address (chaddr)", value: chaddr, hexOffset: baseOffset + 28, hexLength: 16),
            LayerField(name: "Magic Cookie", value: hasMagicCookie ? "DHCP (0x63825363)" : "None", hexOffset: baseOffset + 236, hexLength: 4)
        ]
        dhcpFields.append(contentsOf: optFields)

        var summary = "\(msgTypeName) - Transaction ID 0x\(String(format: "%08X", xid))"
        if yiaddr != "0.0.0.0" {
            summary.append(" Assigned: \(yiaddr)")
        } else if let hn = hostname {
            summary.append(" Host: \(hn)")
        }

        let layer = DissectedLayer(name: "Dynamic Host Configuration Protocol (\(msgTypeName))", summary: summary, fields: dhcpFields)
        return (summary, layer)
    }

    // MARK: - BGP Dissection (RFC 4271 - Port 179)
    public static func dissectBGP(payload: Data, baseOffset: Int) -> (summary: String, layer: DissectedLayer)? {
        guard payload.count >= 19 else { return nil }

        let bgpLen = Int(UInt16(payload[16]) << 8 | UInt16(payload[17]))
        let bgpType = payload[18]

        var typeName = "Unknown (\(bgpType))"
        switch bgpType {
        case 1: typeName = "OPEN"
        case 2: typeName = "UPDATE"
        case 3: typeName = "NOTIFICATION"
        case 4: typeName = "KEEPALIVE"
        case 5: typeName = "ROUTE-REFRESH"
        default: break
        }

        var bgpFields = [
            LayerField(name: "Marker", value: "16 bytes (Sync)", hexOffset: baseOffset, hexLength: 16),
            LayerField(name: "Length", value: "\(bgpLen) bytes", hexOffset: baseOffset + 16, hexLength: 2),
            LayerField(name: "Type", value: "\(typeName) (\(bgpType))", hexOffset: baseOffset + 18, hexLength: 1)
        ]

        var summary = "BGP \(typeName)"

        if bgpType == 1 && payload.count >= 29 { // OPEN
            let version = payload[19]
            let asNum = UInt16(payload[20]) << 8 | UInt16(payload[21])
            let holdTime = UInt16(payload[22]) << 8 | UInt16(payload[23])
            let bgpId = formatIPv4(data: payload.subdata(in: 24..<28))
            let optLen = payload[28]

            bgpFields.append(contentsOf: [
                LayerField(name: "Version", value: "\(version)", hexOffset: baseOffset + 19, hexLength: 1),
                LayerField(name: "My AS", value: "\(asNum)", hexOffset: baseOffset + 20, hexLength: 2),
                LayerField(name: "Hold Time", value: "\(holdTime)s", hexOffset: baseOffset + 22, hexLength: 2),
                LayerField(name: "BGP Identifier", value: bgpId, hexOffset: baseOffset + 24, hexLength: 4),
                LayerField(name: "Optional Parameter Length", value: "\(optLen) bytes", hexOffset: baseOffset + 28, hexLength: 1)
            ])
            summary = "BGP OPEN (AS \(asNum), BGP-ID: \(bgpId), HoldTime: \(holdTime)s)"
        } else if bgpType == 4 { // KEEPALIVE
            summary = "BGP KEEPALIVE Message"
        } else if bgpType == 3 && payload.count >= 21 { // NOTIFICATION
            let errCode = payload[19]
            let errSubcode = payload[20]
            bgpFields.append(contentsOf: [
                LayerField(name: "Error Code", value: "\(errCode)", hexOffset: baseOffset + 19, hexLength: 1),
                LayerField(name: "Error Subcode", value: "\(errSubcode)", hexOffset: baseOffset + 20, hexLength: 1)
            ])
            summary = "BGP NOTIFICATION (Error: \(errCode)/\(errSubcode))"
        }

        let layer = DissectedLayer(name: "Border Gateway Protocol (\(typeName))", summary: summary, fields: bgpFields)
        return (summary, layer)
    }

    // MARK: - OSPF Dissection (RFC 2328 - Protocol 89)
    public static func dissectOSPF(data: Data, offset: Int, srcIP: String, dstIP: String, layers: [DissectedLayer]) -> DissectionResult {
        var updatedLayers = layers
        guard data.count >= offset + 24 else {
            return DissectionResult(
                protocolType: .ospf,
                sourceAddress: srcIP,
                destinationAddress: dstIP,
                summary: "Truncated OSPF Header",
                layers: updatedLayers
            )
        }

        let version = data[offset]
        let ospfType = data[offset + 1]
        let packetLen = Int(UInt16(data[offset + 2]) << 8 | UInt16(data[offset + 3]))
        let routerId = formatIPv4(data: data.subdata(in: (offset + 4)..<(offset + 8)))
        let areaId = formatIPv4(data: data.subdata(in: (offset + 8)..<(offset + 12)))
        let chk = UInt16(data[offset + 12]) << 8 | UInt16(data[offset + 13])
        let auType = UInt16(data[offset + 14]) << 8 | UInt16(data[offset + 15])

        var typeName = "Type \(ospfType)"
        switch ospfType {
        case 1: typeName = "Hello Packet"
        case 2: typeName = "Database Description"
        case 3: typeName = "Link State Request"
        case 4: typeName = "Link State Update"
        case 5: typeName = "Link State Acknowledgment"
        default: break
        }

        var ospfFields = [
            LayerField(name: "Version", value: "\(version)", hexOffset: offset, hexLength: 1),
            LayerField(name: "Type", value: "\(typeName) (\(ospfType))", hexOffset: offset + 1, hexLength: 1),
            LayerField(name: "Packet Length", value: "\(packetLen) bytes", hexOffset: offset + 2, hexLength: 2),
            LayerField(name: "Router ID", value: routerId, hexOffset: offset + 4, hexLength: 4),
            LayerField(name: "Area ID", value: areaId, hexOffset: offset + 8, hexLength: 4),
            LayerField(name: "Checksum", value: String(format: "0x%04X", chk), hexOffset: offset + 12, hexLength: 2),
            LayerField(name: "Auth Type", value: String(format: "0x%04X", auType), hexOffset: offset + 14, hexLength: 2)
        ]

        if ospfType == 1 && data.count >= offset + 44 { // OSPF Hello
            let mask = formatIPv4(data: data.subdata(in: (offset + 24)..<(offset + 28)))
            let helloInt = UInt16(data[offset + 28]) << 8 | UInt16(data[offset + 29])
            let deadInt = UInt32(data[offset + 32]) << 24 | UInt32(data[offset + 33]) << 16 | UInt32(data[offset + 34]) << 8 | UInt32(data[offset + 35])
            let dr = formatIPv4(data: data.subdata(in: (offset + 36)..<(offset + 40)))
            let bdr = formatIPv4(data: data.subdata(in: (offset + 40)..<(offset + 44)))

            ospfFields.append(contentsOf: [
                LayerField(name: "Network Mask", value: mask, hexOffset: offset + 24, hexLength: 4),
                LayerField(name: "Hello Interval", value: "\(helloInt)s", hexOffset: offset + 28, hexLength: 2),
                LayerField(name: "Dead Interval", value: "\(deadInt)s", hexOffset: offset + 32, hexLength: 4),
                LayerField(name: "Designated Router (DR)", value: dr, hexOffset: offset + 36, hexLength: 4),
                LayerField(name: "Backup DR (BDR)", value: bdr, hexOffset: offset + 40, hexLength: 4)
            ])
        }

        let summary = "OSPFv\(version) \(typeName) (Router ID: \(routerId), Area: \(areaId))"
        updatedLayers.append(DissectedLayer(name: "Open Shortest Path First (\(typeName))", summary: summary, fields: ospfFields))

        return DissectionResult(
            protocolType: .ospf,
            sourceAddress: srcIP,
            destinationAddress: dstIP,
            summary: summary,
            payloadLength: max(0, data.count - offset),
            layers: updatedLayers
        )
    }

    // MARK: - NTP Dissection (RFC 5905 - Port 123)
    public static func dissectNTP(payload: Data, baseOffset: Int) -> (summary: String, layer: DissectedLayer)? {
        guard payload.count >= 48 else { return nil }

        let b0 = payload[0]
        let li = (b0 >> 6) & 0x03
        let vn = (b0 >> 3) & 0x07
        let mode = b0 & 0x07
        let stratum = payload[1]
        let poll = payload[2]
        let precision = Int8(bitPattern: payload[3])

        var modeStr = "Mode \(mode)"
        switch mode {
        case 1: modeStr = "Symmetric Active"
        case 2: modeStr = "Symmetric Passive"
        case 3: modeStr = "Client"
        case 4: modeStr = "Server"
        case 5: modeStr = "Broadcast"
        case 6: modeStr = "NTP Control"
        default: break
        }

        var liStr = "No Warning (0)"
        if li == 1 { liStr = "61s Leap" }
        else if li == 2 { liStr = "59s Leap" }
        else if li == 3 { liStr = "Alarm (Not Synchronized)" }

        // Reference Identifier
        let refIdData = payload.subdata(in: 12..<16)
        let refIdStr: String
        if stratum <= 1 {
            refIdStr = String(data: refIdData, encoding: .ascii) ?? formatIPv4(data: refIdData)
        } else {
            refIdStr = formatIPv4(data: refIdData)
        }

        let ntpFields = [
            LayerField(name: "Leap Indicator", value: liStr, hexOffset: baseOffset, hexLength: 1),
            LayerField(name: "Version Number", value: "NTPv\(vn)", hexOffset: baseOffset, hexLength: 1),
            LayerField(name: "Mode", value: "\(modeStr) (\(mode))", hexOffset: baseOffset, hexLength: 1),
            LayerField(name: "Stratum", value: "\(stratum) (\(stratum == 1 ? "Primary Reference" : "Secondary"))", hexOffset: baseOffset + 1, hexLength: 1),
            LayerField(name: "Poll Interval", value: "\(poll) (\(Int(pow(2.0, Double(poll))))s)", hexOffset: baseOffset + 2, hexLength: 1),
            LayerField(name: "Precision", value: "\(precision) (\(pow(2.0, Double(precision)))s)", hexOffset: baseOffset + 3, hexLength: 1),
            LayerField(name: "Reference ID", value: refIdStr, hexOffset: baseOffset + 12, hexLength: 4)
        ]

        let summary = "NTPv\(vn) \(modeStr) (Stratum \(stratum), Ref: \(refIdStr.trimmingCharacters(in: .whitespacesAndNewlines)))"
        let layer = DissectedLayer(name: "Network Time Protocol (\(modeStr))", summary: summary, fields: ntpFields)
        return (summary, layer)
    }

    // MARK: - SNMP Dissection (RFC 1157 / RFC 3416 - Ports 161, 162)
    public static func dissectSNMP(payload: Data, baseOffset: Int) -> (summary: String, layer: DissectedLayer)? {
        // ASN.1 BER Sequence Check: 0x30 <len>
        guard payload.count >= 6, payload[0] == 0x30 else { return nil }

        var pos = 2
        // Version INTEGER: 0x02 0x01 <val>
        guard pos + 3 <= payload.count, payload[pos] == 0x02, payload[pos + 1] == 1 else { return nil }
        let verNum = payload[pos + 2]
        var verStr = "SNMPv\(verNum + 1)"
        if verNum == 1 { verStr = "SNMPv2c" }
        pos += 3

        // Community String OCTET STRING: 0x04 <len> <string>
        var community = "public"
        let commOffset = baseOffset + pos
        var commLen = 0
        if pos + 2 <= payload.count && payload[pos] == 0x04 {
            let clen = Int(payload[pos + 1])
            commLen = clen + 2
            pos += 2
            if pos + clen <= payload.count {
                if let str = String(data: payload.subdata(in: pos..<(pos + clen)), encoding: .utf8) {
                    community = str
                }
                pos += clen
            }
        }

        // PDU Tag
        var pduName = "PDU"
        if pos < payload.count {
            let pduTag = payload[pos]
            switch pduTag {
            case 0xA0: pduName = "GetRequest"
            case 0xA1: pduName = "GetNextRequest"
            case 0xA2: pduName = "GetResponse"
            case 0xA3: pduName = "SetRequest"
            case 0xA4: pduName = "Trap-v1"
            case 0xA5: pduName = "GetBulkRequest"
            case 0xA7: pduName = "Trap-v2"
            default: pduName = String(format: "PDU (0x%02X)", pduTag)
            }
        }

        let snmpFields = [
            LayerField(name: "Version", value: verStr, hexOffset: baseOffset + 2, hexLength: 3),
            LayerField(name: "Community String", value: community, hexOffset: commOffset, hexLength: commLen),
            LayerField(name: "PDU Type", value: pduName, hexOffset: baseOffset + pos, hexLength: 1)
        ]

        let summary = "\(verStr) \(pduName) (Community: \(community))"
        let layer = DissectedLayer(name: "Simple Network Management Protocol (\(pduName))", summary: summary, fields: snmpFields)
        return (summary, layer)
    }

    // MARK: - Formatters
    public static func formatMAC(data: Data) -> String {
        return data.map { String(format: "%02x", $0) }.joined(separator: ":")
    }

    public static func formatIPv4(data: Data) -> String {
        return data.map { "\($0)" }.joined(separator: ".")
    }

    public static func formatIPv6(data: Data) -> String {
        var groups: [String] = []
        for i in stride(from: 0, to: data.count, by: 2) {
            if i + 1 < data.count {
                let val = UInt16(data[i]) << 8 | UInt16(data[i + 1])
                groups.append(String(format: "%x", val))
            }
        }
        return groups.joined(separator: ":")
    }
}
