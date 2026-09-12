import Foundation

/// Represents an IPv4 or IPv6 subnet with CIDR prefix.
public struct IPNetwork: Hashable, Sendable, CustomStringConvertible {
    public let address: IPAddress
    public let prefixLength: Int

    public init?(address: IPAddress, prefixLength: Int) {
        switch address {
        case .v4:
            guard prefixLength >= 0 && prefixLength <= 32 else { return nil }
        case .v6:
            guard prefixLength >= 0 && prefixLength <= 128 else { return nil }
        }
        self.address = address
        self.prefixLength = prefixLength
    }

    public init?(_ cidrString: String) {
        let parts = cidrString.split(separator: "/")
        guard parts.count == 2,
              let addr = IPAddress(String(parts[0])),
              let prefix = Int(parts[1]) else {
            return nil
        }
        self.init(address: addr, prefixLength: prefix)
    }

    public var description: String {
        "\(networkAddress)/\(prefixLength)"
    }

    public var isIPv4: Bool { address.isIPv4 }
    public var isIPv6: Bool { address.isIPv6 }

    // MARK: - IPv4 Subnet Math
    public var ipv4Netmask: IPAddress.IPv4? {
        guard case .v4 = address else { return nil }
        if prefixLength == 0 { return IPAddress.IPv4(rawValue: 0) }
        let mask = UInt32.max << (32 - prefixLength)
        return IPAddress.IPv4(rawValue: mask)
    }

    public var ipv4WildcardMask: IPAddress.IPv4? {
        guard let mask = ipv4Netmask else { return nil }
        return IPAddress.IPv4(rawValue: ~mask.rawValue)
    }

    public var ipv4Address: IPAddress.IPv4? {
        guard case .v4(let v) = address else { return nil }
        return v
    }

    public var ipv4NetworkAddress: IPAddress.IPv4? {
        guard case .v4(let v) = networkAddress else { return nil }
        return v
    }

    public var ipv4BroadcastAddress: IPAddress.IPv4? {
        guard let bcast = broadcastAddress, case .v4(let v) = bcast else { return nil }
        return v
    }

    public var networkAddress: IPAddress {
        switch address {
        case .v4(let v4):
            guard let mask = ipv4Netmask else { return address }
            let net = v4.rawValue & mask.rawValue
            return .v4(IPAddress.IPv4(rawValue: net))
        case .v6:
            // IPv6 network calculation
            return address
        }
    }

    public var broadcastAddress: IPAddress? {
        switch address {
        case .v4(let v4):
            guard let mask = ipv4Netmask else { return nil }
            let net = v4.rawValue & mask.rawValue
            let bcast = net | (~mask.rawValue)
            return .v4(IPAddress.IPv4(rawValue: bcast))
        case .v6:
            return nil // IPv6 does not use broadcast
        }
    }

    /// Usable host count:
    /// /32 -> 1 host (RFC 1122)
    /// /31 -> 2 hosts (RFC 3021 Point-to-Point)
    /// /30 and below -> (2^(32-prefix)) - 2
    public var usableHostCount: UInt64 {
        switch address {
        case .v4:
            if prefixLength == 32 { return 1 }
            if prefixLength == 31 { return 2 }
            let total = UInt64(1) << (32 - prefixLength)
            return total >= 2 ? total - 2 : 0
        case .v6:
            if prefixLength >= 127 {
                return prefixLength == 128 ? 1 : 2
            }
            return UInt64.max // Practical approximation for large v6 prefixes
        }
    }

    public var firstUsableAddress: IPAddress? {
        guard case .v4(let v4) = networkAddress else { return nil }
        if prefixLength == 32 || prefixLength == 31 {
            return .v4(v4)
        }
        return .v4(IPAddress.IPv4(rawValue: v4.rawValue + 1))
    }

    public var lastUsableAddress: IPAddress? {
        guard case .v4 = networkAddress,
              let bcast = broadcastAddress,
              case .v4(let bcastV4) = bcast else { return nil }
        if prefixLength == 32 {
            return networkAddress
        }
        if prefixLength == 31 {
            return bcast
        }
        return .v4(IPAddress.IPv4(rawValue: bcastV4.rawValue - 1))
    }

    public func contains(_ ip: IPAddress) -> Bool {
        switch (address, ip) {
        case (.v4, .v4(let testV4)):
            guard let mask = ipv4Netmask,
                  case .v4(let netV4) = networkAddress else { return false }
            return (testV4.rawValue & mask.rawValue) == netV4.rawValue
        case (.v6, .v6):
            return false // Simplified for v1
        default:
            return false
        }
    }
}
