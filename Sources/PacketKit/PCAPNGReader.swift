import Foundation

public enum PCAPNGReader {

    public static func parse(data: Data, fileName: String = "capture.pcapng") throws -> PacketCaptureSummary {
        guard data.count >= 12 else { throw PCAPError.fileTooSmall }

        var isSwapped = false
        var offset = 0
        var packetNumber = 1
        var records: [PacketRecord] = []
        var anomalyEvents: [AnomalyEvent] = []
        var firstTimestamp: Date? = nil

        let anomalyDetector = TCPAnomalyDetector()
        let flowTracker = FlowTracker()

        func readUInt32(at off: Int) -> UInt32 {
            let val = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: off, as: UInt32.self) }
            return isSwapped ? val.byteSwapped : val
        }

        while offset + 12 <= data.count {
            let blockType = readUInt32(at: offset)
            var blockLen = Int(readUInt32(at: offset + 4))

            // Section Header Block (0x0A0D0D0A)
            if blockType == 0x0A0D0D0A {
                guard offset + 16 <= data.count else { break }
                let bom = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset + 8, as: UInt32.self) }
                if bom == 0x1A2B3C4D {
                    isSwapped = false
                } else if bom == 0x4D3C2B1A {
                    isSwapped = true
                }
                // Reload block length with detected endianness
                blockLen = Int(readUInt32(at: offset + 4))
            }

            guard blockLen >= 12, offset + blockLen <= data.count else { break }

            // Enhanced Packet Block (EPB: 0x00000006)
            if blockType == 0x00000006 && blockLen >= 28 {
                let tsHigh = UInt64(readUInt32(at: offset + 12))
                let tsLow = UInt64(readUInt32(at: offset + 16))
                let capLen = Int(readUInt32(at: offset + 20))
                let origLen = Int(readUInt32(at: offset + 24))

                let dataStart = offset + 28
                if dataStart + capLen <= offset + blockLen {
                    let packetBytes = data.subdata(in: dataStart..<(dataStart + capLen))

                    let rawTs = (tsHigh << 32) | tsLow
                    let timestamp = Date(timeIntervalSince1970: Double(rawTs) / 1_000_000.0)

                    if firstTimestamp == nil {
                        firstTimestamp = timestamp
                    }
                    let relativeTime = max(0, timestamp.timeIntervalSince(firstTimestamp ?? timestamp))

                    let dissected = ProtocolDissector.dissect(
                        packetData: packetBytes,
                        packetNumber: packetNumber,
                        wireLength: origLen
                    )

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
                        capturedLength: capLen,
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
            }

            offset += blockLen
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
            formatName: "PCAPNG (Next Generation)",
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

public enum CaptureFileReader {
    public static func read(data: Data, fileName: String) throws -> PacketCaptureSummary {
        guard data.count >= 4 else { throw PCAPError.fileTooSmall }
        let magic = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self) }

        if magic == 0x0A0D0D0A {
            return try PCAPNGReader.parse(data: data, fileName: fileName)
        } else {
            return try PCAPReader.parse(data: data, fileName: fileName)
        }
    }
}
