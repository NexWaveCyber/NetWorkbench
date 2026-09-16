import Foundation
import Darwin
import NetworkCore

public final class DNSResolver: Sendable {
    private let dohClient = DoHClient()

    public init() {}

    /// Resolves a hostname using the system resolver and records exact query timing.
    /// For standard internet domains, concurrently performs DoH queries to fetch full record types (A, AAAA, MX, TXT, CNAME),
    /// wire TTLs, and cryptographic DNSSEC validation.
    public func resolve(hostname: String, profile: ResolverProfile = .system) async -> DNSResolutionResult {
        let startTime = DispatchTime.now()

        let isIPLiteral = IPAddress.IPv4(hostname) != nil || IPAddress.IPv6(hostname) != nil
        let isLocal = hostname.lowercased() == "localhost" || hostname.hasSuffix(".local") || isIPLiteral

        // Local or IP addresses: POSIX lookup only
        if isLocal {
            return await resolvePOSIX(hostname: hostname, profile: profile, startTime: startTime)
        }

        // Determine DoH endpoint
        let endpoint: DoHEndpoint
        if profile.id == "google" {
            endpoint = .google
        } else if profile.id == "quad9" {
            endpoint = .quad9
        } else {
            endpoint = .cloudflare
        }

        // Concurrently run POSIX and DoH queries
        async let posixTask = resolvePOSIX(hostname: hostname, profile: profile, startTime: startTime)
        async let aTask = dohClient.resolve(name: hostname, recordType: "A", endpoint: endpoint)
        async let aaaaTask = dohClient.resolve(name: hostname, recordType: "AAAA", endpoint: endpoint)
        async let mxTask = dohClient.resolve(name: hostname, recordType: "MX", endpoint: endpoint)
        async let txtTask = dohClient.resolve(name: hostname, recordType: "TXT", endpoint: endpoint)

        let (posixResult, aRes, aaaaRes, mxRes, txtRes) = await (posixTask, aTask, aaaaTask, mxTask, txtTask)

        // If DoH succeeded, merge rich DNS records
        var combinedRecords: [DNSRecord] = []
        var v4List = posixResult.ipv4Addresses
        var v6List = posixResult.ipv6Addresses
        var isDNSSEC = aRes.isDNSSECValidated || aaaaRes.isDNSSECValidated

        let dohAnswers = aRes.answers + aaaaRes.answers + mxRes.answers + txtRes.answers

        for ans in dohAnswers {
            let recordType: DNSRecordType
            switch ans.type {
            case 1: recordType = .a
            case 28: recordType = .aaaa
            case 5: recordType = .cname
            case 15: recordType = .mx
            case 16: recordType = .txt
            case 2: recordType = .ns
            case 6: recordType = .soa
            case 257: recordType = .caa
            default: continue
            }

            let rec = DNSRecord(
                name: ans.name,
                type: recordType,
                value: ans.data,
                ttl: UInt32(max(0, ans.ttl))
            )

            if !combinedRecords.contains(where: { $0.type == rec.type && $0.value == rec.value }) {
                combinedRecords.append(rec)
            }

            // Extract IPs if not yet present
            if recordType == .a, let v4 = IPAddress.IPv4(ans.data), !v4List.contains(v4) {
                v4List.append(v4)
            } else if recordType == .aaaa, let v6 = IPAddress.IPv6(ans.data), !v6List.contains(v6) {
                v6List.append(v6)
            }
        }

        // If DoH had answers, return enriched result
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000.0
        if !combinedRecords.isEmpty {
            return DNSResolutionResult(
                hostname: hostname,
                resolverName: profile.name,
                records: combinedRecords,
                ipv4Addresses: v4List,
                ipv6Addresses: v6List,
                queryTimeMs: elapsedMs,
                isHealthy: true,
                errorMessage: nil,
                isDNSSECValidated: isDNSSEC
            )
        }

        // Fall back to POSIX results if DoH produced no records (e.g. private enterprise DNS)
        return DNSResolutionResult(
            hostname: hostname,
            resolverName: profile.name,
            records: posixResult.records,
            ipv4Addresses: posixResult.ipv4Addresses,
            ipv6Addresses: posixResult.ipv6Addresses,
            queryTimeMs: elapsedMs,
            isHealthy: posixResult.isHealthy,
            errorMessage: posixResult.errorMessage,
            isDNSSECValidated: false
        )
    }

    private func resolvePOSIX(hostname: String, profile: ResolverProfile, startTime: DispatchTime) async -> DNSResolutionResult {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var hints = addrinfo()
                hints.ai_family = AF_UNSPEC
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
                        errorMessage: errMsg,
                        isDNSSECValidated: false
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
                            records.append(DNSRecord(name: hostname, type: .a, value: v4.description, ttl: 300))
                        }
                    } else if current.pointee.ai_family == AF_INET6 {
                        var sin6 = current.pointee.ai_addr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee }
                        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                        if inet_ntop(AF_INET6, &sin6.sin6_addr, &buffer, socklen_t(INET6_ADDRSTRLEN)) != nil {
                            let str = String(cString: buffer)
                            if let v6 = IPAddress.IPv6(str), !v6List.contains(v6) {
                                v6List.append(v6)
                                records.append(DNSRecord(name: hostname, type: .aaaa, value: v6.description, ttl: 300))
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
                    errorMessage: nil,
                    isDNSSECValidated: false
                ))
            }
        }
    }
}
