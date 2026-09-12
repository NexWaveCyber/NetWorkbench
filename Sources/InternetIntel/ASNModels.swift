import Foundation

public enum RPKIValidationStatus: String, Sendable, Codable {
    case valid = "VALID"
    case invalid = "INVALID"
    case notFound = "NOT FOUND"
    case unknown = "UNKNOWN"

    public var displayLabel: String {
        switch self {
        case .valid: return "RPKI Valid (ROA Signed)"
        case .invalid: return "RPKI Invalid (Conflicting ROA)"
        case .notFound: return "RPKI Not Found (No ROA Published)"
        case .unknown: return "Validation Inconclusive"
        }
    }
}

public struct ASRecord: Sendable, Identifiable, Codable {
    public var id: Int { asn }
    public let asn: Int
    public let asName: String
    public let countryCode: String
    public let registry: String
    public let allocatedDate: String

    public var formattedASN: String { "AS\(asn)" }

    public init(asn: Int, asName: String, countryCode: String, registry: String, allocatedDate: String) {
        self.asn = asn
        self.asName = asName
        self.countryCode = countryCode
        self.registry = registry.uppercased()
        self.allocatedDate = allocatedDate
    }
}

public struct BGPAnnouncement: Sendable, Codable {
    public let prefix: String
    public let originASN: Int
    public let registry: String
    public let countryCode: String
    public let allocationDate: String

    public init(prefix: String, originASN: Int, registry: String, countryCode: String, allocationDate: String) {
        self.prefix = prefix
        self.originASN = originASN
        self.registry = registry.uppercased()
        self.countryCode = countryCode.uppercased()
        self.allocationDate = allocationDate
    }
}

public struct RPKIValidationResult: Sendable, Codable {
    public let status: RPKIValidationStatus
    public let originASN: Int
    public let prefix: String
    public let validator: String
    public let explanation: String

    public init(status: RPKIValidationStatus, originASN: Int, prefix: String, validator: String = "routinator", explanation: String) {
        self.status = status
        self.originASN = originASN
        self.prefix = prefix
        self.validator = validator
        self.explanation = explanation
    }
}

public struct InternetIntelligenceReport: Sendable, Identifiable {
    public var id: String { "\(target)-\(ipAddress)" }
    public let target: String
    public let ipAddress: String
    public let asRecord: ASRecord?
    public let bgpAnnouncement: BGPAnnouncement?
    public let rpkiResult: RPKIValidationResult?
    public let rdapOrgName: String?
    public let lookupTimeMs: Double
    public let isSuccess: Bool
    public let errorMessage: String?

    public init(
        target: String,
        ipAddress: String,
        asRecord: ASRecord?,
        bgpAnnouncement: BGPAnnouncement?,
        rpkiResult: RPKIValidationResult?,
        rdapOrgName: String?,
        lookupTimeMs: Double,
        isSuccess: Bool,
        errorMessage: String? = nil
    ) {
        self.target = target
        self.ipAddress = ipAddress
        self.asRecord = asRecord
        self.bgpAnnouncement = bgpAnnouncement
        self.rpkiResult = rpkiResult
        self.rdapOrgName = rdapOrgName
        self.lookupTimeMs = lookupTimeMs
        self.isSuccess = isSuccess
        self.errorMessage = errorMessage
    }
}
