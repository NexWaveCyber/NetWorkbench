import Foundation

public final class FlowTracker: @unchecked Sendable {

    private struct BidirectionalFlowKey: Hashable {
        let ep1: String
        let ep2: String
        let protocolType: PacketProtocol

        init(source: String, destination: String, protocolType: PacketProtocol) {
            self.protocolType = protocolType
            if source <= destination {
                self.ep1 = source
                self.ep2 = destination
            } else {
                self.ep1 = destination
                self.ep2 = source
            }
        }
    }

    private struct FlowAccumulator {
        let ep1: String
        let ep2: String
        let protocolType: PacketProtocol
        var startTime: Date
        var endTime: Date
        var packets1to2: Int = 0
        var packets2to1: Int = 0
        var bytes1to2: Int = 0
        var bytes2to1: Int = 0
        var anomalies: [TCPAnomaly] = []
    }

    private var flows: [BidirectionalFlowKey: FlowAccumulator] = [:]
    private var talkerBytesSent: [String: Int] = [:]
    private var talkerBytesRecv: [String: Int] = [:]
    private var talkerPackets: [String: Int] = [:]
    private var protocolPackets: [PacketProtocol: Int] = [:]
    private var protocolBytes: [PacketProtocol: Int] = [:]
    private var totalBytesAll: Int = 0

    public init() {}

    public func record(packet: PacketRecord) {
        let srcEndpoint: String
        let dstEndpoint: String

        if let sp = packet.sourcePort, let dp = packet.destinationPort {
            srcEndpoint = "\(packet.sourceAddress):\(sp)"
            dstEndpoint = "\(packet.destinationAddress):\(dp)"
        } else {
            srcEndpoint = packet.sourceAddress
            dstEndpoint = packet.destinationAddress
        }

        let key = BidirectionalFlowKey(source: srcEndpoint, destination: dstEndpoint, protocolType: packet.protocolType)

        if var existing = flows[key] {
            existing.endTime = max(existing.endTime, packet.timestamp)
            if srcEndpoint == existing.ep1 {
                existing.packets1to2 += 1
                existing.bytes1to2 += packet.wireLength
            } else {
                existing.packets2to1 += 1
                existing.bytes2to1 += packet.wireLength
            }
            existing.anomalies.append(contentsOf: packet.anomalies)
            flows[key] = existing
        } else {
            var newAcc = FlowAccumulator(
                ep1: key.ep1,
                ep2: key.ep2,
                protocolType: packet.protocolType,
                startTime: packet.timestamp,
                endTime: packet.timestamp
            )
            if srcEndpoint == key.ep1 {
                newAcc.packets1to2 = 1
                newAcc.bytes1to2 = packet.wireLength
            } else {
                newAcc.packets2to1 = 1
                newAcc.bytes2to1 = packet.wireLength
            }
            newAcc.anomalies = packet.anomalies
            flows[key] = newAcc
        }

        // Talker tracking (by base IP address, ignoring port)
        let srcIP = packet.sourceAddress
        let dstIP = packet.destinationAddress

        talkerBytesSent[srcIP, default: 0] += packet.wireLength
        talkerPackets[srcIP, default: 0] += 1

        talkerBytesRecv[dstIP, default: 0] += packet.wireLength
        talkerPackets[dstIP, default: 0] += 1

        protocolPackets[packet.protocolType, default: 0] += 1
        protocolBytes[packet.protocolType, default: 0] += packet.wireLength
        totalBytesAll += packet.wireLength
    }

    public func buildFlows() -> [ConversationFlow] {
        return flows.values.map { acc in
            let dur = max(0, acc.endTime.timeIntervalSince(acc.startTime))
            let id = "\(acc.ep1) <-> \(acc.ep2) (\(acc.protocolType))"
            return ConversationFlow(
                id: id,
                source: acc.ep1,
                destination: acc.ep2,
                protocolType: acc.protocolType,
                startTime: acc.startTime,
                endTime: acc.endTime,
                duration: dur,
                packetsAtoB: acc.packets1to2,
                packetsBtoA: acc.packets2to1,
                totalPackets: acc.packets1to2 + acc.packets2to1,
                bytesAtoB: acc.bytes1to2,
                bytesBtoA: acc.bytes2to1,
                totalBytes: acc.bytes1to2 + acc.bytes2to1,
                anomalies: acc.anomalies
            )
        }.sorted { $0.totalBytes > $1.totalBytes }
    }

    public func buildTopTalkers() -> [TalkerSummary] {
        let allIPs = Set(talkerBytesSent.keys).union(talkerBytesRecv.keys)
        return allIPs.map { ip in
            let sent = talkerBytesSent[ip, default: 0]
            let recv = talkerBytesRecv[ip, default: 0]
            let pkts = talkerPackets[ip, default: 0]
            return TalkerSummary(
                ipAddress: ip,
                sentBytes: sent,
                receivedBytes: recv,
                totalBytes: sent + recv,
                packetCount: pkts
            )
        }.sorted { $0.totalBytes > $1.totalBytes }
    }

    public func buildProtocolDistribution() -> [ProtocolShare] {
        guard totalBytesAll > 0 else { return [] }
        return protocolPackets.keys.map { proto in
            let pkts = protocolPackets[proto, default: 0]
            let bytes = protocolBytes[proto, default: 0]
            let pct = (Double(bytes) / Double(totalBytesAll)) * 100.0
            return ProtocolShare(
                protocolType: proto,
                packetCount: pkts,
                byteCount: bytes,
                percentage: pct
            )
        }.sorted { $0.byteCount > $1.byteCount }
    }
}
