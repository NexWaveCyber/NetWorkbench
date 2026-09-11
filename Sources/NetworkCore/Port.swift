import Foundation

/// Represents a TCP or UDP transport layer port number.
public struct NetworkPort: Hashable, Sendable, CustomStringConvertible, ExpressibleByIntegerLiteral {
    public let rawValue: UInt16

    public init(_ rawValue: UInt16) {
        self.rawValue = rawValue
    }

    public init(integerLiteral value: UInt16) {
        self.rawValue = value
    }

    public var description: String {
        "\(rawValue)"
    }

    // Common standard services
    public static let echo: NetworkPort = 7
    public static let ftp: NetworkPort = 21
    public static let ssh: NetworkPort = 22
    public static let telnet: NetworkPort = 23
    public static let smtp: NetworkPort = 25
    public static let dns: NetworkPort = 53
    public static let dhcpServer: NetworkPort = 67
    public static let dhcpClient: NetworkPort = 68
    public static let tftp: NetworkPort = 69
    public static let http: NetworkPort = 80
    public static let ntp: NetworkPort = 123
    public static let snmp: NetworkPort = 161
    public static let snmpTrap: NetworkPort = 162
    public static let bgp: NetworkPort = 179
    public static let ldap: NetworkPort = 389
    public static let https: NetworkPort = 443
    public static let smb: NetworkPort = 445
    public static let syslog: NetworkPort = 514
    public static let ldaps: NetworkPort = 636
    public static let doT: NetworkPort = 853
    public static let httpAlt: NetworkPort = 8080
    public static let httpsAlt: NetworkPort = 8443

    public var serviceName: String? {
        switch self {
        case .ssh: return "SSH"
        case .dns: return "DNS"
        case .http: return "HTTP"
        case .snmp: return "SNMP"
        case .bgp: return "BGP"
        case .https: return "HTTPS"
        case .doT: return "DNS-over-TLS"
        case .httpAlt: return "HTTP-Alt"
        default: return nil
        }
    }
}
