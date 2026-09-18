import Foundation

public struct TCPStreamReassembler: Sendable {
    public init() {}

    public static func reassembleStream(for selectedPacket: PacketRecord, from allPackets: [PacketRecord]) -> TCPStreamReassemblyResult? {
        guard selectedPacket.protocolType == .tcp || selectedPacket.protocolType == .http || selectedPacket.protocolType == .tls,
              let srcPort = selectedPacket.sourcePort,
              let dstPort = selectedPacket.destinationPort else {
            return nil
        }

        let epA = "\(selectedPacket.sourceAddress):\(srcPort)"
        let epB = "\(selectedPacket.destinationAddress):\(dstPort)"

        // Filter all packets in this bidirectional TCP stream
        let streamPackets = allPackets.filter { p in
            guard let sp = p.sourcePort, let dp = p.destinationPort else { return false }
            let pEpSrc = "\(p.sourceAddress):\(sp)"
            let pEpDst = "\(p.destinationAddress):\(dp)"
            return (pEpSrc == epA && pEpDst == epB) || (pEpSrc == epB && pEpDst == epA)
        }.sorted { $0.number < $1.number }

        guard !streamPackets.isEmpty else { return nil }

        // Determine Client vs Server (Client is the initiator of SYN, or whichever spoke first)
        var clientEp = epA
        var serverEp = epB

        if let synPkt = streamPackets.first(where: { ($0.tcpFlags?.contains(.syn) == true) && ($0.tcpFlags?.contains(.ack) == false) }),
           let sp = synPkt.sourcePort {
            clientEp = "\(synPkt.sourceAddress):\(sp)"
            if let dp = synPkt.destinationPort {
                serverEp = "\(synPkt.destinationAddress):\(dp)"
            }
        } else if let first = streamPackets.first, let sp = first.sourcePort, let dp = first.destinationPort {
            clientEp = "\(first.sourceAddress):\(sp)"
            serverEp = "\(first.destinationAddress):\(dp)"
        }

        var segments: [TCPStreamSegment] = []
        var clientBytes = 0
        var serverBytes = 0
        var combinedAscii = ""

        for pkt in streamPackets {
            let sp = pkt.sourcePort ?? 0
            let curSrc = "\(pkt.sourceAddress):\(sp)"
            let isClient = (curSrc == clientEp)
            let dir: TCPStreamDirection = isClient ? .clientToServer : .serverToClient

            // Extract TCP payload bytes
            let payload = extractTCPPayload(from: pkt)
            if payload.isEmpty { continue }

            if isClient {
                clientBytes += payload.count
            } else {
                serverBytes += payload.count
            }

            let ascii = toAsciiString(payload)
            let hex = toHexString(payload)

            segments.append(TCPStreamSegment(
                direction: dir,
                packetNumber: pkt.number,
                seq: pkt.tcpSeq ?? 0,
                payload: payload,
                asciiText: ascii,
                hexDump: hex,
                timestamp: pkt.timestamp
            ))

            let prefix = isClient ? "[CLIENT ➔ SERVER - Packet #\(pkt.number)]\n" : "[SERVER ➔ CLIENT - Packet #\(pkt.number)]\n"
            combinedAscii.append(prefix + ascii + "\n\n")
        }

        return TCPStreamReassemblyResult(
            streamId: "\(clientEp) ⟷ \(serverEp)",
            clientEndpoint: clientEp,
            serverEndpoint: serverEp,
            clientBytes: clientBytes,
            serverBytes: serverBytes,
            totalBytes: clientBytes + serverBytes,
            segments: segments,
            combinedAscii: combinedAscii.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func extractTCPPayload(from packet: PacketRecord) -> Data {
        let raw = packet.rawBytes
        guard raw.count >= 34 else { return Data() } // Min Eth(14) + IP(20)

        var offset = 14
        let etherType = UInt16(raw[12]) << 8 | UInt16(raw[13])
        if etherType == 0x8100 && raw.count >= 18 { // 802.1Q
            offset = 18
        }

        guard raw.count >= offset + 20 else { return Data() }
        let ipVer = raw[offset] >> 4
        var ipHdrLen = 20
        var proto: UInt8 = 6

        if ipVer == 4 {
            ipHdrLen = Int(raw[offset] & 0x0F) * 4
            proto = raw[offset + 9]
        } else if ipVer == 6 {
            ipHdrLen = 40
            proto = raw[offset + 6]
        }

        guard proto == 6 else { return Data() } // TCP only
        let tcpOffset = offset + ipHdrLen
        guard raw.count >= tcpOffset + 20 else { return Data() }

        let tcpDataOffset = Int(raw[tcpOffset + 12] >> 4) * 4
        let payloadStart = tcpOffset + tcpDataOffset
        guard raw.count >= payloadStart else { return Data() }

        return raw.subdata(in: payloadStart..<raw.count)
    }

    private static func toAsciiString(_ data: Data) -> String {
        var str = ""
        for b in data {
            if b == 0x0D || b == 0x0A || b == 0x09 {
                str.append(Character(UnicodeScalar(b)))
            } else if b >= 32 && b <= 126 {
                str.append(Character(UnicodeScalar(b)))
            } else {
                str.append(".")
            }
        }
        return str
    }

    private static func toHexString(_ data: Data) -> String {
        return data.map { String(format: "%02x", $0) }.joined(separator: " ")
    }
}
