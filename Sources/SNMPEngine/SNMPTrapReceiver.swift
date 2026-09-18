import Foundation
import Network

/// Asynchronous UDP SNMP Trap and Inform receiver daemon (RFC 1157, RFC 3416).
/// Binds UDP socket (port 162 or unprivileged port 1162) and streams decoded trap records.
public actor SNMPTrapReceiver {
    public private(set) var isListening: Bool = false
    public private(set) var port: Int = 1162
    public private(set) var trapsReceivedCount: Int = 0
    public private(set) var informsReceivedCount: Int = 0
    public private(set) var lastError: String? = nil

    private var listener: NWListener?
    private var streamContinuation: AsyncStream<SNMPTrapRecord>.Continuation?
    private let queue = DispatchQueue(label: "com.nexwave.snmp.trapreceiver")

    public init() {}

    /// Real-time stream of incoming parsed SNMP traps and informs.
    public var trapStream: AsyncStream<SNMPTrapRecord> {
        AsyncStream { continuation in
            self.streamContinuation = continuation
            continuation.onTermination = { @Sendable _ in }
        }
    }

    /// Starts listening on specified UDP port.
    public func start(port: Int = 1162) throws {
        if isListening {
            stop()
        }

        self.port = port
        self.lastError = nil

        let params = NWParameters.udp
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw NSError(domain: "SNMPTrapReceiver", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid UDP port: \(port)"])
        }

        do {
            let nwListener = try NWListener(using: params, on: nwPort)
            self.listener = nwListener

            nwListener.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                Task {
                    await self.handleStateChange(state)
                }
            }

            nwListener.newConnectionHandler = { [weak self] connection in
                guard let self = self else { return }
                Task {
                    await self.handleIncomingConnection(connection)
                }
            }

            nwListener.start(queue: queue)
            self.isListening = true
        } catch {
            self.lastError = error.localizedDescription
            self.isListening = false
            throw error
        }
    }

    /// Stops the UDP listener daemon.
    public func stop() {
        listener?.cancel()
        listener = nil
        isListening = false
    }

    /// Allows manual injection of simulated trap records for local testing without network equipment.
    public func injectSimulatedTrap(_ record: SNMPTrapRecord) {
        trapsReceivedCount += 1
        if record.isInform {
            informsReceivedCount += 1
        }
        streamContinuation?.yield(record)
    }

    private func handleStateChange(_ state: NWListener.State) {
        switch state {
        case .ready:
            isListening = true
            lastError = nil
        case .failed(let err):
            isListening = false
            lastError = err.localizedDescription
        case .cancelled:
            isListening = false
        default:
            break
        }
    }

    private func handleIncomingConnection(_ connection: NWConnection) {
        connection.start(queue: queue)

        let hostStr: String
        let portInt: Int
        if case .hostPort(let host, let port) = connection.endpoint {
            switch host {
            case .ipv4(let addr): hostStr = "\(addr)"
            case .ipv6(let addr): hostStr = "\(addr)"
            case .name(let name, _): hostStr = name
            @unknown default: hostStr = "unknown"
            }
            portInt = Int(port.rawValue)
        } else {
            hostStr = "unknown"
            portInt = 162
        }

        connection.receiveMessage { [weak self] content, _, _, _ in
            guard let self = self else { return }
            if let data = content, !data.isEmpty {
                Task {
                    await self.processPacket(data: data, remoteHost: hostStr, remotePort: portInt, connection: connection)
                }
            }
        }
    }

    private func processPacket(data: Data, remoteHost: String, remotePort: Int, connection: NWConnection) {
        // Try decoding as SNMPv1 or SNMPv2c message
        if let msg = try? SNMPMessage.deserialize(data: data) {
            let pdu = msg.pdu

            if pdu.tag == ASN1Tag.trapV1, let payload = pdu.v1TrapPayload {
                let severity = computeV1Severity(payload.genericTrap, varBinds: pdu.varBinds)
                let trapOID = "\(payload.enterprise).\(payload.genericTrap.rawValue).\(payload.specificTrap)"
                let record = SNMPTrapRecord(
                    sourceAddress: remoteHost,
                    sourcePort: remotePort,
                    version: .v1,
                    community: msg.community,
                    enterpriseOID: payload.enterprise,
                    trapOID: trapOID,
                    genericTrap: payload.genericTrap,
                    specificTrap: payload.specificTrap,
                    timeStampTicks: payload.timeStamp,
                    varBinds: pdu.varBinds,
                    severity: severity,
                    isInform: false
                )
                trapsReceivedCount += 1
                streamContinuation?.yield(record)
                return
            }

            if pdu.tag == ASN1Tag.snmpV2Trap || pdu.tag == ASN1Tag.informRequest {
                let isInform = (pdu.tag == ASN1Tag.informRequest)

                // If InformRequest, send GetResponse ACK back per RFC 3416
                if isInform {
                    informsReceivedCount += 1
                    let ackPDU = SNMPPDU(
                        tag: ASN1Tag.getResponse,
                        requestId: pdu.requestId,
                        errorStatus: .noError,
                        errorIndex: 0,
                        varBinds: pdu.varBinds
                    )
                    let ackMsg = SNMPMessage(version: msg.version, community: msg.community, pdu: ackPDU)
                    if let ackData = try? ackMsg.serialize() {
                        connection.send(content: ackData, completion: .idempotent)
                    }
                }

                // Extract sysUpTime.0 (1.3.6.1.2.1.1.3.0) and snmpTrapOID.0 (1.3.6.1.6.3.1.1.4.1.0)
                var sysUpTime: UInt32 = 0
                var trapOID = "1.3.6.1.6.3.1.1.5.1" // coldStart default
                var enterpriseOID = "1.3.6.1"

                for vb in pdu.varBinds {
                    if vb.oid == "1.3.6.1.2.1.1.3.0", case .timeTicks(let t) = vb.value {
                        sysUpTime = t
                    } else if vb.oid == "1.3.6.1.6.3.1.1.4.1.0", case .oid(let o) = vb.value {
                        trapOID = o
                    } else if vb.oid == "1.3.6.1.6.3.1.1.4.3.0", case .oid(let o) = vb.value {
                        enterpriseOID = o
                    }
                }

                let severity = computeV2Severity(trapOID: trapOID, varBinds: pdu.varBinds)
                let record = SNMPTrapRecord(
                    sourceAddress: remoteHost,
                    sourcePort: remotePort,
                    version: msg.version,
                    community: msg.community,
                    enterpriseOID: enterpriseOID,
                    trapOID: trapOID,
                    timeStampTicks: sysUpTime,
                    varBinds: pdu.varBinds,
                    severity: severity,
                    isInform: isInform
                )
                trapsReceivedCount += 1
                streamContinuation?.yield(record)
                return
            }
        }

        // Try decoding as SNMPv3 Message
        if let v3Msg = try? SNMPv3Message.deserialize(data: data) {
            if !v3Msg.isEncrypted, let scoped = try? ScopedPDU.deserialize(data: v3Msg.scopedPDUData) {
                let pdu = scoped.pdu
                if pdu.tag == ASN1Tag.snmpV2Trap || pdu.tag == ASN1Tag.informRequest {
                    let isInform = (pdu.tag == ASN1Tag.informRequest)
                    var sysUpTime: UInt32 = 0
                    var trapOID = "1.3.6.1.6.3.1.1.5.1"

                    for vb in pdu.varBinds {
                        if vb.oid == "1.3.6.1.2.1.1.3.0", case .timeTicks(let t) = vb.value {
                            sysUpTime = t
                        } else if vb.oid == "1.3.6.1.6.3.1.1.4.1.0", case .oid(let o) = vb.value {
                            trapOID = o
                        }
                    }

                    let severity = computeV2Severity(trapOID: trapOID, varBinds: pdu.varBinds)
                    let record = SNMPTrapRecord(
                        sourceAddress: remoteHost,
                        sourcePort: remotePort,
                        version: .v3,
                        community: "v3-user:\(v3Msg.securityParameters.userName)",
                        enterpriseOID: "1.3.6.1.6.3.1",
                        trapOID: trapOID,
                        timeStampTicks: sysUpTime,
                        varBinds: pdu.varBinds,
                        severity: severity,
                        isInform: isInform
                    )
                    trapsReceivedCount += 1
                    if isInform { informsReceivedCount += 1 }
                    streamContinuation?.yield(record)
                }
            }
        }
    }

    private func computeV1Severity(_ trap: GenericTrapType, varBinds: [SNMPVarBind]) -> TrapSeverity {
        switch trap {
        case .linkDown:
            return .critical
        case .coldStart, .warmStart, .authenticationFailure, .egpNeighborLoss:
            return .warning
        case .linkUp, .enterpriseSpecific:
            for vb in varBinds {
                let desc = vb.value.description.lowercased()
                if desc.contains("fail") || desc.contains("down") || desc.contains("error") || desc.contains("critical") {
                    return .critical
                }
            }
            return .info
        }
    }

    private func computeV2Severity(trapOID: String, varBinds: [SNMPVarBind]) -> TrapSeverity {
        // RFC 3418 standard trap OIDs (1.3.6.1.6.3.1.1.5.*)
        if trapOID.hasSuffix(".3") || trapOID.contains("linkDown") {
            return .critical
        }
        if trapOID.hasSuffix(".1") || trapOID.hasSuffix(".2") || trapOID.hasSuffix(".5") || trapOID.contains("coldStart") || trapOID.contains("warmStart") || trapOID.contains("authenticationFailure") {
            return .warning
        }
        for vb in varBinds {
            let desc = vb.value.description.lowercased()
            if desc.contains("fail") || desc.contains("down") || desc.contains("alarm") || desc.contains("critical") {
                return .critical
            }
            if desc.contains("warn") || desc.contains("degrade") {
                return .warning
            }
        }
        return .info
    }
}
