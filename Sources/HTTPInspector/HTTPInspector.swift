import Foundation
import NetworkCore
import Security

private final class MetricsCollector: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    var collectedMetrics: URLSessionTaskMetrics?
    var certInfo: TLSCertificateInfo?
    private let lock = NSLock()

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        lock.lock()
        defer { lock.unlock() }
        self.collectedMetrics = metrics
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

                var expiryDate: Date? = nil
                if let values = SecCertificateCopyValues(cert, [kSecOIDX509V1ValidityNotAfter] as CFArray, nil) as? [CFString: [CFString: Any]],
                   let notAfterDict = values[kSecOIDX509V1ValidityNotAfter],
                   let dateVal = notAfterDict[kSecPropertyKeyValue] as? Date {
                    expiryDate = dateVal
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
                    issuerSummary: challenge.protectionSpace.host,
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
        let urlStr = "\(scheme)://\(targetHost)"
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

            return HTTPObservation(
                url: url,
                statusCode: httpResponse.statusCode,
                httpVersion: "HTTP/1.1",
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
