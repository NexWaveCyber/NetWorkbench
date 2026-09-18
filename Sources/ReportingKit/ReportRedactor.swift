import Foundation
import CryptoKit

public enum ReportRedactor {

    private struct SecretPattern {
        let regex: NSRegularExpression
        let tokenPrefix: String

        init(pattern: String, prefix: String) {
            self.regex = (try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])) ?? (try? NSRegularExpression(pattern: "$^")) ?? NSRegularExpression()
            self.tokenPrefix = prefix
        }
    }

    private static let secretPatterns: [SecretPattern] = [
        SecretPattern(pattern: #"(password\s+)(\S+)"#, prefix: "REDACTED_PASSWORD"),
        SecretPattern(pattern: #"(secret\s+)(\S+)"#, prefix: "REDACTED_SECRET"),
        SecretPattern(pattern: #"(community\s+)(\S+)"#, prefix: "REDACTED_COMMUNITY"),
        SecretPattern(pattern: #"(snmp-server\s+community\s+)(\S+)"#, prefix: "REDACTED_SNMP"),
        SecretPattern(pattern: #"(key\s+)(\S+)"#, prefix: "REDACTED_KEY"),
        SecretPattern(pattern: #"(token\s*[:=]\s*["']?)([a-zA-Z0-9_\-\.]{8,})(["']?)"#, prefix: "REDACTED_TOKEN"),
        SecretPattern(pattern: #"(Bearer\s+)([a-zA-Z0-9_\-\.]{8,})"#, prefix: "REDACTED_BEARER"),
        SecretPattern(pattern: #"-----BEGIN [A-Z ]+ PRIVATE KEY-----[\s\S]+?-----END [A-Z ]+ PRIVATE KEY-----"#, prefix: "REDACTED_PRIVATE_KEY")
    ]

    public static func sanitize(_ text: String) -> String {
        var result = text

        for sp in secretPatterns {
            let matches = sp.regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                guard let fullRange = Range(match.range, in: result) else { continue }

                if match.numberOfRanges > 2, let secretRange = Range(match.range(at: 2), in: result) {
                    let secretVal = String(result[secretRange])
                    let token = makeToken(prefix: sp.tokenPrefix, rawSecret: secretVal)
                    result.replaceSubrange(secretRange, with: token)
                } else {
                    let fullText = String(result[fullRange])
                    let token = makeToken(prefix: sp.tokenPrefix, rawSecret: fullText)
                    result.replaceSubrange(fullRange, with: "[\(token)]")
                }
            }
        }

        return result
    }

    private static func makeToken(prefix: String, rawSecret: String) -> String {
        let digest = SHA256.hash(data: Data(rawSecret.utf8))
        let hashPrefix = digest.compactMap { String(format: "%02x", $0) }.joined().prefix(8)
        return "[\(prefix)_\(hashPrefix)]"
    }
}
