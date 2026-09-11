import Foundation

/// Detects and sanitizes sensitive network credentials from configurations and logs.
public struct SensitiveDataRedactor: Sendable {
    public init() {}

    private static let patterns: [(regex: String, replacement: String)] = [
        // Cisco enable secret / password
        (
            regex: #"(enable\s+(?:secret|password)\s+(?:\d+\s+)?)[^\s\r\n]+"#,
            replacement: "$1[REDACTED_SECRET]"
        ),
        // Cisco username secret / password
        (
            regex: #"(username\s+\S+\s+(?:secret|password)\s+(?:\d+\s+)?)[^\s\r\n]+"#,
            replacement: "$1[REDACTED_SECRET]"
        ),
        // SNMP community strings
        (
            regex: #"(snmp-server\s+community\s+)[^\s\r\n]+(\s+(?:RO|RW|view))?"#,
            replacement: "$1[REDACTED_COMMUNITY]$2"
        ),
        // Pre-shared keys (IPsec/IKE)
        (
            regex: #"((?:pre-shared-key|key)\s+(?:hex\s+)?)[^\s\r\n]+"#,
            replacement: "$1[REDACTED_PSK]"
        ),
        // BGP / OSPF authentication passwords
        (
            regex: #"((?:password|md5|key-string)\s+)[^\s\r\n]+"#,
            replacement: "$1[REDACTED_AUTH]"
        ),
        // Private Key blocks
        (
            regex: #"-----BEGIN [A-Z ]+PRIVATE KEY-----[^-]+-----END [A-Z ]+PRIVATE KEY-----"#,
            replacement: "-----BEGIN PRIVATE KEY-----\n[REDACTED_PRIVATE_KEY]\n-----END PRIVATE KEY-----"
        ),
        // HTTP Bearer tokens
        (
            regex: #"(Bearer\s+)[a-zA-Z0-9_\-\.]+"#,
            replacement: "$1[REDACTED_TOKEN]"
        )
    ]

    /// Sanitizes the input string by masking sensitive patterns.
    public static func sanitize(_ input: String) -> String {
        var sanitized = input
        for item in patterns {
            if let regex = try? NSRegularExpression(pattern: item.regex, options: [.caseInsensitive]) {
                let range = NSRange(location: 0, length: sanitized.utf16.count)
                sanitized = regex.stringByReplacingMatches(
                    in: sanitized,
                    options: [],
                    range: range,
                    withTemplate: item.replacement
                )
            }
        }
        return sanitized
    }
}
