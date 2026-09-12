import Foundation

public final class TCPAnomalyDetector: @unchecked Sendable {

    private struct TCPFlowDirectionKey: Hashable {
        let sourceIP: String
        let destIP: String
        let sourcePort: Int
        let destPort: Int
    }

    private struct SentSegment {
        let packetNumber: Int
        let seq: UInt32
        let payloadLen: Int
        let timestamp: Date
    }

    private struct FlowState {
        var sentSegments: [UInt32: SentSegment] = [:]
        var lastAckNum: UInt32? = nil
        var lastAckWindow: UInt16? = nil
        var dupAckCount: Int = 0
        var hasSeenSyn: Bool = false
        var hasSeenSynAck: Bool = false
        var synPacketNum: Int? = nil
    }

    private var states: [TCPFlowDirectionKey: FlowState] = [:]

    public init() {}

    public func analyze(
        packetNumber: Int,
        timestamp: Date,
        sourceIP: String,
        destIP: String,
        sourcePort: Int,
        destPort: Int,
        tcpFlags: TCPFlags,
        seq: UInt32,
        ack: UInt32,
        window: UInt16,
        payloadLength: Int
    ) -> [TCPAnomaly] {
        var anomalies: [TCPAnomaly] = []

        let dirKey = TCPFlowDirectionKey(
            sourceIP: sourceIP,
            destIP: destIP,
            sourcePort: sourcePort,
            destPort: destPort
        )

        var state = states[dirKey, default: FlowState()]

        // 1. Connection Reset (RST)
        if tcpFlags.contains(.rst) {
            anomalies.append(.connectionReset)
        }

        // 2. Zero Window (Flow Control Stall)
        if window == 0 && !tcpFlags.contains(.syn) && !tcpFlags.contains(.rst) {
            anomalies.append(.zeroWindow)
        }

        // 3. SYN tracking
        if tcpFlags.contains(.syn) && !tcpFlags.contains(.ack) {
            state.hasSeenSyn = true
            state.synPacketNum = packetNumber
        } else if tcpFlags.contains(.syn) && tcpFlags.contains(.ack) {
            state.hasSeenSynAck = true
        }

        // 4. Retransmission Detection
        if payloadLength > 0 || tcpFlags.contains(.syn) || tcpFlags.contains(.fin) {
            if let existing = state.sentSegments[seq] {
                if existing.payloadLen == payloadLength && existing.packetNumber != packetNumber {
                    anomalies.append(.retransmission(originalPacket: existing.packetNumber))
                }
            } else {
                state.sentSegments[seq] = SentSegment(
                    packetNumber: packetNumber,
                    seq: seq,
                    payloadLen: payloadLength,
                    timestamp: timestamp
                )
            }
        }

        // 5. Duplicate ACK & Window Update Detection
        if tcpFlags.contains(.ack) && !tcpFlags.contains(.syn) && !tcpFlags.contains(.rst) && payloadLength == 0 {
            if let lastAck = state.lastAckNum {
                if ack == lastAck {
                    if let lastWin = state.lastAckWindow, window != lastWin && window > 0 {
                        anomalies.append(.windowUpdate)
                    } else {
                        state.dupAckCount += 1
                        if state.dupAckCount >= 2 { // Fast retransmission threshold (original + 2 dupes = 3 total)
                            anomalies.append(.duplicateAck(count: state.dupAckCount, ackNum: ack))
                        }
                    }
                } else if ack > lastAck {
                    state.dupAckCount = 0
                }
            }
            state.lastAckNum = ack
            state.lastAckWindow = window
        }

        states[dirKey] = state
        return anomalies
    }

    public func finalize() -> [AnomalyEvent] {
        // Look for unanswered SYNs
        var finalEvents: [AnomalyEvent] = []
        for (key, state) in states {
            if state.hasSeenSyn && !state.hasSeenSynAck, let synNum = state.synPacketNum {
                let event = AnomalyEvent(
                    packetNumber: synNum,
                    relativeTime: 0,
                    source: "\(key.sourceIP):\(key.sourcePort)",
                    destination: "\(key.destIP):\(key.destPort)",
                    anomaly: .unansweredSyn,
                    severity: .warning,
                    description: "TCP SYN was transmitted without SYN-ACK response (host down or port filtered)"
                )
                finalEvents.append(event)
            }
        }
        return finalEvents
    }
}
