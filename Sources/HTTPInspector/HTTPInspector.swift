import Foundation
import Network
import NetworkCore
import Security

private func formatCipherSuite(_ c: tls_ciphersuite_t?) -> String? {
    guard let c = c else { return nil }
    let raw = c.rawValue
    let suites: [UInt16: String] = [
        0x1301: "TLS_AES_128_GCM_SHA256",
        0x1302: "TLS_AES_256_GCM_SHA384",
        0x1303: "TLS_CHACHA20_POLY1305_SHA256",
        0x1304: "TLS_AES_128_CCM_SHA256",
        0x1305: "TLS_AES_128_CCM_8_SHA256",
        0xC02F: "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256",
        0xC030: "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384",
        0xC02B: "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256",
        0xC02C: "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384",
        0xCCA8: "TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256",
        0xCCA9: "TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256",
        0x009C: "TLS_RSA_WITH_AES_128_GCM_SHA256",
        0x009D: "TLS_RSA_WITH_AES_256_GCM_SHA384",
        0xC013: "TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA",
        0xC014: "TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA",
        0xC009: "TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA",
        0xC00A: "TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA"
    ]
    if let name = suites[raw] {
        return name
    }
    return String(format: "0x%04X", raw)
}

private func formatProtocolVersion(_ v: tls_protocol_version_t?) -> String? {
    guard let v = v else { return nil }
    switch v.rawValue {
    case 0x0301: return "TLS 1.0"
    case 0x0302: return "TLS 1.1"
    case 0x0303: return "TLS 1.2"
    case 0x0304: return "TLS 1.3"
    case 0xFEFF: return "DTLS 1.0"
    case 0xFEFD: return "DTLS 1.2"
    default: return String(format: "TLS (0x%04X)", v.rawValue)
    }
}

private final class MetricsCollector: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    var collectedMetrics: URLSessionTaskMetrics?
    var certInfo: TLSCertificateInfo?
    private let lock = NSLock()

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        lock.lock()
        defer { lock.unlock() }
        self.collectedMetrics = metrics

        if let trans = metrics.transactionMetrics.first, let current = self.certInfo {
            let cipher = formatCipherSuite(trans.negotiatedTLSCipherSuite) ?? current.cipherSuite
            let proto = formatProtocolVersion(trans.negotiatedTLSProtocolVersion) ?? current.protocolVersion
            self.certInfo = TLSCertificateInfo(
                subjectSummary: current.subjectSummary,
                issuerSummary: current.issuerSummary,
                expirationDate: current.expirationDate,
                daysUntilExpiry: current.daysUntilExpiry,
                isExpired: current.isExpired,
                cipherSuite: cipher,
                protocolVersion: proto
            )
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if let trust = challenge.protectionSpace.serverTrust {
            var error: CFError?
            let isValid = SecTrustEvaluateWithError(trust, &error)

            if let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let cert = chain.first {
                let subject = SecCertificateCopySubjectSummary(cert) as String? ?? "Unknown Subject"
                let issuer = chain.count > 1 ? (SecCertificateCopySubjectSummary(chain[1]) as String? ?? "Unknown CA") : subject

                var expiryDate: Date? = nil
                if let values = SecCertificateCopyValues(cert, [kSecOIDX509V1ValidityNotAfter] as CFArray, nil) as? [CFString: [CFString: Any]],
                   let notAfterDict = values[kSecOIDX509V1ValidityNotAfter] {
                    if let num = notAfterDict[kSecPropertyKeyValue] as? NSNumber {
                        // Darwin Security framework returns CFAbsoluteTime (seconds since Jan 1 2001 00:00:00 UTC) as NSNumber
                        expiryDate = Date(timeIntervalSinceReferenceDate: num.doubleValue)
                    } else if let d = notAfterDict[kSecPropertyKeyValue] as? Double {
                        expiryDate = Date(timeIntervalSinceReferenceDate: d)
                    } else if let dateVal = notAfterDict[kSecPropertyKeyValue] as? Date {
                        expiryDate = dateVal
                    }
                }

                var daysRemaining: Int? = nil
                var isExpired = false
                if let expiry = expiryDate {
                    let diff = Calendar.current.dateComponents([.day], from: Date(), to: expiry).day
                    daysRemaining = diff
                    isExpired = expiry < Date()
                }

                self.lock.lock()
                self.certInfo = TLSCertificateInfo(
                    subjectSummary: subject,
                    issuerSummary: issuer,
                    expirationDate: expiryDate,
                    daysUntilExpiry: daysRemaining,
                    isExpired: isExpired || !isValid,
                    cipherSuite: challenge.protectionSpace.protocol,
                    protocolVersion: challenge.protectionSpace.protocol
                )
                self.lock.unlock()
            }
        }
        completionHandler(.performDefaultHandling, nil)
    }
}

public final class HTTPInspector: Sendable {
    public init() {}

    /// Inspects an HTTP/HTTPS endpoint and measures performance stages and certificate health.
    public func inspect(targetHost: String, port: NetworkPort = .https, useHTTPS: Bool = true) async -> HTTPObservation {
        let scheme = useHTTPS ? "https" : "http"
        let isDefaultPort = (useHTTPS && port.rawValue == 443) || (!useHTTPS && port.rawValue == 80)
        let formattedHost = targetHost.contains(":") && !targetHost.hasPrefix("[") ? "[\(targetHost)]" : targetHost
        let portSuffix = isDefaultPort ? "" : ":\(port.rawValue)"
        let urlStr = "\(scheme)://\(formattedHost)\(portSuffix)"

        guard let url = URL(string: urlStr) else {
            return HTTPObservation(
                url: URL(string: "http://invalid")!,
                statusCode: 0,
                httpVersion: nil,
                redirectURL: nil,
                headers: [:],
                dnsTimeMs: nil,
                connectTimeMs: nil,
                tlsTimeMs: nil,
                ttfbMs: nil,
                totalTimeMs: 0,
                certificateInfo: nil,
                isHealthy: false,
                errorMessage: "Invalid URL string: \(urlStr)"
            )
        }

        let collector = MetricsCollector()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5.0
        config.timeoutIntervalForResource = 8.0
        let session = URLSession(configuration: config, delegate: collector, delegateQueue: nil)

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("NexWave-Network-Workbench/1.0", forHTTPHeaderField: "User-Agent")

        let startTime = DispatchTime.now()

        do {
            let (data, response) = try await session.data(for: request)
            _ = data // consume
            let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000.0

            guard let httpResponse = response as? HTTPURLResponse else {
                return HTTPObservation(
                    url: url,
                    statusCode: 0,
                    httpVersion: nil,
                    redirectURL: nil,
                    headers: [:],
                    dnsTimeMs: nil,
                    connectTimeMs: nil,
                    tlsTimeMs: nil,
                    ttfbMs: nil,
                    totalTimeMs: elapsedMs,
                    certificateInfo: nil,
                    isHealthy: false,
                    errorMessage: "Non-HTTP response received"
                )
            }

            var dnsMs: Double? = nil
            var connectMs: Double? = nil
            var tlsMs: Double? = nil
            var ttfbMs: Double? = nil

            if let trans = collector.collectedMetrics?.transactionMetrics.first {
                if let dStart = trans.domainLookupStartDate, let dEnd = trans.domainLookupEndDate {
                    dnsMs = dEnd.timeIntervalSince(dStart) * 1000.0
                }
                if let cStart = trans.connectStartDate, let cEnd = trans.connectEndDate {
                    connectMs = cEnd.timeIntervalSince(cStart) * 1000.0
                }
                if let sStart = trans.secureConnectionStartDate, let sEnd = trans.secureConnectionEndDate {
                    tlsMs = sEnd.timeIntervalSince(sStart) * 1000.0
                }
                if let reqStart = trans.requestStartDate, let resStart = trans.responseStartDate {
                    ttfbMs = resStart.timeIntervalSince(reqStart) * 1000.0
                }
            }

            var headersDict: [String: String] = [:]
            for (k, v) in httpResponse.allHeaderFields {
                headersDict["\(k)"] = "\(v)"
            }

            let isHealthy = (200...399).contains(httpResponse.statusCode)

            let httpVersion: String = {
                if let proto = collector.collectedMetrics?.transactionMetrics.first?.networkProtocolName {
                    switch proto.lowercased() {
                    case "h2": return "HTTP/2"
                    case "h3": return "HTTP/3"
                    case "http/1.1": return "HTTP/1.1"
                    case "http/1.0": return "HTTP/1.0"
                    default: return proto.uppercased()
                    }
                }
                return "HTTP/1.1"
            }()

            return HTTPObservation(
                url: url,
                statusCode: httpResponse.statusCode,
                httpVersion: httpVersion,
                redirectURL: nil,
                headers: headersDict,
                dnsTimeMs: dnsMs,
                connectTimeMs: connectMs,
                tlsTimeMs: tlsMs,
                ttfbMs: ttfbMs,
                totalTimeMs: elapsedMs,
                certificateInfo: collector.certInfo,
                isHealthy: isHealthy,
                errorMessage: nil
            )
        } catch {
            let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000.0
            return HTTPObservation(
                url: url,
                statusCode: 0,
                httpVersion: nil,
                redirectURL: nil,
                headers: [:],
                dnsTimeMs: nil,
                connectTimeMs: nil,
                tlsTimeMs: nil,
                ttfbMs: nil,
                totalTimeMs: elapsedMs,
                certificateInfo: nil,
                isHealthy: false,
                errorMessage: error.localizedDescription
            )
        }
    }
}
