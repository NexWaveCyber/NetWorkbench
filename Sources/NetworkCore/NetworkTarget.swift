import Foundation

public enum TargetType: String, Sendable, CaseIterable {
    case ipv4 = "IPv4 Address"
    case ipv6 = "IPv6 Address"
    case hostname = "Hostname / FQDN"
    case url = "URL Endpoint"
    case subnet = "IP Subnet / CIDR"
    case device = "Device Name"
}

/// Represents a validated diagnostic target.
public enum NetworkTarget: Hashable, Sendable, CustomStringConvertible {
    case ipv4(IPAddress.IPv4)
    case ipv6(IPAddress.IPv6)
    case hostname(String)
    case url(URL)
    case subnet(IPNetwork)
    case device(String)

    public var description: String {
        displayString
    }

    public var displayString: String {
        switch self {
        case .ipv4(let v4): return v4.description
        case .ipv6(let v6): return v6.description
        case .hostname(let h): return h
        case .url(let u): return u.absoluteString
        case .subnet(let s): return s.description
        case .device(let d): return d
        }
    }

    public var targetType: TargetType {
        switch self {
        case .ipv4: return .ipv4
        case .ipv6: return .ipv6
        case .hostname: return .hostname
        case .url: return .url
        case .subnet: return .subnet
        case .device: return .device
        }
    }

    /// The bare host string to resolve or ping
    public var destinationHost: String {
        switch self {
        case .ipv4(let v4): return v4.description
        case .ipv6(let v6): return v6.description
        case .hostname(let h): return h
        case .url(let u): return u.host ?? u.absoluteString
        case .subnet(let s): return s.networkAddress.description
        case .device(let d): return d
        }
    }

    /// Extracted or inferred default port
    public var defaultPort: NetworkPort {
        switch self {
        case .url(let u):
            if let p = u.port { return NetworkPort(UInt16(p)) }
            return u.scheme?.lowercased() == "http" ? .http : .https
        default:
            return .https
        }
    }
}
