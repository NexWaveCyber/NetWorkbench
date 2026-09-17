import Foundation
import Darwin

/// Represents an Internet Protocol address (IPv4 or IPv6).
public enum IPAddress: Hashable, Sendable, CustomStringConvertible, Comparable {
    case v4(IPv4)
    case v6(IPv6)

    public init?(_ string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let unzoned = trimmed.components(separatedBy: "%").first ?? trimmed
        if let v4 = IPv4(unzoned) {
            self = .v4(v4)
        } else if let v6 = IPv6(unzoned) {
            self = .v6(v6)
        } else {
            return nil
        }
    }

    public var description: String {
        switch self {
        case .v4(let v4): return v4.description
        case .v6(let v6): return v6.description
        }
    }

    public var isIPv4: Bool {
        if case .v4 = self { return true }
        return false
    }

    public var isIPv6: Bool {
        if case .v6 = self { return true }
        return false
    }

    public var isPrivate: Bool {
        switch self {
        case .v4(let v4): return v4.isPrivate
        case .v6(let v6): return v6.isPrivate
        }
    }

    public var isLoopback: Bool {
        switch self {
        case .v4(let v4): return v4.isLoopback
        case .v6(let v6): return v6.isLoopback
        }
    }

    public var isLinkLocal: Bool {
        switch self {
        case .v4(let v4): return v4.isLinkLocal
        case .v6(let v6): return v6.isLinkLocal
        }
    }

    /// True if this is a routable or unique IPv6 address (Global Unicast 2000::/3 or ULA fc00::/7).
    public var isUniqueIPv6: Bool {
        switch self {
        case .v4: return false
        case .v6(let v6): return v6.isUniqueIPv6
        }
    }

    public var isCarrierGradeNAT: Bool {
        switch self {
        case .v4(let v4): return v4.isCarrierGradeNAT
        case .v6: return false
        }
    }

    public static func < (lhs: IPAddress, rhs: IPAddress) -> Bool {
        switch (lhs, rhs) {
        case (.v4(let a), .v4(let b)): return a < b
        case (.v6(let a), .v6(let b)): return a < b
        case (.v4, .v6): return true
        case (.v6, .v4): return false
        }
    }

    // MARK: - IPv4 Structure
    public struct IPv4: Hashable, Sendable, CustomStringConvertible, Comparable {
        public let rawValue: UInt32 // stored in host byte order

        public init(rawValue: UInt32) {
            self.rawValue = rawValue
        }

        public init?(octets: (UInt8, UInt8, UInt8, UInt8)) {
            self.rawValue = (UInt32(octets.0) << 24) |
                            (UInt32(octets.1) << 16) |
                            (UInt32(octets.2) << 8) |
                            UInt32(octets.3)
        }

        public init?(_ string: String) {
            var sin = in_addr()
            guard string.withCString({ inet_pton(AF_INET, $0, &sin) }) == 1 else {
                return nil
            }
            self.rawValue = UInt32(bigEndian: sin.s_addr)
        }

        public var octets: (UInt8, UInt8, UInt8, UInt8) {
            (
                UInt8((rawValue >> 24) & 0xFF),
                UInt8((rawValue >> 16) & 0xFF),
                UInt8((rawValue >> 8) & 0xFF),
                UInt8(rawValue & 0xFF)
            )
        }

        public var description: String {
            let o = octets
            return "\(o.0).\(o.1).\(o.2).\(o.3)"
        }

        /// RFC 1918 Private Addresses:
        /// 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16
        public var isPrivate: Bool {
            let o = octets
            if o.0 == 10 { return true }
            if o.0 == 172 && (o.1 >= 16 && o.1 <= 31) { return true }
            if o.0 == 192 && o.1 == 168 { return true }
            return false
        }

        /// RFC 1122 Loopback: 127.0.0.0/8
        public var isLoopback: Bool {
            octets.0 == 127
        }

        /// RFC 3927 Link Local: 169.254.0.0/16
        public var isLinkLocal: Bool {
            octets.0 == 169 && octets.1 == 254
        }

        /// RFC 6598 Carrier-Grade NAT (CGN): 100.64.0.0/10
        public var isCarrierGradeNAT: Bool {
            let o = octets
            return o.0 == 100 && (o.1 >= 64 && o.1 <= 127)
        }

        public static func < (lhs: IPv4, rhs: IPv4) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    // MARK: - IPv6 Structure
    public struct IPv6: Hashable, Sendable, CustomStringConvertible, Comparable {
        public let high64: UInt64
        public let low64: UInt64

        public init(high64: UInt64, low64: UInt64) {
            self.high64 = high64
            self.low64 = low64
        }

        public init?(_ string: String) {
            let clean = string.components(separatedBy: "%").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? string
            var sin6 = in6_addr()
            guard clean.withCString({ inet_pton(AF_INET6, $0, &sin6) }) == 1 else {
                return nil
            }
            let (h, l) = withUnsafeBytes(of: &sin6) { ptr -> (UInt64, UInt64) in
                let p = ptr.bindMemory(to: UInt64.self)
                return (UInt64(bigEndian: p[0]), UInt64(bigEndian: p[1]))
            }
            self.high64 = h
            self.low64 = l
        }

        public var bytes: [UInt8] {
            var result = [UInt8](repeating: 0, count: 16)
            let h = high64.bigEndian
            let l = low64.bigEndian
            withUnsafeBytes(of: h) { hPtr in
                for i in 0..<8 { result[i] = hPtr[i] }
            }
            withUnsafeBytes(of: l) { lPtr in
                for i in 0..<8 { result[8 + i] = lPtr[i] }
            }
            return result
        }

        public var description: String {
            var sin6 = in6_addr()
            let h = high64.bigEndian
            let l = low64.bigEndian
            withUnsafeMutableBytes(of: &sin6) { ptr in
                let p = ptr.bindMemory(to: UInt64.self)
                p[0] = h
                p[1] = l
            }
            var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            guard inet_ntop(AF_INET6, &sin6, &buffer, socklen_t(INET6_ADDRSTRLEN)) != nil else {
                return "::"
            }
            let nulIndex = buffer.firstIndex(of: 0) ?? buffer.count
            return buffer[..<nulIndex].withUnsafeBufferPointer { ptr in
                String(decoding: ptr.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            }
        }

        /// RFC 4193 Unique Local Address (fc00::/7)
        public var isPrivate: Bool {
            let firstByte = UInt8((high64 >> 56) & 0xFF)
            return (firstByte & 0xFE) == 0xFC
        }

        /// ::1/128 Loopback
        public var isLoopback: Bool {
            high64 == 0 && low64 == 1
        }

        /// RFC 4291 Link-Local (fe80::/10)
        public var isLinkLocal: Bool {
            let prefix = UInt16((high64 >> 48) & 0xFFFF)
            return (prefix & 0xFFC0) == 0xFE80
        }

        /// RFC 3587 / RFC 4291 Global Unicast Address (2000::/3)
        public var isGlobalUnicast: Bool {
            let firstByte = UInt8((high64 >> 56) & 0xFF)
            return (firstByte & 0xE0) == 0x20
        }

        /// Unique IPv6 Address: Global Unicast (2000::/3) or Unique Local Address (fc00::/7, RFC 4193).
        /// Excludes Link-Local (fe80::/10), Loopback (::1), Multicast (ff00::/8), and Unspecified (::).
        public var isUniqueIPv6: Bool {
            if isLinkLocal || isLoopback { return false }
            let firstByte = UInt8((high64 >> 56) & 0xFF)
            if firstByte == 0xFF { return false } // Multicast
            return isGlobalUnicast || isPrivate
        }

        public static func < (lhs: IPv6, rhs: IPv6) -> Bool {
            if lhs.high64 != rhs.high64 {
                return lhs.high64 < rhs.high64
            }
            return lhs.low64 < rhs.low64
        }
    }
}
