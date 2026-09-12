import Foundation

public struct WildcardMask: Sendable, Equatable, Hashable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// Initializes a standard inverted wildcard mask from a prefix length (e.g. 24 -> 0.0.0.255).
    public init(prefixLength: Int) {
        let clamped = max(0, min(32, prefixLength))
        let mask = clamped == 0 ? UInt32(0) : (~UInt32(0) << (32 - clamped))
        self.rawValue = ~mask
    }

    /// Initializes from standard dotted-decimal notation (e.g. "0.0.0.255" or "0.0.3.255").
    public init?(_ string: String) {
        let parts = string.split(separator: ".")
        guard parts.count == 4 else { return nil }

        var value: UInt32 = 0
        for part in parts {
            guard let byte = UInt8(part) else { return nil }
            value = (value << 8) | UInt32(byte)
        }
        self.rawValue = value
    }

    /// Dot-decimal representation (e.g. "0.0.0.255").
    public var description: String {
        let b1 = (rawValue >> 24) & 0xFF
        let b2 = (rawValue >> 16) & 0xFF
        let b3 = (rawValue >> 8) & 0xFF
        let b4 = rawValue & 0xFF
        return "\(b1).\(b2).\(b3).\(b4)"
    }

    /// Corresponding standard subnet mask if contiguous.
    public var invertedSubnetMask: String {
        let inv = ~rawValue
        let b1 = (inv >> 24) & 0xFF
        let b2 = (inv >> 16) & 0xFF
        let b3 = (inv >> 8) & 0xFF
        let b4 = inv & 0xFF
        return "\(b1).\(b2).\(b3).\(b4)"
    }

    /// Indicates whether this is a standard contiguous inverted subnet mask.
    public var isContiguous: Bool {
        // For a standard wildcard mask, (rawValue + 1) is a power of 2, i.e. (rawValue + 1) & rawValue == 0
        return ((rawValue &+ 1) & rawValue) == 0
    }

    /// Equivalent standard CIDR prefix length if contiguous.
    public var prefixLength: Int? {
        guard isContiguous else { return nil }
        return 32 - rawValue.nonzeroBitCount
    }

    /// Tests if a candidate IP matches a base IP under this wildcard mask.
    /// In Cisco ACLs: bits where wildcard is 0 MUST match base IP; bits where wildcard is 1 are "don't care".
    public func matches(base: IPAddress.IPv4, candidate: IPAddress.IPv4) -> Bool {
        let careMask = ~rawValue
        return (base.rawValue & careMask) == (candidate.rawValue & careMask)
    }

    /// Binary representation formatted as 4 octets separated by dots.
    public var binaryRepresentation: String {
        let b1 = String((rawValue >> 24) & 0xFF, radix: 2).paddedLeft(toLength: 8, withPad: "0")
        let b2 = String((rawValue >> 16) & 0xFF, radix: 2).paddedLeft(toLength: 8, withPad: "0")
        let b3 = String((rawValue >> 8) & 0xFF, radix: 2).paddedLeft(toLength: 8, withPad: "0")
        let b4 = String(rawValue & 0xFF, radix: 2).paddedLeft(toLength: 8, withPad: "0")
        return "\(b1).\(b2).\(b3).\(b4)"
    }
}

private extension String {
    func paddedLeft(toLength length: Int, withPad pad: Character) -> String {
        let needed = length - count
        guard needed > 0 else { return self }
        return String(repeating: pad, count: needed) + self
    }
}
