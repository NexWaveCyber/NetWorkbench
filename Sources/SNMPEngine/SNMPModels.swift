import Foundation

public enum SNMPVersion: Int32, Codable, Sendable, CaseIterable {
    case v1 = 0
    case v2c = 1
    case v3 = 3

    public var displayString: String {
        switch self {
        case .v1: return "SNMPv1"
        case .v2c: return "SNMPv2c"
        case .v3: return "SNMPv3"
        }
    }
}

public enum SNMPErrorStatus: Int32, Codable, Sendable {
    case noError = 0
    case tooBig = 1
    case noSuchName = 2
    case badValue = 3
    case readOnly = 4
    case genErr = 5
    case noAccess = 6
    case wrongType = 7
    case wrongLength = 8
    case wrongEncoding = 9
    case wrongValue = 10
    case noCreation = 11
    case inconsistentValue = 12
    case resourceUnavailable = 13
    case commitFailed = 14
    case undoFailed = 15
    case authorizationError = 16
    case notWritable = 17
    case inconsistentName = 18

    public var description: String {
        switch self {
        case .noError: return "No Error"
        case .tooBig: return "Too Big"
        case .noSuchName: return "No Such Name"
        case .badValue: return "Bad Value"
        case .readOnly: return "Read Only"
        case .genErr: return "General Error"
        case .noAccess: return "No Access"
        case .wrongType: return "Wrong Type"
        case .wrongLength: return "Wrong Length"
        case .wrongEncoding: return "Wrong Encoding"
        case .wrongValue: return "Wrong Value"
        case .noCreation: return "No Creation"
        case .inconsistentValue: return "Inconsistent Value"
        case .resourceUnavailable: return "Resource Unavailable"
        case .commitFailed: return "Commit Failed"
        case .undoFailed: return "Undo Failed"
        case .authorizationError: return "Authorization Error"
        case .notWritable: return "Not Writable"
        case .inconsistentName: return "Inconsistent Name"
        }
    }
}

public enum SNMPValue: Sendable, Hashable {
    case integer(Int64)
    case octetString(String)
    case rawBytes(Data)
    case oid(String)
    case ipAddress(String)
    case counter32(UInt32)
    case gauge32(UInt32)
    case timeTicks(UInt32)
    case counter64(UInt64)
    case null
    case noSuchObject
    case noSuchInstance
    case endOfMibView

    public var displayString: String {
        switch self {
        case .integer(let v): return "\(v)"
        case .octetString(let s): return s
        case .rawBytes(let d): return d.map { String(format: "%02X", $0) }.joined(separator: " ")
        case .oid(let o): return o
        case .ipAddress(let ip): return ip
        case .counter32(let c): return "\(c)"
        case .gauge32(let g): return "\(g)"
        case .timeTicks(let t):
            let seconds = Double(t) / 100.0
            return String(format: "%.2f s (%u ticks)", seconds, t)
        case .counter64(let c64): return "\(c64)"
        case .null: return "NULL"
        case .noSuchObject: return "No Such Object"
        case .noSuchInstance: return "No Such Instance"
        case .endOfMibView: return "End of MIB View"
        }
    }

    public var description: String { displayString }
}

extension SNMPValue: CustomStringConvertible {}

public struct SNMPVarBind: Identifiable, Sendable, Hashable {
    public var id: String { oid }
    public let oid: String
    public let value: SNMPValue

    public init(oid: String, value: SNMPValue) {
        self.oid = oid
        self.value = value
    }
}

public struct SNMPPDU: Sendable {
    public let tag: UInt8
    public let requestId: Int32
    public let errorStatus: SNMPErrorStatus
    public let errorIndex: Int32
    public let varBinds: [SNMPVarBind]

    public init(
        tag: UInt8 = ASN1Tag.getRequest,
        requestId: Int32 = Int32.random(in: 1...Int32.max),
        errorStatus: SNMPErrorStatus = .noError,
        errorIndex: Int32 = 0,
        varBinds: [SNMPVarBind]
    ) {
        self.tag = tag
        self.requestId = requestId
        self.errorStatus = errorStatus
        self.errorIndex = errorIndex
        self.varBinds = varBinds
    }
    public func serialize() throws -> Data {
        var varBindsData = Data()
        for vb in varBinds {
            let oidData = try ASN1Encoder.encodeOID(vb.oid)
            let valData: Data
            switch vb.value {
            case .null:
                valData = ASN1Encoder.encodeNull()
            case .integer(let i):
                valData = ASN1Encoder.encodeInteger(i)
            case .octetString(let s):
                valData = ASN1Encoder.encodeOctetString(s)
            case .rawBytes(let b):
                valData = ASN1Encoder.encodeOctetBytes(b)
            case .oid(let o):
                valData = try ASN1Encoder.encodeOID(o)
            case .ipAddress(let ip):
                let parts = ip.split(separator: ".").compactMap { UInt8($0) }
                if parts.count == 4 {
                    valData = Data([ASN1Tag.ipAddress, 0x04]) + Data(parts)
                } else {
                    valData = ASN1Encoder.encodeOctetString(ip)
                }
            case .counter32(let c):
                valData = ASN1Encoder.encodeUnsignedInteger(tag: ASN1Tag.counter32, UInt64(c))
            case .gauge32(let g):
                valData = ASN1Encoder.encodeUnsignedInteger(tag: ASN1Tag.gauge32, UInt64(g))
            case .timeTicks(let t):
                valData = ASN1Encoder.encodeUnsignedInteger(tag: ASN1Tag.timeTicks, UInt64(t))
            case .counter64(let c64):
                valData = ASN1Encoder.encodeUnsignedInteger(tag: ASN1Tag.counter64, c64)
            default:
                valData = ASN1Encoder.encodeNull()
            }
            let vbSeq = ASN1Encoder.encodeSequence(oidData + valData)
            varBindsData.append(vbSeq)
        }
        let varBindsSeq = ASN1Encoder.encodeSequence(varBindsData)

        let reqIdData = ASN1Encoder.encodeInteger(Int64(requestId))
        let errStatusData = ASN1Encoder.encodeInteger(Int64(errorStatus.rawValue))
        let errIdxData = ASN1Encoder.encodeInteger(Int64(errorIndex))

        let pduContent = reqIdData + errStatusData + errIdxData + varBindsSeq
        return ASN1Encoder.encodePDU(tag: tag, content: pduContent)
    }

    public static func deserialize(decoder: inout ASN1Decoder) throws -> SNMPPDU {
        let (pduTag, mutPduDecoder) = try decoder.enterPDU()
        var pduDecoder = mutPduDecoder

        let reqId = try pduDecoder.readInteger()
        let errStatusInt = try pduDecoder.readInteger()
        let errStatus = SNMPErrorStatus(rawValue: Int32(errStatusInt)) ?? .genErr
        let errIdx = try pduDecoder.readInteger()

        var varBindsSeq = try pduDecoder.enterSequence()
        var varBinds: [SNMPVarBind] = []

        while !varBindsSeq.isAtEnd {
            var vbSeq = try varBindsSeq.enterSequence()
            let oid = try vbSeq.readOID()
            let valTag = try vbSeq.peekTag()

            let val: SNMPValue
            switch valTag {
            case ASN1Tag.null:
                _ = try vbSeq.readTag()
                _ = try vbSeq.readLength()
                val = .null
            case ASN1Tag.integer:
                let i = try vbSeq.readInteger()
                val = .integer(i)
            case ASN1Tag.octetString:
                let s = try vbSeq.readOctetString()
                val = .octetString(s)
            case ASN1Tag.ipAddress:
                let ip = try vbSeq.readOctetString()
                val = .ipAddress(ip)
            case ASN1Tag.counter32:
                let c = try vbSeq.readUnsignedInteger()
                val = .counter32(UInt32(c & 0xFFFFFFFF))
            case ASN1Tag.gauge32:
                let g = try vbSeq.readUnsignedInteger()
                val = .gauge32(UInt32(g & 0xFFFFFFFF))
            case ASN1Tag.timeTicks:
                let t = try vbSeq.readUnsignedInteger()
                val = .timeTicks(UInt32(t & 0xFFFFFFFF))
            case ASN1Tag.counter64:
                let c64 = try vbSeq.readUnsignedInteger()
                val = .counter64(c64)
            case ASN1Tag.objectIdentifier:
                let o = try vbSeq.readOID()
                val = .oid(o)
            case ASN1Tag.noSuchObject:
                _ = try vbSeq.readTag()
                _ = try vbSeq.readLength()
                val = .noSuchObject
            case ASN1Tag.noSuchInstance:
                _ = try vbSeq.readTag()
                _ = try vbSeq.readLength()
                val = .noSuchInstance
            case ASN1Tag.endOfMibView:
                _ = try vbSeq.readTag()
                _ = try vbSeq.readLength()
                val = .endOfMibView
            default:
                let len = try vbSeq.readLength()
                let bytes = try vbSeq.readRawBytes(count: len)
                val = .rawBytes(bytes)
            }

            varBinds.append(SNMPVarBind(oid: oid, value: val))
        }

        return SNMPPDU(
            tag: pduTag,
            requestId: Int32(reqId),
            errorStatus: errStatus,
            errorIndex: Int32(errIdx),
            varBinds: varBinds
        )
    }
}

public struct SNMPMessage: Sendable {
    public let version: SNMPVersion
    public let community: String
    public let pdu: SNMPPDU

    public init(version: SNMPVersion = .v2c, community: String = "public", pdu: SNMPPDU) {
        self.version = version
        self.community = community
        self.pdu = pdu
    }

    public func serialize() throws -> Data {
        let pduData = try pdu.serialize()
        let verData = ASN1Encoder.encodeInteger(Int64(version.rawValue))
        let commData = ASN1Encoder.encodeOctetString(community)
        return ASN1Encoder.encodeSequence(verData + commData + pduData)
    }

    public static func deserialize(data: Data) throws -> SNMPMessage {
        var outerDecoder = ASN1Decoder(data: data)
        var msgSeq = try outerDecoder.enterSequence()

        let verInt = try msgSeq.readInteger()
        let version = SNMPVersion(rawValue: Int32(verInt)) ?? .v2c
        let community = try msgSeq.readOctetString()
        let pdu = try SNMPPDU.deserialize(decoder: &msgSeq)

        return SNMPMessage(version: version, community: community, pdu: pdu)
    }
}

/// ScopedPDU for SNMPv3 (RFC 3412 Section 6.2)
public struct ScopedPDU: Sendable {
    public let contextEngineID: Data
    public let contextName: String
    public let pdu: SNMPPDU

    public init(contextEngineID: Data = Data(), contextName: String = "", pdu: SNMPPDU) {
        self.contextEngineID = contextEngineID
        self.contextName = contextName
        self.pdu = pdu
    }

    public func serialize() throws -> Data {
        let ctxEngData = ASN1Encoder.encodeOctetBytes(contextEngineID)
        let ctxNameData = ASN1Encoder.encodeOctetString(contextName)
        let pduData = try pdu.serialize()
        return ASN1Encoder.encodeSequence(ctxEngData + ctxNameData + pduData)
    }

    public static func deserialize(data: Data) throws -> ScopedPDU {
        var decoder = ASN1Decoder(data: data)
        var seq = try decoder.enterSequence()
        let ctxEngId = try seq.readOctetBytes()
        let ctxName = try seq.readOctetString()
        let pdu = try SNMPPDU.deserialize(decoder: &seq)
        return ScopedPDU(contextEngineID: ctxEngId, contextName: ctxName, pdu: pdu)
    }
}

/// USM Security Parameters (RFC 3414 Section 2.4)
public struct UsmSecurityParameters: Sendable {
    public var engineID: Data
    public var engineBoots: Int32
    public var engineTime: Int32
    public var userName: String
    public var authParameters: Data
    public var privParameters: Data

    public init(
        engineID: Data = Data(),
        engineBoots: Int32 = 0,
        engineTime: Int32 = 0,
        userName: String = "",
        authParameters: Data = Data(),
        privParameters: Data = Data()
    ) {
        self.engineID = engineID
        self.engineBoots = engineBoots
        self.engineTime = engineTime
        self.userName = userName
        self.authParameters = authParameters
        self.privParameters = privParameters
    }

    public func serialize() -> Data {
        let engData = ASN1Encoder.encodeOctetBytes(engineID)
        let bootsData = ASN1Encoder.encodeInteger(Int64(engineBoots))
        let timeData = ASN1Encoder.encodeInteger(Int64(engineTime))
        let userData = ASN1Encoder.encodeOctetString(userName)
        let authData = ASN1Encoder.encodeOctetBytes(authParameters)
        let privData = ASN1Encoder.encodeOctetBytes(privParameters)
        return ASN1Encoder.encodeSequence(engData + bootsData + timeData + userData + authData + privData)
    }

    public static func deserialize(data: Data) throws -> UsmSecurityParameters {
        var decoder = ASN1Decoder(data: data)
        var seq = try decoder.enterSequence()
        let eng = try seq.readOctetBytes()
        let boots = Int32(try seq.readInteger())
        let time = Int32(try seq.readInteger())
        let user = try seq.readOctetString()
        let auth = try seq.readOctetBytes()
        let priv = try seq.readOctetBytes()
        return UsmSecurityParameters(
            engineID: eng,
            engineBoots: boots,
            engineTime: time,
            userName: user,
            authParameters: auth,
            privParameters: priv
        )
    }
}

/// SNMPv3 Message (RFC 3412)
public struct SNMPv3Message: Sendable {
    public let msgID: Int32
    public let msgMaxSize: Int32
    public let msgFlags: UInt8 // 0x04 = reportable, 0x01 = auth, 0x02 = priv
    public let securityModel: Int32 // 3 = USM
    public var securityParameters: UsmSecurityParameters
    public var scopedPDUData: Data
    public var isEncrypted: Bool

    public init(
        msgID: Int32 = Int32.random(in: 1...Int32.max),
        msgMaxSize: Int32 = 65507,
        msgFlags: UInt8 = 0x04,
        securityModel: Int32 = 3,
        securityParameters: UsmSecurityParameters,
        scopedPDUData: Data,
        isEncrypted: Bool = false
    ) {
        self.msgID = msgID
        self.msgMaxSize = msgMaxSize
        self.msgFlags = msgFlags
        self.securityModel = securityModel
        self.securityParameters = securityParameters
        self.scopedPDUData = scopedPDUData
        self.isEncrypted = isEncrypted
    }

    public func serialize(authKey: Data = Data(), authProtocol: SNMPv3AuthProtocol = .none) throws -> Data {
        let idData = ASN1Encoder.encodeInteger(Int64(msgID))
        let sizeData = ASN1Encoder.encodeInteger(Int64(msgMaxSize))
        let flagsData = ASN1Encoder.encodeOctetBytes(Data([msgFlags]))
        let modelData = ASN1Encoder.encodeInteger(Int64(securityModel))
        let headerSeq = ASN1Encoder.encodeSequence(idData + sizeData + flagsData + modelData)

        var secParams = securityParameters
        if authProtocol != .none {
            secParams.authParameters = Data(repeating: 0, count: authProtocol.truncatedAuthLength)
        }
        let rawSecParamsSeq = secParams.serialize()
        let secParamsOctetString = ASN1Encoder.encodeOctetBytes(rawSecParamsSeq)

        let dataPayload: Data
        if isEncrypted {
            dataPayload = ASN1Encoder.encodeOctetBytes(scopedPDUData)
        } else {
            dataPayload = scopedPDUData
        }

        let verData = ASN1Encoder.encodeInteger(3)
        var rawMsg = ASN1Encoder.encodeSequence(verData + headerSeq + secParamsOctetString + dataPayload)

        if authProtocol != .none && !authKey.isEmpty {
            let hmac = SNMPv3Crypto.computeAuthHMAC(data: rawMsg, authKey: authKey, protocol: authProtocol)
            secParams.authParameters = hmac
            let finalSecParams = ASN1Encoder.encodeOctetBytes(secParams.serialize())
            rawMsg = ASN1Encoder.encodeSequence(verData + headerSeq + finalSecParams + dataPayload)
        }

        return rawMsg
    }

    public static func deserialize(data: Data) throws -> SNMPv3Message {
        var outerDecoder = ASN1Decoder(data: data)
        var msgSeq = try outerDecoder.enterSequence()

        let verInt = try msgSeq.readInteger()
        guard verInt == 3 else {
            throw NSError(domain: "SNMPEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Expected SNMPv3 version (3), got \(verInt)"])
        }

        var headerSeq = try msgSeq.enterSequence()
        let msgId = Int32(try headerSeq.readInteger())
        let msgMaxSize = Int32(try headerSeq.readInteger())
        let flagsData = try headerSeq.readOctetBytes()
        let msgFlags = flagsData.first ?? 0
        let secModel = Int32(try headerSeq.readInteger())

        let secParamsRaw = try msgSeq.readOctetBytes()
        let secParams = try UsmSecurityParameters.deserialize(data: secParamsRaw)

        let pduTag = try msgSeq.peekTag()
        let isEnc = (pduTag == ASN1Tag.octetString)
        let scopedData: Data
        if isEnc {
            scopedData = try msgSeq.readOctetBytes()
        } else {
            let len = try msgSeq.readLength()
            scopedData = try msgSeq.readRawBytes(count: len)
        }

        return SNMPv3Message(
            msgID: msgId,
            msgMaxSize: msgMaxSize,
            msgFlags: msgFlags,
            securityModel: secModel,
            securityParameters: secParams,
            scopedPDUData: scopedData,
            isEncrypted: isEnc
        )
    }
}

