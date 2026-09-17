import Foundation
import NetworkCore
import Security

public struct TLSCertificateInfo: Sendable, Hashable {
    public let subjectSummary: String
    public let issuerSummary: String
    public let expirationDate: Date?
    public let daysUntilExpiry: Int?
    public let isExpired: Bool
    public let isSelfSigned: Bool
    public let isUntrusted: Bool
    public let cipherSuite: String?
    public let protocolVersion: String?

    public init(
        subjectSummary: String,
        issuerSummary: String,
        expirationDate: Date?,
        daysUntilExpiry: Int?,
        isExpired: Bool,
        isSelfSigned: Bool = false,
        isUntrusted: Bool = false,
        cipherSuite: String? = nil,
        protocolVersion: String? = nil
    ) {
        self.subjectSummary = subjectSummary
        self.issuerSummary = issuerSummary
        self.expirationDate = expirationDate
        self.daysUntilExpiry = daysUntilExpiry
        self.isExpired = isExpired
        self.isSelfSigned = isSelfSigned
        self.isUntrusted = isUntrusted
        self.cipherSuite = cipherSuite
        self.protocolVersion = protocolVersion
    }
}

public struct HTTPObservation: Sendable {
    public let url: URL
    public let statusCode: Int
    public let httpVersion: String?
    public let redirectURL: URL?
    public let headers: [String: String]
    public let dnsTimeMs: Double?
    public let connectTimeMs: Double?
    public let tlsTimeMs: Double?
    public let ttfbMs: Double?
    public let totalTimeMs: Double
    public let certificateInfo: TLSCertificateInfo?
    public let isHealthy: Bool
    public let errorMessage: String?

    public init(
        url: URL,
        statusCode: Int,
        httpVersion: String?,
        redirectURL: URL?,
        headers: [String: String],
        dnsTimeMs: Double?,
        connectTimeMs: Double?,
        tlsTimeMs: Double?,
        ttfbMs: Double?,
        totalTimeMs: Double,
        certificateInfo: TLSCertificateInfo?,
        isHealthy: Bool,
        errorMessage: String? = nil
    ) {
        self.url = url
        self.statusCode = statusCode
        self.httpVersion = httpVersion
        self.redirectURL = redirectURL
        self.headers = headers
        self.dnsTimeMs = dnsTimeMs
        self.connectTimeMs = connectTimeMs
        self.tlsTimeMs = tlsTimeMs
        self.ttfbMs = ttfbMs
        self.totalTimeMs = totalTimeMs
        self.certificateInfo = certificateInfo
        self.isHealthy = isHealthy
        self.errorMessage = errorMessage
    }
}
