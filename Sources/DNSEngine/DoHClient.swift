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

    /// Performs an RFC 8484 DNS-over-HTTPS query using JSON wire protocol.
    public func resolve(name: String, recordType: String = "A", endpoint: DoHEndpoint = .cloudflare) async -> DoHQueryResult {
        let startTime = DispatchTime.now()

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
}
