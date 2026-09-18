import Foundation

/// Pure-Swift ASN.1 Basic Encoding Rules (BER) codec for SNMP packet serialization and parsing.
public enum ASN1Tag {
    // Universal Tags
    public static let boolean: UInt8 = 0x01
    public static let integer: UInt8 = 0x02
    public static let bitString: UInt8 = 0x03
    public static let octetString: UInt8 = 0x04
    public static let null: UInt8 = 0x05
    public static let objectIdentifier: UInt8 = 0x06
    public static let sequence: UInt8 = 0x30

    // SNMP Application-Specific Tags
    public static let ipAddress: UInt8 = 0x40
    public static let counter32: UInt8 = 0x41
    public static let gauge32: UInt8 = 0x42
    public static let timeTicks: UInt8 = 0x43
    public static let opaque: UInt8 = 0x44
    public static let counter64: UInt8 = 0x46

    // SNMP Context PDU Tags
    public static let getRequest: UInt8 = 0xA0
    public static let getNextRequest: UInt8 = 0xA1
    public static let getResponse: UInt8 = 0xA2
    public static let setRequest: UInt8 = 0xA3
    public static let trapV1: UInt8 = 0xA4
    public static let getBulkRequest: UInt8 = 0xA5
    public static let informRequest: UInt8 = 0xA6
    public static let snmpV2Trap: UInt8 = 0xA7
    public static let report: UInt8 = 0xA8

    // SNMPv2 Exception Tags
    public static let noSuchObject: UInt8 = 0x80
    public static let noSuchInstance: UInt8 = 0x81
    public static let endOfMibView: UInt8 = 0x82
}

public enum ASN1Error: Error, LocalizedError {
    case outOfBounds
    case invalidTag(UInt8)
    case invalidLength
    case invalidOIDFormat
    case integerOverflow

    public var errorDescription: String? {
        switch self {
        case .outOfBounds: return "ASN.1 buffer underflow or out of bounds."
        case .invalidTag(let tag): return "Invalid or unsupported ASN.1 tag: 0x\(String(tag, radix: 16))"
        case .invalidLength: return "Invalid ASN.1 BER length encoding."
        case .invalidOIDFormat: return "Malformed OID string or byte sequence."
        case .integerOverflow: return "Integer value exceeds supported bounds."
        }
    }
}

public struct ASN1Encoder {
    public static func encodeLength(_ length: Int) -> Data {
        if length < 128 {
            return Data([UInt8(length)])
        }
        var temp = length
        var bytes: [UInt8] = []
        while temp > 0 {
            bytes.insert(UInt8(temp & 0xFF), at: 0)
            temp >>= 8
        }
        let firstByte = UInt8(0x80 | bytes.count)
        return Data([firstByte] + bytes)
    }

    public static func encodeInteger(_ value: Int64) -> Data {
        if value == 0 {
            return Data([ASN1Tag.integer, 0x01, 0x00])
        }

        var v = value
        var bytes: [UInt8] = []

        while true {
            bytes.append(UInt8(v & 0xFF))
            v >>= 8
            let lastByte = bytes.last ?? 0
            if v == 0 && (lastByte & 0x80) == 0 {
                break
            }
            if v == -1 && (lastByte & 0x80) != 0 {
                break
            }
        }
        bytes.reverse()

        let len = encodeLength(bytes.count)
        return Data([ASN1Tag.integer]) + len + Data(bytes)
    }

    public static func encodeUnsignedInteger(tag: UInt8, _ value: UInt64) -> Data {
        if value == 0 {
            return Data([tag, 0x01, 0x00])
        }

        var v = value
        var bytes: [UInt8] = []

        while v > 0 {
            bytes.append(UInt8(v & 0xFF))
            v >>= 8
        }
        if let last = bytes.last, (last & 0x80) != 0 {
            bytes.append(0x00)
        }
        bytes.reverse()

        let len = encodeLength(bytes.count)
        return Data([tag]) + len + Data(bytes)
    }

    public static func encodeOctetString(_ string: String) -> Data {
        let utf8 = Data(string.utf8)
        let len = encodeLength(utf8.count)
        return Data([ASN1Tag.octetString]) + len + utf8
    }

    public static func encodeOctetBytes(_ data: Data) -> Data {
        let len = encodeLength(data.count)
        return Data([ASN1Tag.octetString]) + len + data
    }

    public static func encodeNull() -> Data {
        return Data([ASN1Tag.null, 0x00])
    }

    public static func encodeOID(_ oid: String) throws -> Data {
        let cleanOID = oid.hasPrefix(".") ? String(oid.dropFirst()) : oid
        let parts = cleanOID.split(separator: ".").compactMap { UInt32($0) }
        guard parts.count >= 2 else {
            throw ASN1Error.invalidOIDFormat
        }

        var bytes: [UInt8] = []
        // First byte is (X * 40) + Y
        bytes.append(UInt8(parts[0] * 40 + parts[1]))

        for i in 2..<parts.count {
            var sub = parts[i]
            var subBytes: [UInt8] = []
            repeat {
                var byte = UInt8(sub & 0x7F)
                if !subBytes.isEmpty {
                    byte |= 0x80
                }
                subBytes.insert(byte, at: 0)
                sub >>= 7
            } while sub > 0
            bytes.append(contentsOf: subBytes)
        }

        let len = encodeLength(bytes.count)
        return Data([ASN1Tag.objectIdentifier]) + len + Data(bytes)
    }

    public static func encodeSequence(_ content: Data) -> Data {
        let len = encodeLength(content.count)
        return Data([ASN1Tag.sequence]) + len + content
    }

    public static func encodePDU(tag: UInt8, content: Data) -> Data {
        let len = encodeLength(content.count)
        return Data([tag]) + len + content
    }
}

public struct ASN1Decoder {
    private let data: Data
    private var offset: Int = 0

    public init(data: Data) {
        self.data = data
    }

    public var isAtEnd: Bool {
        offset >= data.count
    }

    public mutating func readTag() throws -> UInt8 {
        guard offset < data.count else { throw ASN1Error.outOfBounds }
        let tag = data[offset]
        offset += 1
        return tag
    }

    public mutating func peekTag() throws -> UInt8 {
        guard offset < data.count else { throw ASN1Error.outOfBounds }
        return data[offset]
    }

    public mutating func readLength() throws -> Int {
        guard offset < data.count else { throw ASN1Error.outOfBounds }
        let first = data[offset]
        offset += 1

        if (first & 0x80) == 0 {
            return Int(first)
        }

        let numBytes = Int(first & 0x7F)
        guard numBytes > 0, numBytes <= 4, offset + numBytes <= data.count else {
            throw ASN1Error.invalidLength
        }

        var len = 0
        for _ in 0..<numBytes {
            len = (len << 8) | Int(data[offset])
            offset += 1
        }
        return len
    }

    public mutating func readRawBytes(count: Int) throws -> Data {
        guard offset + count <= data.count else { throw ASN1Error.outOfBounds }
        let slice = data.subdata(in: offset..<(offset + count))
        offset += count
        return slice
    }

    public mutating func readInteger() throws -> Int64 {
        let tag = try readTag()
        guard tag == ASN1Tag.integer else { throw ASN1Error.invalidTag(tag) }
        let len = try readLength()
        let bytes = try readRawBytes(count: len)

        guard !bytes.isEmpty else { return 0 }
        var result: Int64 = (bytes[0] & 0x80) != 0 ? -1 : 0
        for b in bytes {
            result = (result << 8) | Int64(b)
        }
        return result
    }

    public mutating func readUnsignedInteger() throws -> UInt64 {
        _ = try readTag()
        let len = try readLength()
        let bytes = try readRawBytes(count: len)

        var result: UInt64 = 0
        for b in bytes {
            result = (result << 8) | UInt64(b)
        }
        return result
    }

    public mutating func readOctetString() throws -> String {
        let tag = try readTag()
        guard tag == ASN1Tag.octetString || tag == ASN1Tag.ipAddress else {
            throw ASN1Error.invalidTag(tag)
        }
        let len = try readLength()
        let bytes = try readRawBytes(count: len)

        if tag == ASN1Tag.ipAddress, bytes.count == 4 {
            return "\(bytes[0]).\(bytes[1]).\(bytes[2]).\(bytes[3])"
        }
        return String(data: bytes, encoding: .utf8) ?? bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
    }

    public mutating func readOctetBytes() throws -> Data {
        let tag = try readTag()
        guard tag == ASN1Tag.octetString else {
            throw ASN1Error.invalidTag(tag)
        }
        let len = try readLength()
        return try readRawBytes(count: len)
    }

    public mutating func readOID() throws -> String {
        let tag = try readTag()
        guard tag == ASN1Tag.objectIdentifier else { throw ASN1Error.invalidTag(tag) }
        let len = try readLength()
        let bytes = try readRawBytes(count: len)

        guard !bytes.isEmpty else { return "" }

        // First byte has first two components
        var components: [UInt32] = [UInt32(bytes[0] / 40), UInt32(bytes[0] % 40)]
        var current: UInt32 = 0

        for i in 1..<bytes.count {
            let b = bytes[i]
            current = (current << 7) | UInt32(b & 0x7F)
            if (b & 0x80) == 0 {
                components.append(current)
                current = 0
            }
        }

        return components.map(String.init).joined(separator: ".")
    }

    public mutating func enterSequence() throws -> ASN1Decoder {
        let tag = try readTag()
        guard tag == ASN1Tag.sequence else { throw ASN1Error.invalidTag(tag) }
        let len = try readLength()
        let slice = try readRawBytes(count: len)
        return ASN1Decoder(data: slice)
    }

    public mutating func enterPDU() throws -> (tag: UInt8, decoder: ASN1Decoder) {
        let tag = try readTag()
        let len = try readLength()
        let slice = try readRawBytes(count: len)
        return (tag, ASN1Decoder(data: slice))
    }
}
