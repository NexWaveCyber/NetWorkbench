import Foundation

/// Real-time terminal keyword and syntax highlighter (MobaXterm Syntax Coloring equivalent)
/// Enhances terminal lines by dynamically color-coding IP addresses, MAC addresses,
/// error states, and operational success indicators without affecting underlying escape logic.
public struct TerminalKeywordHighlighter: Sendable {
    public static let shared = TerminalKeywordHighlighter()

    public init() {}

    private static let ipv4Regex = try? NSRegularExpression(
        pattern: #"\b(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b"#
    )

    private static let ipv6Regex = try? NSRegularExpression(
        pattern: #"\b(?:[0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}\b|\b(?:[0-9a-fA-F]{1,4}:){1,7}:|\b:(?::[0-9a-fA-F]{1,4}){1,7}\b|\bfe80:[0-9a-fA-F:]*\b|\b::1\b"#
    )

    private static let cidrRegex = try? NSRegularExpression(
        pattern: #"/(?:[0-9]|[12][0-9]|3[0-2])\b|\b255\.(?:255|254|252|248|240|224|192|128|0)\.(?:255|254|252|248|240|224|192|128|0)\.(?:255|254|252|248|240|224|192|128|0)\b"#
    )

    private static let interfaceRegex = try? NSRegularExpression(
        pattern: #"\b(?:GigabitEthernet|TenGigabitEthernet|FastEthernet|Ethernet|Loopback|Vlan|Port-channel|Management|Tunnel|ge-|xe-|et-|ether|bridge|sfp-sfpplus|wlan|en|eth|lo)\d*(?:[\/.:]\d+)*\b"#,
        options: .caseInsensitive
    )

    private static let macRegex = try? NSRegularExpression(
        pattern: #"\b(?:[0-9a-fA-F]{2}[:-]){5}[0-9a-fA-F]{2}\b|\b[0-9a-fA-F]{4}\.[0-9a-fA-F]{4}\.[0-9a-fA-F]{4}\b"#
    )

    private static let errorRegex = try? NSRegularExpression(
        pattern: #"\b(error|failed|failure|down|critical|denied|unreachable|drop|timeout|reset|alert|panic|refused|400|401|403|404|500|502|503)\b"#,
        options: .caseInsensitive
    )

    private static let successRegex = try? NSRegularExpression(
        pattern: #"\b(up|active|connected|established|ok|success|succeeded|running|passed|online|200\s+ok|201\s+created)\b"#,
        options: .caseInsensitive
    )

    // Palette
    private let ipColor = ANSIColor(r: 0, g: 229, b: 255)          // Neon Cyan
    private let ipv6Color = ANSIColor(r: 0, g: 200, b: 240)        // Deep Cyan
    private let cidrColor = ANSIColor(r: 140, g: 190, b: 230)      // Slate Blue
    private let interfaceColor = ANSIColor(r: 175, g: 130, b: 255) // Cyber Purple
    private let macColor = ANSIColor(r: 245, g: 158, b: 11)        // Solar Amber
    private let errorColor = ANSIColor(r: 255, g: 69, b: 58)        // Crimson Red
    private let successColor = ANSIColor(r: 16, g: 185, b: 129)     // Emerald Green

    /// Highlights keywords in a terminal line if enabled in config
    public func highlight(line: TerminalLine, config: TerminalSyntaxHighlightConfig) -> TerminalLine {
        guard config.isEnabled else { return line }

        let plainText = line.text
        guard !plainText.isEmpty else { return line }

        var matches: [(range: NSRange, color: ANSIColor, isBold: Bool)] = []
        let fullRange = NSRange(location: 0, length: (plainText as NSString).length)

        if config.highlightIPs, let regex = Self.ipv4Regex {
            for m in regex.matches(in: plainText, range: fullRange) {
                matches.append((range: m.range, color: ipColor, isBold: true))
            }
        }

        if config.highlightIPv6, let regex = Self.ipv6Regex {
            for m in regex.matches(in: plainText, range: fullRange) {
                matches.append((range: m.range, color: ipv6Color, isBold: true))
            }
        }

        if config.highlightCIDR, let regex = Self.cidrRegex {
            for m in regex.matches(in: plainText, range: fullRange) {
                matches.append((range: m.range, color: cidrColor, isBold: false))
            }
        }

        if config.highlightInterfaces, let regex = Self.interfaceRegex {
            for m in regex.matches(in: plainText, range: fullRange) {
                matches.append((range: m.range, color: interfaceColor, isBold: true))
            }
        }

        if config.highlightMACs, let regex = Self.macRegex {
            for m in regex.matches(in: plainText, range: fullRange) {
                matches.append((range: m.range, color: macColor, isBold: false))
            }
        }

        if config.highlightErrors, let regex = Self.errorRegex {
            for m in regex.matches(in: plainText, range: fullRange) {
                matches.append((range: m.range, color: errorColor, isBold: true))
            }
        }

        if config.highlightSuccess, let regex = Self.successRegex {
            for m in regex.matches(in: plainText, range: fullRange) {
                matches.append((range: m.range, color: successColor, isBold: true))
            }
        }

        guard !matches.isEmpty else { return line }

        // Sort matches by start position
        matches.sort { $0.range.location < $1.range.location }

        // Build new styled spans
        var newSpans: [ANSISpan] = []
        var cursor = 0
        let nsString = plainText as NSString

        for item in matches {
            if item.range.location < cursor {
                // Overlapping match, skip
                continue
            }

            // Text before match
            if item.range.location > cursor {
                let prefixRange = NSRange(location: cursor, length: item.range.location - cursor)
                let prefixText = nsString.substring(with: prefixRange)
                newSpans.append(ANSISpan(text: prefixText, style: .default))
            }

            // Highlighted match
            let matchText = nsString.substring(with: item.range)
            let style = ANSIStyle(
                foreground: item.color,
                isBold: item.isBold
            )
            newSpans.append(ANSISpan(text: matchText, style: style))
            cursor = item.range.location + item.range.length
        }

        // Remaining tail text
        if cursor < nsString.length {
            let tailRange = NSRange(location: cursor, length: nsString.length - cursor)
            let tailText = nsString.substring(with: tailRange)
            newSpans.append(ANSISpan(text: tailText, style: .default))
        }

        return TerminalLine(
            id: line.id,
            text: line.text,
            spans: newSpans,
            isCommandInput: line.isCommandInput,
            timestamp: line.timestamp
        )
    }
}
