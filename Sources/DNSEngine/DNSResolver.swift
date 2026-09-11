import Foundation
import Darwin
import NetworkCore

public final class DNSResolver: Sendable {
    public init() {}

    /// Resolves a hostname using the system resolver and records exact query timing.
    public func resolve(hostname: String, profile: ResolverProfile = .system) async -> DNSResolutionResult {
        let startTime = DispatchTime.now()

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var hints = addrinfo()
                hints.ai_family = AF_UNSPEC // IPv4 and IPv6
                hints.ai_socktype = SOCK_STREAM

                var res: UnsafeMutablePointer<addrinfo>?
                let status = getaddrinfo(hostname, nil, &hints, &res)
                let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000.0

                guard status == 0, let head = res else {
                    let errMsg = String(cString: gai_strerror(status))
                    continuation.resume(returning: DNSResolutionResult(
                        hostname: hostname,
                        resolverName: profile.name,
                        records: [],
                        ipv4Addresses: [],
                        ipv6Addresses: [],
                        queryTimeMs: elapsedMs,
                        isHealthy: false,
                        errorMessage: errMsg
                    ))
                    return
                }

                defer { freeaddrinfo(head) }

                var v4List: [IPAddress.IPv4] = []
                var v6List: [IPAddress.IPv6] = []
                var records: [DNSRecord] = []

                var ptr: UnsafeMutablePointer<addrinfo>? = head
                while let current = ptr {
                    if current.pointee.ai_family == AF_INET {
                        let sin = current.pointee.ai_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                        let raw = UInt32(bigEndian: sin.sin_addr.s_addr)
                        let v4 = IPAddress.IPv4(rawValue: raw)
                        if !v4List.contains(v4) {
                            v4List.append(v4)
                            records.append(DNSRecord(name: hostname, type: .a, value: v4.description))
                        }
                    } else if current.pointee.ai_family == AF_INET6 {
                        var sin6 = current.pointee.ai_addr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee }
                        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                        if inet_ntop(AF_INET6, &sin6.sin6_addr, &buffer, socklen_t(INET6_ADDRSTRLEN)) != nil {
                            let str = String(cString: buffer)
                            if let v6 = IPAddress.IPv6(str), !v6List.contains(v6) {
                                v6List.append(v6)
                                records.append(DNSRecord(name: hostname, type: .aaaa, value: v6.description))
                            }
                        }
                    }
                    ptr = current.pointee.ai_next
                }

                continuation.resume(returning: DNSResolutionResult(
                    hostname: hostname,
                    resolverName: profile.name,
                    records: records,
                    ipv4Addresses: v4List,
                    ipv6Addresses: v6List,
                    queryTimeMs: elapsedMs,
                    isHealthy: !records.isEmpty,
                    errorMessage: nil
                ))
            }
        }
    }
}
