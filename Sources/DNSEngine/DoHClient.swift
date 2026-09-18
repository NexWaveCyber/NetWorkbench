import Foundation

public enum DoHEndpoint: String, CaseIterable, Identifiable, Sendable {
    case cloudflare = "Cloudflare (1.1.1.1)"
    case google = "Google (8.8.8.8)"
    case quad9 = "Quad9 (9.9.9.9)"

    public var id: String { rawValue }

    public var queryURL: String {
        switch self {
        case .cloudflare: return "https://cloudflare-dns.com/dns-query"
        case .google: return "https://dns.google/resolve"
        case .quad9: return "https://dns.quad9.net/dns-query"
        }
    }
}

public struct DoHAnswerRecord: Sendable, Identifiable {
    public var id: String { "\(name)-\(type)-\(data)" }
    public let name: String
    public let type: Int
    public let ttl: Int
    public let data: String

    public var typeName: String {
        switch type {
        case 1: return "A"
        case 28: return "AAAA"
        case 5: return "CNAME"
        case 15: return "MX"
        case 16: return "TXT"
        case 6: return "SOA"
        case 48: return "DNSKEY"
        case 46: return "RRSIG"
        default: return "TYPE\(type)"
        }
    }

    public init(name: String, type: Int, ttl: Int, data: String) {
        self.name = name
        self.type = type
        self.ttl = ttl
        self.data = data
    }
}

public struct DoHQueryResult: Sendable {
    public let hostname: String
    public let endpoint: DoHEndpoint
    public let statusCode: Int // DNS RCODE: 0 = NOERROR, 3 = NXDOMAIN
    public let isDNSSECValidated: Bool // AD (Authenticated Data) flag
    public let answers: [DoHAnswerRecord]
    public let queryTimeMs: Double
    public let isSuccess: Bool
    public let errorMessage: String?

    public var statusName: String {
        switch statusCode {
        case 0: return "NOERROR"
        case 1: return "FORMERR"
        case 2: return "SERVFAIL"
        case 3: return "NXDOMAIN"
        case 4: return "NOTIMP"
        case 5: return "REFUSED"
        default: return "RCODE\(statusCode)"
        }
    }

    public init(
        hostname: String,
        endpoint: DoHEndpoint,
        statusCode: Int,
        isDNSSECValidated: Bool,
        answers: [DoHAnswerRecord],
        queryTimeMs: Double,
        isSuccess: Bool,
        errorMessage: String? = nil
    ) {
        self.hostname = hostname
        self.endpoint = endpoint
        self.statusCode = statusCode
        self.isDNSSECValidated = isDNSSECValidated
        self.answers = answers
        self.queryTimeMs = queryTimeMs
        self.isSuccess = isSuccess
        self.errorMessage = errorMessage
    }
}

public final class DoHClient: Sendable {
    public init() {}

    /// Performs an RFC 8484 DNS-over-HTTPS query supporting both standard binary wireformat and JSON wire protocol.
    public func resolve(name: String, recordType: String = "A", endpoint: DoHEndpoint = .cloudflare) async -> DoHQueryResult {
        let startTime = DispatchTime.now()

        // Quad9 strictly mandates RFC 8484 binary wireformat with ?dns=<base64url>
        if endpoint == .quad9 {
            return await resolveRFC8484(name: name, recordType: recordType, endpoint: endpoint, startTime: startTime)
        }

        guard var components = URLComponents(string: endpoint.queryURL) else {
            return DoHQueryResult(
                hostname: name,
                endpoint: endpoint,
                statusCode: -1,
                isDNSSECValidated: false,
                answers: [],
                queryTimeMs: 0.0,
                isSuccess: false,
                errorMessage: "Invalid endpoint URL"
            )
        }

        components.queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "type", value: recordType)
        ]

        guard let url = components.url else {
            return DoHQueryResult(
                hostname: name,
                endpoint: endpoint,
                statusCode: -1,
                isDNSSECValidated: false,
                answers: [],
                queryTimeMs: 0.0,
                isSuccess: false,
                errorMessage: "Failed to construct query parameters"
            )
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/dns-json", forHTTPHeaderField: "Accept")
        request.setValue("NexWave-Network-Workbench-DoH", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 4.0

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000.0

            guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                return DoHQueryResult(
                    hostname: name,
                    endpoint: endpoint,
                    statusCode: code,
                    isDNSSECValidated: false,
                    answers: [],
                    queryTimeMs: elapsedMs,
                    isSuccess: false,
                    errorMessage: "DoH server HTTP \(code)"
                )
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return DoHQueryResult(
                    hostname: name,
                    endpoint: endpoint,
                    statusCode: -1,
                    isDNSSECValidated: false,
                    answers: [],
                    queryTimeMs: elapsedMs,
                    isSuccess: false,
                    errorMessage: "Failed to parse DNS JSON response"
                )
            }

            let status = json["Status"] as? Int ?? -1
            let adFlag = json["AD"] as? Bool ?? false

            var answers: [DoHAnswerRecord] = []
            if let answerArray = json["Answer"] as? [[String: Any]] {
                for item in answerArray {
                    let aName = item["name"] as? String ?? name
                    let aType = item["type"] as? Int ?? 1
                    let aTTL = item["TTL"] as? Int ?? 0
                    let aData = item["data"] as? String ?? ""
                    answers.append(DoHAnswerRecord(name: aName, type: aType, ttl: aTTL, data: aData))
                }
            }

            return DoHQueryResult(
                hostname: name,
                endpoint: endpoint,
                statusCode: status,
                isDNSSECValidated: adFlag,
                answers: answers,
                queryTimeMs: elapsedMs,
                isSuccess: status == 0
            )
        } catch {
            let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000.0
            return DoHQueryResult(
                hostname: name,
                endpoint: endpoint,
                statusCode: -1,
                isDNSSECValidated: false,
                answers: [],
                queryTimeMs: elapsedMs,
                isSuccess: false,
                errorMessage: error.localizedDescription
            )
        }
    }

    // MARK: - RFC 8484 Binary Wireformat Resolver

    private func resolveRFC8484(name: String, recordType: String, endpoint: DoHEndpoint, startTime: DispatchTime) async -> DoHQueryResult {
        let queryData = buildDNSQueryPacket(name: name, recordType: recordType)
        let b64 = queryData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        guard let url = URL(string: "\(endpoint.queryURL)?dns=\(b64)") else {
            return DoHQueryResult(
                hostname: name,
                endpoint: endpoint,
                statusCode: -1,
                isDNSSECValidated: false,
                answers: [],
                queryTimeMs: 0.0,
                isSuccess: false,
                errorMessage: "Failed to construct RFC 8484 query URL"
            )
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/dns-message", forHTTPHeaderField: "Accept")
        request.setValue("NexWave-Network-Workbench-DoH", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 4.0

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000.0

            guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                return DoHQueryResult(
                    hostname: name,
                    endpoint: endpoint,
                    statusCode: code,
                    isDNSSECValidated: false,
                    answers: [],
                    queryTimeMs: elapsedMs,
                    isSuccess: false,
                    errorMessage: "DoH server HTTP \(code)"
                )
            }

            let parsed = parseWireformatResponse(data: data, originalName: name)
            return DoHQueryResult(
                hostname: name,
                endpoint: endpoint,
                statusCode: parsed.statusCode,
                isDNSSECValidated: parsed.isDNSSEC,
                answers: parsed.answers,
                queryTimeMs: elapsedMs,
                isSuccess: parsed.statusCode == 0
            )
        } catch {
            let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000.0
            return DoHQueryResult(
                hostname: name,
                endpoint: endpoint,
                statusCode: -1,
                isDNSSECValidated: false,
                answers: [],
                queryTimeMs: elapsedMs,
                isSuccess: false,
                errorMessage: error.localizedDescription
            )
        }
    }

    private func buildDNSQueryPacket(name: String, recordType: String) -> Data {
        var data = Data()

        // 1. Transaction ID (2 bytes)
        let txId = UInt16(arc4random_uniform(65535))
        data.append(UInt8((txId >> 8) & 0xFF))
        data.append(UInt8(txId & 0xFF))

        // 2. Flags: 0x0120 (RD = 1, AD = 1 for DNSSEC)
        data.append(0x01)
        data.append(0x20)

        // 3. QDCOUNT: 1 question (2 bytes)
        data.append(0x00)
        data.append(0x01)

        // 4. ANCOUNT: 0 (2 bytes)
        data.append(0x00)
        data.append(0x00)

        // 5. NSCOUNT: 0 (2 bytes)
        data.append(0x00)
        data.append(0x00)

        // 6. ARCOUNT: 0 (2 bytes)
        data.append(0x00)
        data.append(0x00)

        // 7. Question Section: QNAME labels
        let labels = name.split(separator: ".")
        for label in labels {
            let utf8 = Array(label.utf8)
            data.append(UInt8(utf8.count))
            data.append(contentsOf: utf8)
        }
        data.append(0x00) // Root label null terminator

        // 8. QTYPE (2 bytes)
        let qType: UInt16
        switch recordType.uppercased() {
        case "A": qType = 1
        case "NS": qType = 2
        case "CNAME": qType = 5
        case "SOA": qType = 6
        case "MX": qType = 15
        case "TXT": qType = 16
        case "AAAA": qType = 28
        case "CAA": qType = 257
        default: qType = 1
        }
        data.append(UInt8((qType >> 8) & 0xFF))
        data.append(UInt8(qType & 0xFF))

        // 9. QCLASS: 1 (IN) (2 bytes)
        data.append(0x00)
        data.append(0x01)

        return data
    }

    private func parseWireformatResponse(data: Data, originalName: String) -> (statusCode: Int, isDNSSEC: Bool, answers: [DoHAnswerRecord]) {
        guard data.count >= 12 else {
            return (-1, false, [])
        }

        let flags = UInt16(data[2]) << 8 | UInt16(data[3])
        let rcode = Int(flags & 0x000F)
        let isDNSSEC = (flags & 0x0020) != 0
        let qdcount = Int(UInt16(data[4]) << 8 | UInt16(data[5]))
        let ancount = Int(UInt16(data[6]) << 8 | UInt16(data[7]))

        var cursor = 12

        // Skip questions
        for _ in 0..<qdcount {
            cursor = skipDomainName(in: data, from: cursor)
            cursor += 4 // QTYPE (2) + QCLASS (2)
            if cursor > data.count { return (rcode, isDNSSEC, []) }
        }

        var answers: [DoHAnswerRecord] = []

        // Parse answers
        for _ in 0..<ancount {
            guard cursor < data.count else { break }

            let (ansName, nextCursor) = readDomainName(in: data, from: cursor)
            cursor = nextCursor
            guard cursor + 10 <= data.count else { break }

            let rType = Int(UInt16(data[cursor]) << 8 | UInt16(data[cursor + 1]))
            let rTTL = Int(UInt32(data[cursor + 4]) << 24 | UInt32(data[cursor + 5]) << 16 | UInt32(data[cursor + 6]) << 8 | UInt32(data[cursor + 7]))
            let rdLength = Int(UInt16(data[cursor + 8]) << 8 | UInt16(data[cursor + 9]))
            cursor += 10

            guard cursor + rdLength <= data.count else { break }

            let rdataStr: String
            switch rType {
            case 1 where rdLength == 4: // A record IPv4
                rdataStr = "\(data[cursor]).\(data[cursor+1]).\(data[cursor+2]).\(data[cursor+3])"
            case 28 where rdLength == 16: // AAAA record IPv6
                var parts: [String] = []
                for i in stride(from: 0, to: 16, by: 2) {
                    let val = UInt16(data[cursor + i]) << 8 | UInt16(data[cursor + i + 1])
                    parts.append(String(format: "%x", val))
                }
                rdataStr = parts.joined(separator: ":")
            case 5, 2: // CNAME or NS
                let (cname, _) = readDomainName(in: data, from: cursor)
                rdataStr = cname
            case 15 where rdLength >= 3: // MX
                let pref = UInt16(data[cursor]) << 8 | UInt16(data[cursor + 1])
                let (exchange, _) = readDomainName(in: data, from: cursor + 2)
                rdataStr = "\(pref) \(exchange)"
            case 16 where rdLength >= 1: // TXT
                let txtLen = Int(data[cursor])
                if cursor + 1 + txtLen <= data.count {
                    let sub = data.subdata(in: (cursor + 1)..<(cursor + 1 + txtLen))
                    rdataStr = String(data: sub, encoding: .utf8) ?? ""
                } else {
                    rdataStr = ""
                }
            default:
                let sub = data.subdata(in: cursor..<(cursor + rdLength))
                rdataStr = sub.map { String(format: "%02x", $0) }.joined()
            }

            cursor += rdLength
            answers.append(DoHAnswerRecord(
                name: ansName.isEmpty ? originalName : ansName,
                type: rType,
                ttl: rTTL,
                data: rdataStr
            ))
        }

        return (rcode, isDNSSEC, answers)
    }

    private func skipDomainName(in data: Data, from start: Int) -> Int {
        var cursor = start
        while cursor < data.count {
            let length = Int(data[cursor])
            if length == 0 {
                return cursor + 1
            } else if (length & 0xC0) == 0xC0 {
                return cursor + 2
            } else {
                cursor += 1 + length
            }
        }
        return cursor
    }

    private func readDomainName(in data: Data, from start: Int) -> (String, Int) {
        var cursor = start
        var labels: [String] = []
        var jumped = false
        var nextAfterPointer = cursor

        var loopCount = 0
        while cursor < data.count && loopCount < 50 {
            loopCount += 1
            let length = Int(data[cursor])
            if length == 0 {
                if !jumped { nextAfterPointer = cursor + 1 }
                break
            } else if (length & 0xC0) == 0xC0 {
                guard cursor + 1 < data.count else { break }
                let offset = Int(UInt16(length & 0x3F) << 8 | UInt16(data[cursor + 1]))
                if !jumped { nextAfterPointer = cursor + 2 }
                jumped = true
                cursor = offset
            } else {
                cursor += 1
                guard cursor + length <= data.count else { break }
                let sub = data.subdata(in: cursor..<(cursor + length))
                if let str = String(data: sub, encoding: .utf8) {
                    labels.append(str)
                }
                cursor += length
                if !jumped { nextAfterPointer = cursor }
            }
        }

        return (labels.joined(separator: "."), nextAfterPointer)
    }
}

