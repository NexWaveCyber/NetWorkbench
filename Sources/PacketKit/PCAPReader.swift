import Foundation

public enum PCAPError: Error, LocalizedError {
    case fileTooSmall
    case invalidMagic(UInt32)
    case unsupportedLinkType(UInt32)
    case corruptPacketHeader(Int)

    public var errorDescription: String? {
        switch self {
        case .fileTooSmall: return "File is too small to be a valid PCAP/PCAPNG capture."
        case .invalidMagic(let magic): return String(format: "Unrecognized PCAP magic number: 0x%08X", magic)
        case .unsupportedLinkType(let link): return "Unsupported data link type: \(link)"
        case .corruptPacketHeader(let offset): return "Corrupt packet header encountered at byte offset \(offset)."
        }
    }
}

public enum PCAPReader {

    public static func parse(data: Data, fileName: String = "capture.pcap") throws -> PacketCaptureSummary {
        guard data.count >= 24 else { throw PCAPError.fileTooSmall }

        // Read magic safely with loadUnaligned
        let rawMagic = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self) }

        var isSwapped = false
        var isNano = false

        switch rawMagic {
        case 0xa1b2c3d4: // standard microsecond, host order
            isSwapped = false
            isNano = false
        case 0xd4c3b2a1: // standard microsecond, swapped order
            isSwapped = true
            isNano = false
        case 0xa1b23c4d: // nanosecond, host order
            isSwapped = false
            isNano = true
        case 0x4d3cb2a1: // nanosecond, swapped order
            isSwapped = true
            isNano = true
        default:
            throw PCAPError.invalidMagic(rawMagic)
        }

        // Global header parsing
        func readUInt32(at offset: Int) -> UInt32 {
            let val = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
            return isSwapped ? val.byteSwapped : val
        }

        _ = readUInt32(at: 20)

        var offset = 24
        var packetNumber = 1
        var records: [PacketRecord] = []
        var anomalyEvents: [AnomalyEvent] = []
        var firstTimestamp: Date? = nil

        let anomalyDetector = TCPAnomalyDetector()
        let flowTracker = FlowTracker()

        while offset + 16 <= data.count {
            let tsSec = readUInt32(at: offset)
            let tsUsec = readUInt32(at: offset + 4)
            let inclLen = Int(readUInt32(at: offset + 8))
            let origLen = Int(readUInt32(at: offset + 12))

            let packetStart = offset + 16
            guard packetStart + inclLen <= data.count else { break }

            let packetBytes = data.subdata(in: packetStart..<(packetStart + inclLen))
            offset += 16 + inclLen

            let timeDivisor = isNano ? 1_000_000_000.0 : 1_000_000.0
            let timestamp = Date(timeIntervalSince1970: TimeInterval(tsSec) + (Double(tsUsec) / timeDivisor))

            if firstTimestamp == nil {
                firstTimestamp = timestamp
            }
            let relativeTime = max(0, timestamp.timeIntervalSince(firstTimestamp ?? timestamp))

            let dissected = ProtocolDissector.dissect(
                packetData: packetBytes,
                packetNumber: packetNumber,
                wireLength: origLen
            )

            // TCP Anomaly check
            var packetAnomalies: [TCPAnomaly] = []
            if let flags = dissected.tcpFlags,
               let seq = dissected.tcpSeq,
               let ack = dissected.tcpAck,
               let win = dissected.tcpWindow,
               let sp = dissected.sourcePort,
               let dp = dissected.destinationPort {
                packetAnomalies = anomalyDetector.analyze(
                    packetNumber: packetNumber,
                    timestamp: timestamp,
                    sourceIP: dissected.sourceAddress,
                    destIP: dissected.destinationAddress,
                    sourcePort: sp,
                    destPort: dp,
                    tcpFlags: flags,
                    seq: seq,
                    ack: ack,
                    window: win,
                    payloadLength: dissected.payloadLength
                )

                for anomaly in packetAnomalies {
                    let evt = AnomalyEvent(
                        packetNumber: packetNumber,
                        relativeTime: relativeTime,
                        source: "\(dissected.sourceAddress):\(sp)",
                        destination: "\(dissected.destinationAddress):\(dp)",
                        anomaly: anomaly,
                        severity: anomaly.severity,
                        description: anomaly.title
                    )
                    anomalyEvents.append(evt)
                }
            }

            let record = PacketRecord(
                number: packetNumber,
                timestamp: timestamp,
                relativeTime: relativeTime,
                sourceAddress: dissected.sourceAddress,
                destinationAddress: dissected.destinationAddress,
                sourcePort: dissected.sourcePort,
                destinationPort: dissected.destinationPort,
                protocolType: dissected.protocolType,
                wireLength: origLen,
                capturedLength: inclLen,
                summary: dissected.summary,
                tcpFlags: dissected.tcpFlags,
                tcpSeq: dissected.tcpSeq,
                tcpAck: dissected.tcpAck,
                tcpWindow: dissected.tcpWindow,
                anomalies: packetAnomalies,
                layers: dissected.layers,
                rawBytes: packetBytes
            )

            records.append(record)
            flowTracker.record(packet: record)
            packetNumber += 1
        }

        let finalEvents = anomalyDetector.finalize()
        anomalyEvents.append(contentsOf: finalEvents)

        let totalPackets = records.count
        let totalBytes = records.reduce(0) { $0 + $1.wireLength }
        let startTime = records.first?.timestamp
        let endTime = records.last?.timestamp
        let duration = max(0.001, (endTime?.timeIntervalSince(startTime ?? Date())) ?? 0.0)
        let avgBitrateMbps = (Double(totalBytes * 8) / duration) / 1_000_000.0

        return PacketCaptureSummary(
            fileName: fileName,
            formatName: "PCAP (Classic)",
            totalPackets: totalPackets,
            totalBytes: totalBytes,
            duration: duration,
            startTime: startTime,
            endTime: endTime,
            averageBitrateMbps: avgBitrateMbps,
            protocolDistribution: flowTracker.buildProtocolDistribution(),
            topTalkers: flowTracker.buildTopTalkers(),
            flows: flowTracker.buildFlows(),
            anomalies: anomalyEvents,
            packets: records
        )
    }
}
