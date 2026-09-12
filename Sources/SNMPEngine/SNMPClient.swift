import Foundation
import Network

public struct SNMPInterfaceMetric: Identifiable, Sendable, Hashable {
    public var id: Int { index }
    public let index: Int
    public var name: String
    public var description: String
    public var adminStatus: String // "Up", "Down"
    public var operStatus: String  // "Up", "Down"
    public var speedMbps: Double
    public var inOctets: UInt64
    public var outOctets: UInt64
    public var inErrors: UInt64
    public var outErrors: UInt64
    public var inDiscards: UInt64
    public var outDiscards: UInt64
    public var timestamp: Date

    public init(
        index: Int,
        name: String,
        description: String = "",
        adminStatus: String = "Up",
        operStatus: String = "Up",
        speedMbps: Double = 1000.0,
        inOctets: UInt64 = 0,
        outOctets: UInt64 = 0,
        inErrors: UInt64 = 0,
        outErrors: UInt64 = 0,
        inDiscards: UInt64 = 0,
        outDiscards: UInt64 = 0,
        timestamp: Date = Date()
    ) {
        self.index = index
        self.name = name
        self.description = description
        self.adminStatus = adminStatus
        self.operStatus = operStatus
        self.speedMbps = speedMbps
        self.inOctets = inOctets
        self.outOctets = outOctets
        self.inErrors = inErrors
        self.outErrors = outErrors
        self.inDiscards = inDiscards
        self.outDiscards = outDiscards
        self.timestamp = timestamp
    }
}

public struct InterfaceThroughputDelta: Sendable {
    public let inMbps: Double
    public let outMbps: Double
    public let inErrorsPerSec: Double
    public let outErrorsPerSec: Double
    public let inDiscardsPerSec: Double
    public let outDiscardsPerSec: Double
    public let inUtilizationPct: Double
    public let outUtilizationPct: Double

    public init(
        inMbps: Double,
        outMbps: Double,
        inErrorsPerSec: Double,
        outErrorsPerSec: Double,
        inDiscardsPerSec: Double,
        outDiscardsPerSec: Double,
        inUtilizationPct: Double,
        outUtilizationPct: Double
    ) {
        self.inMbps = inMbps
        self.outMbps = outMbps
        self.inErrorsPerSec = inErrorsPerSec
        self.outErrorsPerSec = outErrorsPerSec
        self.inDiscardsPerSec = inDiscardsPerSec
        self.outDiscardsPerSec = outDiscardsPerSec
        self.inUtilizationPct = inUtilizationPct
        self.outUtilizationPct = outUtilizationPct
    }
}

public enum SNMPClientError: Error, LocalizedError {
    case connectionFailed(String)
    case timeout
    case responseError(SNMPErrorStatus)
    case emptyResponse

    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg): return "SNMP UDP connection failed: \(msg)"
        case .timeout: return "SNMP request timed out after 3.0s."
        case .responseError(let status): return "SNMP Agent returned error: \(status.description)"
        case .emptyResponse: return "Empty response received from SNMP agent."
        }
    }
}

/// Asynchronous SNMP v1/v2c client built on Apple Network.framework UDP.
public actor SNMPClient {
    public init() {}

    /// Executes an SNMP GetRequest for one or more OIDs.
    public func get(
        host: String,
        port: Int = 161,
        community: String = "public",
        version: SNMPVersion = .v2c,
        oids: [String],
        timeout: TimeInterval = 3.0
    ) async throws -> [SNMPVarBind] {
        let varBinds = oids.map { SNMPVarBind(oid: $0, value: .null) }
        let pdu = SNMPPDU(tag: ASN1Tag.getRequest, varBinds: varBinds)
        let message = SNMPMessage(version: version, community: community, pdu: pdu)

        let response = try await sendSNMPMessage(host: host, port: port, message: message, timeout: timeout)
        if response.pdu.errorStatus != .noError {
            throw SNMPClientError.responseError(response.pdu.errorStatus)
        }
        return response.pdu.varBinds
    }

    /// Executes an SNMP GetNextRequest for an OID.
    public func getNext(
        host: String,
        port: Int = 161,
        community: String = "public",
        version: SNMPVersion = .v2c,
        oid: String,
        timeout: TimeInterval = 3.0
    ) async throws -> SNMPVarBind {
        let pdu = SNMPPDU(tag: ASN1Tag.getNextRequest, varBinds: [SNMPVarBind(oid: oid, value: .null)])
        let message = SNMPMessage(version: version, community: community, pdu: pdu)

        let response = try await sendSNMPMessage(host: host, port: port, message: message, timeout: timeout)
        if response.pdu.errorStatus != .noError {
            throw SNMPClientError.responseError(response.pdu.errorStatus)
        }
        guard let first = response.pdu.varBinds.first else {
            throw SNMPClientError.emptyResponse
        }
        return first
    }

    /// Recursively walks a subtree starting at `rootOID` until output exits prefix.
    public func walk(
        host: String,
        port: Int = 161,
        community: String = "public",
        version: SNMPVersion = .v2c,
        rootOID: String,
        maxIterations: Int = 200,
        timeout: TimeInterval = 3.0
    ) async throws -> [SNMPVarBind] {
        var results: [SNMPVarBind] = []
        var currentOID = rootOID
        let prefix = rootOID.hasSuffix(".") ? rootOID : rootOID + "."

        for _ in 0..<maxIterations {
            let vb = try await getNext(host: host, port: port, community: community, version: version, oid: currentOID, timeout: timeout)
            if vb.value == .endOfMibView || vb.value == .noSuchObject || vb.value == .noSuchInstance {
                break
            }
            if !vb.oid.hasPrefix(rootOID) && !vb.oid.hasPrefix(prefix) {
                // Walk has left the target subtree
                break
            }
            results.append(vb)
            currentOID = vb.oid
        }

        return results
    }

    /// Calculates interface throughput deltas between two sample snapshots.
    public static func calculateDeltas(
        previous: SNMPInterfaceMetric,
        current: SNMPInterfaceMetric
    ) -> InterfaceThroughputDelta {
        let timeDelta = max(0.1, current.timestamp.timeIntervalSince(previous.timestamp))

        let inOctetDelta = current.inOctets >= previous.inOctets ? (current.inOctets - previous.inOctets) : current.inOctets
        let outOctetDelta = current.outOctets >= previous.outOctets ? (current.outOctets - previous.outOctets) : current.outOctets

        let inBits = Double(inOctetDelta) * 8.0
        let outBits = Double(outOctetDelta) * 8.0

        let inMbps = (inBits / timeDelta) / 1_000_000.0
        let outMbps = (outBits / timeDelta) / 1_000_000.0

        let inErrorDelta = current.inErrors >= previous.inErrors ? (current.inErrors - previous.inErrors) : current.inErrors
        let outErrorDelta = current.outErrors >= previous.outErrors ? (current.outErrors - previous.outErrors) : current.outErrors

        let inDiscardDelta = current.inDiscards >= previous.inDiscards ? (current.inDiscards - previous.inDiscards) : current.inDiscards
        let outDiscardDelta = current.outDiscards >= previous.outDiscards ? (current.outDiscards - previous.outDiscards) : current.outDiscards

        let inErrorsPerSec = Double(inErrorDelta) / timeDelta
        let outErrorsPerSec = Double(outErrorDelta) / timeDelta

        let inDiscardsPerSec = Double(inDiscardDelta) / timeDelta
        let outDiscardsPerSec = Double(outDiscardDelta) / timeDelta

        let linkCapacity = max(1.0, current.speedMbps)
        let inUtil = min(100.0, (inMbps / linkCapacity) * 100.0)
        let outUtil = min(100.0, (outMbps / linkCapacity) * 100.0)

        return InterfaceThroughputDelta(
            inMbps: inMbps,
            outMbps: outMbps,
            inErrorsPerSec: inErrorsPerSec,
            outErrorsPerSec: outErrorsPerSec,
            inDiscardsPerSec: inDiscardsPerSec,
            outDiscardsPerSec: outDiscardsPerSec,
            inUtilizationPct: inUtil,
            outUtilizationPct: outUtil
        )
    }

    // MARK: - UDP Transport

    private func sendSNMPMessage(
        host: String,
        port: Int,
        message: SNMPMessage,
        timeout: TimeInterval
    ) async throws -> SNMPMessage {
        let payload = try message.serialize()
        let nwEndpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: UInt16(port))!
        )

        let params = NWParameters.udp
        let connection = NWConnection(to: nwEndpoint, using: params)

        return try await withCheckedThrowingContinuation { continuation in
            let queue = DispatchQueue(label: "com.nexwave.snmp.client")
            let resumer = SafeResumer()

            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + timeout)
            timer.setEventHandler {
                resumer.runOnce {
                    connection.cancel()
                    continuation.resume(throwing: SNMPClientError.timeout)
                }
            }
            timer.resume()

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: payload, completion: .contentProcessed { sendError in
                        if let err = sendError {
                            resumer.runOnce {
                                timer.cancel()
                                connection.cancel()
                                continuation.resume(throwing: SNMPClientError.connectionFailed(err.localizedDescription))
                            }
                            return
                        }

                        connection.receive(minimumIncompleteLength: 1, maximumLength: 65535) { content, _, _, recvError in
                            resumer.runOnce {
                                timer.cancel()
                                connection.cancel()

                                if let err = recvError {
                                    continuation.resume(throwing: SNMPClientError.connectionFailed(err.localizedDescription))
                                    return
                                }
                                guard let data = content, !data.isEmpty else {
                                    continuation.resume(throwing: SNMPClientError.emptyResponse)
                                    return
                                }

                                do {
                                    let resp = try SNMPMessage.deserialize(data: data)
                                    continuation.resume(returning: resp)
                                } catch {
                                    continuation.resume(throwing: error)
                                }
                            }
                        }
                    })
                case .failed(let err):
                    resumer.runOnce {
                        timer.cancel()
                        connection.cancel()
                        continuation.resume(throwing: SNMPClientError.connectionFailed(err.localizedDescription))
                    }
                case .cancelled:
                    break
                default:
                    break
                }
            }

            connection.start(queue: queue)
        }
    }
}

private final class SafeResumer: @unchecked Sendable {
    private let lock = NSLock()
    private var isResumed = false

    func runOnce(_ block: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !isResumed else { return }
        isResumed = true
        block()
    }
}
