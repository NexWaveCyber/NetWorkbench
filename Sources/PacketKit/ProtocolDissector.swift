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
            LayerField(name: "Frame Number", value: "\(packetNumber)"),
            LayerField(name: "Frame Length on Wire", value: "\(wireLength) bytes"),
            LayerField(name: "Captured Length", value: "\(packetData.count) bytes")
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
            ethFields.append(LayerField(name: "802.1Q VLAN ID", value: "\(vlan)"))
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
            if dstMAC == "01:00:0C:CC:CC:CC" || (packetData.count > offset + 8 && packetData[offset] == 0xAA && packetData[offset + 1] == 0xAA) {
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

        let opcode = UInt16(data[offset + 6]) << 8 | UInt16(data[offset + 7])
        let senderMAC = formatMAC(data: data.subdata(in: (offset + 8)..<(offset + 14)))
        let senderIP = formatIPv4(data: data.subdata(in: (offset + 14)..<(offset + 18)))
        let targetMAC = formatMAC(data: data.subdata(in: (offset + 18)..<(offset + 24)))
        let targetIP = formatIPv4(data: data.subdata(in: (offset + 24)..<(offset + 28)))

        let opString = (opcode == 1) ? "Request" : (opcode == 2 ? "Reply" : "Unknown (\(opcode))")
        let summary = (opcode == 1) ? "Who has \(targetIP)? Tell \(senderIP)" : "\(senderIP) is at \(senderMAC)"

        let arpFields = [
            LayerField(name: "Opcode", value: opString),
            LayerField(name: "Sender MAC", value: senderMAC),
            LayerField(name: "Sender IP", value: senderIP),
            LayerField(name: "Target MAC", value: targetMAC),
            LayerField(name: "Target IP", value: targetIP)
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
        let srcIP = formatIPv4(data: data.subdata(in: (offset + 12)..<(offset + 16)))
        let dstIP = formatIPv4(data: data.subdata(in: (offset + 16)..<(offset + 20)))

        let ipFields = [
            LayerField(name: "Version", value: "\(version)"),
            LayerField(name: "Header Length", value: "\(ihl) bytes"),
            LayerField(name: "Total Length", value: "\(totalLen) bytes"),
            LayerField(name: "Identification", value: String(format: "0x%04X (%d)", ident, ident)),
            LayerField(name: "Time to Live (TTL)", value: "\(ttl)"),
            LayerField(name: "Protocol", value: "\(protocolNum)"),
            LayerField(name: "Source IP", value: srcIP),
            LayerField(name: "Destination IP", value: dstIP)
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
            LayerField(name: "Next Header", value: "\(nextHeader)"),
            LayerField(name: "Payload Length", value: "\(payloadLen) bytes"),
            LayerField(name: "Hop Limit", value: "\(hopLimit)"),
            LayerField(name: "Source IPv6", value: srcIP),
            LayerField(name: "Destination IPv6", value: dstIP)
        ]
        updatedLayers.append(DissectedLayer(name: "Internet Protocol Version 6", summary: "Src: \(srcIP), Dst: \(dstIP)", fields: ipFields))

        let transportOffset = offset + 40
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

            let payloadOffset = offset + dataOffset
            let actualPayloadLen = max(0, min(data.count - payloadOffset, ipTotalLen - ipHeaderLen - dataOffset))

            let tcpFields = [
                LayerField(name: "Source Port", value: "\(srcPort)"),
                LayerField(name: "Destination Port", value: "\(dstPort)"),
                LayerField(name: "Sequence Number (raw)", value: "\(seq)"),
                LayerField(name: "Acknowledgment Number (raw)", value: "\(ack)"),
                LayerField(name: "Header Length", value: "\(dataOffset) bytes"),
                LayerField(name: "Flags", value: "\(tcpFlags.flagSummary) (0x\(String(format: "%02X", rawFlags)))"),
                LayerField(name: "Window Size", value: "\(win)"),
                LayerField(name: "Payload Length", value: "\(actualPayloadLen) bytes")
            ]
            updatedLayers.append(DissectedLayer(name: "Transmission Control Protocol", summary: "\(srcPort) → \(dstPort) \(tcpFlags.flagSummary)", fields: tcpFields))

            // Check for Application Protocols
            var appProto: PacketProtocol = .tcp
            var summaryDetail: String? = nil

            if payloadOffset < data.count && actualPayloadLen > 0 {
                let payload = data.subdata(in: payloadOffset..<min(data.count, payloadOffset + actualPayloadLen))

                // TLS check
                if (srcPort == 443 || dstPort == 443 || srcPort == 8443 || dstPort == 8443) && payload.count >= 5 && payload[0] == 0x16 {
                    appProto = .tls
                    if let tlsInfo = dissectTLS(payload: payload) {
                        summaryDetail = tlsInfo.summary
                        updatedLayers.append(tlsInfo.layer)
                    }
                }
                // HTTP check
                else if (srcPort == 80 || dstPort == 80 || srcPort == 8080 || dstPort == 8080) {
                    if let httpStr = String(data: payload.prefix(64), encoding: .utf8)?.components(separatedBy: "\r\n").first,
                       (httpStr.hasPrefix("GET ") || httpStr.hasPrefix("POST ") || httpStr.hasPrefix("HTTP/") || httpStr.hasPrefix("PUT ") || httpStr.hasPrefix("HEAD ")) {
                        appProto = .http
                        summaryDetail = httpStr
                        let httpFields = [LayerField(name: "First Line", value: httpStr)]
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

            let udpFields = [
                LayerField(name: "Source Port", value: "\(srcPort)"),
                LayerField(name: "Destination Port", value: "\(dstPort)"),
                LayerField(name: "Length", value: "\(udpLen) bytes")
            ]
            updatedLayers.append(DissectedLayer(name: "User Datagram Protocol", summary: "\(srcPort) → \(dstPort) Len=\(udpLen - 8)", fields: udpFields))

            let payloadOffset = offset + 8
            var appProto: PacketProtocol = .udp
            var summary = "\(srcPort) → \(dstPort) Len=\(max(0, udpLen - 8))"

            // DNS check (port 53 or 853)
            if (srcPort == 53 || dstPort == 53 || srcPort == 853 || dstPort == 853) && data.count >= payloadOffset + 12 {
                let dnsPayload = data.subdata(in: payloadOffset..<min(data.count, payloadOffset + (udpLen - 8)))
                if let dnsResult = dissectDNS(payload: dnsPayload) {
                    appProto = .dns
                    summary = dnsResult.summary
                    updatedLayers.append(dnsResult.layer)
                }
            }

            return DissectionResult(
                protocolType: appProto,
                sourceAddress: srcIP,
                destinationAddress: dstIP,
                sourcePort: srcPort,
                destinationPort: dstPort,
                summary: summary,
                payloadLength: max(0, udpLen - 8),
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

            var typeName = "Type \(type), Code \(code)"
            if protocolNum == 1 {
                if type == 8 { typeName = "Echo (ping) request" }
                else if type == 0 { typeName = "Echo (ping) reply" }
                else if type == 3 { typeName = "Destination unreachable (code \(code))" }
                else if type == 11 { typeName = "Time-to-live exceeded (code \(code))" }
            } else {
                if type == 128 { typeName = "Echo Request" }
                else if type == 129 { typeName = "Echo Reply" }
            }

            let icmpFields = [
                LayerField(name: "Type", value: "\(type) (\(typeName))"),
                LayerField(name: "Code", value: "\(code)")
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
    private static func dissectDNS(payload: Data) -> (summary: String, layer: DissectedLayer)? {
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
            LayerField(name: "Transaction ID", value: String(format: "0x%04X", txId)),
            LayerField(name: "Type", value: isResponse ? "Response" : "Query"),
            LayerField(name: "Questions", value: "\(qdCount)"),
            LayerField(name: "Answer RRs", value: "\(anCount)"),
            LayerField(name: "Query Name", value: qName.isEmpty ? "None" : qName),
            LayerField(name: "Response Code", value: rcodeStr)
        ]
        let layer = DissectedLayer(name: "Domain Name System (\(isResponse ? "response" : "query"))", summary: summary, fields: dnsFields)
        return (summary, layer)
    }

    // MARK: - TLS Dissection
    private static func dissectTLS(payload: Data) -> (summary: String, layer: DissectedLayer)? {
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
            LayerField(name: "Content Type", value: "Handshake (22)"),
            LayerField(name: "Version", value: "TLS \(versionMajor).\(versionMinor)"),
            LayerField(name: "Record Length", value: "\(recLen) bytes"),
            LayerField(name: "Handshake Type", value: handshakeName)
        ]
        if let serverName = sni {
            tlsFields.append(LayerField(name: "Server Name Indication (SNI)", value: serverName))
        }

        let layer = DissectedLayer(name: "Transport Layer Security", summary: summary, fields: tlsFields)
        return (summary, layer)
    }

    private static func extractSNI(data: Data) -> String? {
        // Simple search for extension 0x0000 in ClientHello payload
        // ClientHello: Handshake Type (1B), Length (3B), Version (2B), Random (32B), Session ID len (1B)...
        guard data.count > 43 else { return nil }
        var pos = 38 // skip type (1), len (3), version (2), random (32)
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
            if extType == 0x0000 && pos + extLen <= end { // Server Name
                // Server Name list: list length (2B), name type (1B, 0=host_name), name len (2B), name
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

    // MARK: - Formatters
    private static func formatMAC(data: Data) -> String {
        return data.map { String(format: "%02x", $0) }.joined(separator: ":")
    }

    private static func formatIPv4(data: Data) -> String {
        return data.map { "\($0)" }.joined(separator: ".")
    }

    private static func formatIPv6(data: Data) -> String {
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
