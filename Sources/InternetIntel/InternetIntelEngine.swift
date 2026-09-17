import Foundation
import NetworkCore

public final class InternetIntelEngine: Sendable {
    public init() {}

    /// Performs comprehensive Internet Intelligence resolution (BGP ASN, announced prefix, RPKI validation).
    public func inspect(target: String) async -> InternetIntelligenceReport {
        let startTime = DispatchTime.now()
        let cleanTarget = target.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanTarget.isEmpty else {
            return InternetIntelligenceReport(
                target: target,
                ipAddress: "",
                asRecord: nil,
                bgpAnnouncement: nil,
                rpkiResult: nil,
                rdapOrgName: nil,
                lookupTimeMs: 0.0,
                isSuccess: false,
                errorMessage: "Empty target provided."
            )
        }

        // Direct ASN query support (e.g. "AS13335" or "15169")
        if cleanTarget.uppercased().hasPrefix("AS") || (Int(cleanTarget) != nil && cleanTarget.count <= 6) {
            let asnInt = Int(cleanTarget.uppercased().replacingOccurrences(of: "AS", with: "")) ?? 0
            if asnInt > 0 {
                let asRecord = await queryASNRecord(asn: asnInt)
                let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000.0
                return InternetIntelligenceReport(
                    target: target,
                    ipAddress: "N/A",
                    asRecord: asRecord,
                    bgpAnnouncement: nil,
                    rpkiResult: nil,
                    rdapOrgName: asRecord?.asName,
                    lookupTimeMs: elapsedMs,
                    isSuccess: asRecord != nil,
                    errorMessage: asRecord == nil ? "Unable to resolve AS\(asnInt) details." : nil
                )
            }
        }

        // Resolve target to IPv4 address if given a hostname
        let ipString: String
        if IPAddress.IPv4(cleanTarget) != nil {
            ipString = cleanTarget
        } else {
            if let resolved = await resolveHostToIPv4(cleanTarget) {
                ipString = resolved
            } else {
                let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000.0
                return InternetIntelligenceReport(
                    target: target,
                    ipAddress: "",
                    asRecord: nil,
                    bgpAnnouncement: nil,
                    rpkiResult: nil,
                    rdapOrgName: nil,
                    lookupTimeMs: elapsedMs,
                    isSuccess: false,
                    errorMessage: "Failed to resolve hostname '\(cleanTarget)' to an IPv4 address."
                )
            }
        }

        // 1. Query Origin ASN via Team Cymru DNS
        let bgpAnnouncement = await queryOriginASN(ip: ipString)

        var asRecord: ASRecord? = nil
        var rpkiResult: RPKIValidationResult? = nil

        if let bgp = bgpAnnouncement {
            // 2. Query ASN metadata
            asRecord = await queryASNRecord(asn: bgp.originASN)

            // 3. Query RPKI Validation via RIPE Stat
            rpkiResult = await validateRPKI(asn: bgp.originASN, prefix: bgp.prefix)
        }

        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000.0

        return InternetIntelligenceReport(
            target: cleanTarget,
            ipAddress: ipString,
            asRecord: asRecord,
            bgpAnnouncement: bgpAnnouncement,
            rpkiResult: rpkiResult,
            rdapOrgName: asRecord?.asName,
            lookupTimeMs: elapsedMs,
            isSuccess: bgpAnnouncement != nil,
            errorMessage: bgpAnnouncement == nil ? "No public BGP route announcement found for \(ipString)." : nil
        )
    }

    /// Fast BGP ASN resolution for a route hop IP address via Team Cymru DNS.
    public func resolveASN(ip: String, hopNumber: Int = 0) async -> (asn: String?, asName: String?) {
        let isPrivate = ip.starts(with: "192.168.") || ip.starts(with: "10.") || ip.starts(with: "172.16.") || ip.starts(with: "172.31.") || ip == "127.0.0.1" || ip == "::1"
        if isPrivate {
            return (nil, hopNumber == 1 ? "Default Gateway" : "Private Subnet")
        }

        // Fast static prefixes for high-frequency cloud roots
        if ip.starts(with: "1.1.1") || ip.starts(with: "1.0.0") {
            return ("AS13335", "Cloudflare")
        } else if ip.starts(with: "8.8.") || ip.starts(with: "142.250.") || ip.starts(with: "172.217.") {
            return ("AS15169", "Google")
        } else if ip.starts(with: "140.82.") || ip.starts(with: "20.205.") {
            return ("AS36459", "GitHub / Microsoft")
        } else if ip.starts(with: "9.9.9") || ip.starts(with: "149.112.") {
            return ("AS19281", "Quad9")
        }

        if let bgp = await queryOriginASN(ip: ip) {
            let formattedASN = "AS\(bgp.originASN)"
            if let asRec = await queryASNRecord(asn: bgp.originASN) {
                return (formattedASN, asRec.asName)
            }
            return (formattedASN, bgp.registry)
        }

        return (nil, "Transit Provider")
    }

    // MARK: - DNS Helpers (Team Cymru)

    private func resolveHostToIPv4(_ host: String) async -> String? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var hints = addrinfo()
                hints.ai_family = AF_INET
                hints.ai_socktype = SOCK_STREAM
                var res: UnsafeMutablePointer<addrinfo>?
                guard getaddrinfo(host, nil, &hints, &res) == 0, let head = res else {
                    continuation.resume(returning: nil)
                    return
                }
                defer { freeaddrinfo(head) }
                let sin = head.pointee.ai_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                var addr = sin.sin_addr
                if inet_ntop(AF_INET, &addr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil {
                    continuation.resume(returning: String(cString: buffer))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func queryOriginASN(ip: String) async -> BGPAnnouncement? {
        let octets = ip.split(separator: ".")
        guard octets.count == 4 else { return nil }
        let reversedIP = octets.reversed().joined(separator: ".")
        let queryHost = "\(reversedIP).origin.asn.cymru.com"

        guard let txt = await queryTXTRecord(queryHost) else { return nil }
        // Format: "13335 | 1.1.1.0/24 | AU | apnic | 2011-08-11"
        let parts = txt.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 5, let asn = Int(parts[0]) else { return nil }

        return BGPAnnouncement(
            prefix: parts[1],
            originASN: asn,
            registry: parts[3],
            countryCode: parts[2],
            allocationDate: parts[4]
        )
    }

    private func queryASNRecord(asn: Int) async -> ASRecord? {
        let queryHost = "AS\(asn).asn.cymru.com"
        guard let txt = await queryTXTRecord(queryHost) else { return nil }
        // Format: "13335 | US | arin | 2010-07-14 | CLOUDFLARENET - Cloudflare, Inc., US"
        let parts = txt.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 5 else { return nil }

        return ASRecord(
            asn: asn,
            asName: parts[4],
            countryCode: parts[1],
            registry: parts[2],
            allocatedDate: parts[3]
        )
    }

    private func queryTXTRecord(_ hostname: String) async -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/dig")
        task.arguments = ["+short", "TXT", hostname]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        guard let raw = String(data: data, encoding: .utf8) else { return nil }
        let lines = raw.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let first = lines.first else { return nil }
        return first.replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespaces)
    }

    // MARK: - RPKI Validation (RIPE Stat)

    private func validateRPKI(asn: Int, prefix: String) async -> RPKIValidationResult {
        guard let encodedPrefix = prefix.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://stat.ripe.net/data/rpki-validation/data.json?resource=\(asn)&prefix=\(encodedPrefix)") else {
            return RPKIValidationResult(status: .unknown, originASN: asn, prefix: prefix, explanation: "Invalid RPKI query URL")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 4.0
        request.setValue("NexWave-Network-Workbench", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
                return RPKIValidationResult(status: .unknown, originASN: asn, prefix: prefix, explanation: "RIR RPKI validation server returned HTTP error")
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataObj = json["data"] as? [String: Any],
               let statusStr = dataObj["status"] as? String {
                let status: RPKIValidationStatus
                switch statusStr.lowercased() {
                case "valid": status = .valid
                case "invalid": status = .invalid
                case "not_found": status = .notFound
                default: status = .unknown
                }

                let validator = dataObj["validator"] as? String ?? "routinator"
                let explanation: String
                switch status {
                case .valid:
                    explanation = "Valid Route Origin Authorization (ROA) cryptographically matches origin AS\(asn) and prefix \(prefix)."
                case .invalid:
                    explanation = "Cryptographic mismatch! Prefix \(prefix) is announced by AS\(asn) but conflicting ROA exists in RPKI repository."
                case .notFound:
                    explanation = "No ROA signed for prefix \(prefix). Vulnerable to BGP route hijacking."
                case .unknown:
                    explanation = "RPKI repository status could not be verified."
                }

                return RPKIValidationResult(status: status, originASN: asn, prefix: prefix, validator: validator, explanation: explanation)
            }
        } catch {
            return RPKIValidationResult(status: .unknown, originASN: asn, prefix: prefix, explanation: "RPKI lookup timed out or network offline")
        }

        return RPKIValidationResult(status: .unknown, originASN: asn, prefix: prefix, explanation: "Inconclusive response from validator")
    }
}
