import Foundation
import CryptoKit

public struct RedactedSecretInfo: Identifiable, Sendable {
    public var id: String { "\(lineNumber)-\(secretType)" }
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

        // Enable / User Secrets
        if let regex = try? NSRegularExpression(pattern: #"(?i)(?:enable\s+(?:secret|password)(?:\s+\d+)?\s+)(\S+)"#, options: []) {
            list.append(SecretPattern(name: "Enable Secret", regex: regex, captureGroup: 1))
        }
        if let regex = try? NSRegularExpression(pattern: #"(?i)(?:username\s+\S+\s+(?:secret|password)(?:\s+\d+)?\s+)(\S+)"#, options: []) {
            list.append(SecretPattern(name: "User Password", regex: regex, captureGroup: 1))
        }
        // Password 7 or Secret
        if let regex = try? NSRegularExpression(pattern: #"(?i)(?:\bpassword\s+7\s+)(\S+)"#, options: []) {
            list.append(SecretPattern(name: "Type 7 Password", regex: regex, captureGroup: 1))
        }
        // SNMP Community String
        if let regex = try? NSRegularExpression(pattern: #"(?i)(?:snmp-server\s+community\s+)(\S+)"#, options: []) {
            list.append(SecretPattern(name: "SNMP Community", regex: regex, captureGroup: 1))
        }
        // TACACS / RADIUS Key
        if let regex = try? NSRegularExpression(pattern: #"(?i)(?:(?:tacacs-server|radius-server|tacacs|radius)\s+(?:host\s+\S+\s+)?key(?:\s+\d+)?\s+)(\S+)"#, options: []) {
            list.append(SecretPattern(name: "AAA Server Key", regex: regex, captureGroup: 1))
        }
        // BGP Neighbor Password
        if let regex = try? NSRegularExpression(pattern: #"(?i)(?:neighbor\s+\S+\s+password(?:\s+\d+)?\s+)(\S+)"#, options: []) {
            list.append(SecretPattern(name: "BGP Neighbor Password", regex: regex, captureGroup: 1))
        }
        // IPsec Pre-Shared Key
        if let regex = try? NSRegularExpression(pattern: #"(?i)(?:(?:pre-shared-key|key\s+\d+|preshared-key)\s+)(\S+)"#, options: []) {
            list.append(SecretPattern(name: "IPsec / IKE PSK", regex: regex, captureGroup: 1))
        }
        // WPA PSK
        if let regex = try? NSRegularExpression(pattern: #"(?i)(?:wpa-psk\s+(?:ascii|hex)\s+)(\S+)"#, options: []) {
            list.append(SecretPattern(name: "Wi-Fi WPA PSK", regex: regex, captureGroup: 1))
        }

        return list
    }()

    public func sanitize(text: String) -> RedactionResult {
        let lines = text.components(separatedBy: .newlines)
        var sanitizedLines: [String] = []
        var items: [RedactedSecretInfo] = []

        for (idx, line) in lines.enumerated() {
            let lineNum = idx + 1
            var currentLine = line

            for p in patterns {
                let range = NSRange(location: 0, length: currentLine.utf16.count)
                let matches = p.regex.matches(in: currentLine, options: [], range: range)

                // Replace in reverse order so ranges remain valid
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

        return RedactionResult(
            sanitizedText: sanitizedLines.joined(separator: "\n"),
            redactedCount: items.count,
            redactedItems: items
        )
    }

    private func makeRedactionToken(secret: String, type: String) -> String {
        let hash = SHA256.hash(data: Data(secret.utf8))
        let shortHex = hash.compactMap { String(format: "%02x", $0) }.joined().prefix(6).uppercased()
        return "[REDACTED_SECRET_\(shortHex)]"
    }
}
