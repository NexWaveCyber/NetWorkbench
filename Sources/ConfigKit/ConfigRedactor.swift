import Foundation
import CryptoKit

public struct RedactedSecretInfo: Identifiable, Sendable {
    public var id: String { "\(lineNumber)-\(secretType)-\(replacementToken)" }
    public let lineNumber: Int
    public let secretType: String
    public let originalLength: Int
    public let replacementToken: String

    public init(lineNumber: Int, secretType: String, originalLength: Int, replacementToken: String) {
        self.lineNumber = lineNumber
        self.secretType = secretType
        self.originalLength = originalLength
        self.replacementToken = replacementToken
    }
}

public struct RedactionResult: Sendable {
    public let sanitizedText: String
    public let redactedCount: Int
    public let redactedItems: [RedactedSecretInfo]

    public init(sanitizedText: String, redactedCount: Int, redactedItems: [RedactedSecretInfo]) {
        self.sanitizedText = sanitizedText
        self.redactedCount = redactedCount
        self.redactedItems = redactedItems
    }
}

public struct ConfigRedactor: Sendable {
    public init() {}

    private struct SecretPattern {
        let name: String
        let regex: NSRegularExpression
        let captureGroup: Int
    }

    private let patterns: [SecretPattern] = {
        var list: [SecretPattern] = []

        // 1. Enable / User Secrets (Cisco, Arista, Huawei)
        if let regex = try? NSRegularExpression(pattern: #"(?i)(?:enable\s+(?:secret|password)(?:\s+\d+)?\s+)(\S+)"#, options: []) {
            list.append(SecretPattern(name: "Enable Secret", regex: regex, captureGroup: 1))
        }
        if let regex = try? NSRegularExpression(pattern: #"(?i)(?:username\s+\S+\s+(?:privilege\s+\d+\s+)?(?:secret|password)(?:\s+\d+)?\s+)(\S+)"#, options: []) {
            list.append(SecretPattern(name: "User Password", regex: regex, captureGroup: 1))
        }
        // 2. Cisco Type 7 Password
        if let regex = try? NSRegularExpression(pattern: #"(?i)(?:\bpassword\s+7\s+)(\S+)"#, options: []) {
            list.append(SecretPattern(name: "Type 7 Password", regex: regex, captureGroup: 1))
        }
        // 3. SNMP Community Strings (RO / RW)
        if let regex = try? NSRegularExpression(pattern: #"(?i)(?:snmp-server\s+community\s+)(\S+)"#, options: []) {
            list.append(SecretPattern(name: "SNMP Community", regex: regex, captureGroup: 1))
        }
        // 4. TACACS+ / RADIUS Shared Secret Keys
        if let regex = try? NSRegularExpression(pattern: #"(?i)(?:(?:tacacs-server|radius-server|tacacs|radius)\s+(?:host\s+\S+\s+)?key(?:\s+\d+)?\s+)(\S+)"#, options: []) {
            list.append(SecretPattern(name: "AAA Server Key", regex: regex, captureGroup: 1))
        }
        // 5. BGP / OSPF / EIGRP Neighbor Password
        if let regex = try? NSRegularExpression(pattern: #"(?i)(?:(?:neighbor\s+\S+\s+password|ip\s+ospf\s+authentication-key|message-digest-key\s+\d+\s+md5)(?:\s+\d+)?\s+)(\S+)"#, options: []) {
            list.append(SecretPattern(name: "Routing Protocol Auth Key", regex: regex, captureGroup: 1))
        }
        // 6. IPsec / IKE Pre-Shared Keys
        if let regex = try? NSRegularExpression(pattern: #"(?i)(?:(?:pre-shared-key|key\s+\d+|preshared-key)\s+(?:hex\s+|ascii\s+)?|set\s+psksecret\s+)(\S+)"#, options: []) {
            list.append(SecretPattern(name: "IPsec / IKE PSK", regex: regex, captureGroup: 1))
        }
        // 7. Wi-Fi WPA Pre-Shared Key
        if let regex = try? NSRegularExpression(pattern: #"(?i)(?:wpa-psk\s+(?:ascii|hex)\s+)(\S+)"#, options: []) {
            list.append(SecretPattern(name: "Wi-Fi WPA PSK", regex: regex, captureGroup: 1))
        }
        // 8. Fortinet Encrypted Passwords & Secrets
        if let regex = try? NSRegularExpression(pattern: #"(?i)(?:set\s+(?:password|secret)\s+ENC\s+)(\S+)"#, options: []) {
            list.append(SecretPattern(name: "Fortinet ENC Secret", regex: regex, captureGroup: 1))
        }
        // 9. Juniper Encrypted Passwords ($9$ / $1$)
        if let regex = try? NSRegularExpression(pattern: #"(?i)(?:encrypted-password\s+")(\$9\$[^\s"]+|\$1\$[^\s"]+)"#, options: []) {
            list.append(SecretPattern(name: "Juniper Encrypted Password", regex: regex, captureGroup: 1))
        }
        // 10. Palo Alto Password Hashes
        if let regex = try? NSRegularExpression(pattern: #"(?i)(?:phash\s+)(\S+)"#, options: []) {
            list.append(SecretPattern(name: "Palo Alto Password Hash", regex: regex, captureGroup: 1))
        }
        // 11. Cloud API & AWS Access Keys
        if let regex = try? NSRegularExpression(pattern: #"(?i)\b(AKIA[0-9A-Z]{16})\b"#, options: []) {
            list.append(SecretPattern(name: "AWS Access Key", regex: regex, captureGroup: 1))
        }
        // 12. Bearer Tokens
        if let regex = try? NSRegularExpression(pattern: #"(?i)(?:Bearer\s+)([A-Za-z0-9\-_.]{16,})"#, options: []) {
            list.append(SecretPattern(name: "API Bearer Token", regex: regex, captureGroup: 1))
        }

        return list
    }()

    public func sanitize(text: String, anonymizeIPs: Bool = false) -> RedactionResult {
        // Multi-line Private Key PEM Block redaction first
        let processedText = sanitizePrivateKeys(in: text)

        let lines = processedText.components(separatedBy: .newlines)
        var sanitizedLines: [String] = []
        var items: [RedactedSecretInfo] = []

        for (idx, line) in lines.enumerated() {
            let lineNum = idx + 1
            var currentLine = line

            for p in patterns {
                let range = NSRange(location: 0, length: currentLine.utf16.count)
                let matches = p.regex.matches(in: currentLine, options: [], range: range)

                for match in matches.reversed() {
                    guard match.numberOfRanges > p.captureGroup else { continue }
                    let secretRange = match.range(at: p.captureGroup)
                    guard let swiftRange = Range(secretRange, in: currentLine) else { continue }

                    let secretValue = String(currentLine[swiftRange])
                    let token = makeRedactionToken(secret: secretValue, type: p.name)

                    items.append(RedactedSecretInfo(
                        lineNumber: lineNum,
                        secretType: p.name,
                        originalLength: secretValue.count,
                        replacementToken: token
                    ))

                    currentLine.replaceSubrange(swiftRange, with: token)
                }
            }

            sanitizedLines.append(currentLine)
        }

        var finalResult = sanitizedLines.joined(separator: "\n")

        if anonymizeIPs {
            finalResult = applyTopologyIPAnonymization(to: finalResult)
        }

        return RedactionResult(
            sanitizedText: finalResult,
            redactedCount: items.count,
            redactedItems: items
        )
    }

    private func sanitizePrivateKeys(in text: String) -> String {
        let pattern = #"-----BEGIN (?:[A-Z0-9 ]+)?PRIVATE KEY-----[\s\S]*?-----END (?:[A-Z0-9 ]+)?PRIVATE KEY-----"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return text }
        let range = NSRange(location: 0, length: text.utf16.count)
        return regex.stringByReplacingMatches(
            in: text,
            options: [],
            range: range,
            withTemplate: "-----BEGIN PRIVATE KEY-----\n[REDACTED_CRYPTO_KEY_BLOCK]\n-----END PRIVATE KEY-----"
        )
    }

    public func applyTopologyIPAnonymization(to text: String) -> String {
        // Replace public IP addresses with RFC 5737 Test-Net ranges (192.0.2.0/24, 198.51.100.0/24)
        // while preserving private RFC 1918 subnets (10.x.x.x, 172.16-31.x.x, 192.168.x.x)
        let ipPattern = #"\b([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})\b"#
        guard let regex = try? NSRegularExpression(pattern: ipPattern, options: []) else { return text }

        var ipMap: [String: String] = [:]
        var counter = 2

        let range = NSRange(location: 0, length: text.utf16.count)
        let matches = regex.matches(in: text, options: [], range: range)

        var result = text
        for match in matches.reversed() {
            guard let r = Range(match.range(at: 1), in: result) else { continue }
            let ip = String(result[r])

            // Skip RFC 1918 private IPs and subnet masks
            if ip.hasPrefix("10.") || ip.hasPrefix("192.168.") || ip.hasPrefix("172.16.") || ip.hasPrefix("172.17.") ||
               ip.hasPrefix("172.18.") || ip.hasPrefix("172.19.") || ip.hasPrefix("172.20.") || ip.hasPrefix("172.31.") ||
               ip == "255.255.255.0" || ip == "255.255.255.255" || ip == "0.0.0.0" || ip == "255.255.255.252" ||
               ip == "255.255.0.0" || ip == "255.0.0.0" || ip == "127.0.0.1" {
                continue
            }

            if ipMap[ip] == nil {
                ipMap[ip] = "198.51.100.\(counter)"
                counter = (counter % 250) + 1
            }

            if let masked = ipMap[ip] {
                result.replaceSubrange(r, with: masked)
            }
        }

        return result
    }

    private func makeRedactionToken(secret: String, type: String) -> String {
        let hash = SHA256.hash(data: Data(secret.utf8))
        let shortHex = hash.compactMap { String(format: "%02x", $0) }.joined().prefix(6).uppercased()
        return "[REDACTED_SECRET_\(shortHex)]"
    }
}
