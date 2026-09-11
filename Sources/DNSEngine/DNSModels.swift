import Foundation
import NetworkCore

public enum DNSRecordType: String, Sendable, CaseIterable {
    case a = "A"
    case aaaa = "AAAA"
    case cname = "CNAME"
    case mx = "MX"
    case txt = "TXT"
    case ptr = "PTR"
    case ns = "NS"
    case soa = "SOA"
    case srv = "SRV"
    case caa = "CAA"
}

public struct DNSRecord: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let type: DNSRecordType
    public let value: String
    public let ttl: UInt32

    public init(name: String, type: DNSRecordType, value: String, ttl: UInt32 = 300) {
        self.id = "\(name)_\(type.rawValue)_\(value)"
        self.name = name
        self.type = type
        self.value = value
        self.ttl = ttl
    }
}

public struct ResolverProfile: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let addresses: [String]
    public let supportsDoH: Bool
    public let dohURL: String?

    public static let system = ResolverProfile(
        id: "system",
        name: "System Default",
        addresses: [],
        supportsDoH: false,
        dohURL: nil
    )

    public static let cloudflare = ResolverProfile(
        id: "cloudflare",
        name: "Cloudflare (1.1.1.1)",
        addresses: ["1.1.1.1", "1.0.0.1", "2606:4700:4700::1111"],
        supportsDoH: true,
        dohURL: "https://cloudflare-dns.com/dns-query"
    )

    public static let google = ResolverProfile(
        id: "google",
        name: "Google (8.8.8.8)",
        addresses: ["8.8.8.8", "8.8.4.4", "2001:4860:4860::8888"],
        supportsDoH: true,
        dohURL: "https://dns.google/resolve"
    )

    public static let quad9 = ResolverProfile(
        id: "quad9",
        name: "Quad9 (9.9.9.9)",
        addresses: ["9.9.9.9", "149.112.112.112", "2620:fe::fe"],
        supportsDoH: true,
        dohURL: "https://dns.quad9.net/dns-query"
    )
}

public struct DNSResolutionResult: Sendable {
    public let hostname: String
    public let resolverName: String
    public let records: [DNSRecord]
    public let ipv4Addresses: [IPAddress.IPv4]
    public let ipv6Addresses: [IPAddress.IPv6]
    public let queryTimeMs: Double
    public let isHealthy: Bool
    public let errorMessage: String?

    public init(
        hostname: String,
        resolverName: String,
        records: [DNSRecord],
        ipv4Addresses: [IPAddress.IPv4],
        ipv6Addresses: [IPAddress.IPv6],
        queryTimeMs: Double,
        isHealthy: Bool,
        errorMessage: String? = nil
    ) {
        self.hostname = hostname
        self.resolverName = resolverName
        self.records = records
        self.ipv4Addresses = ipv4Addresses
        self.ipv6Addresses = ipv6Addresses
        self.queryTimeMs = queryTimeMs
        self.isHealthy = isHealthy
        self.errorMessage = errorMessage
    }
}
