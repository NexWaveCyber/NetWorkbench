import Foundation

/// Fast streaming ANSI SGR (Select Graphic Rendition) parser
/// Translates raw terminal escape sequences into structured `[ANSISpan]` elements.
public struct ANSISGRParser: Sendable {
    public static let shared = ANSISGRParser()

    public init() {}

    /// Parses a raw output string into an array of styled lines
    public func parseLines(from text: String) -> [TerminalLine] {
        var lines: [TerminalLine] = []
        let rawLines = text.components(separatedBy: "\n")
        var currentStyle = ANSIStyle.default

        for rawLine in rawLines {
            var sanitized = rawLine
            // Handle carriage return: if line contains '\r', take the last segment if not empty
            if sanitized.contains("\r") {
                let parts = sanitized.components(separatedBy: "\r").filter { !$0.isEmpty }
                sanitized = parts.last ?? ""
            }

            if sanitized.isEmpty {
                continue
            }

            let (spans, updatedStyle) = parseSpans(from: sanitized, initialStyle: currentStyle)
            currentStyle = updatedStyle

            // Combine span text to form the plain text representation
            let plainText = spans.map(\.text).joined()
            if !plainText.isEmpty {
                lines.append(TerminalLine(text: plainText, spans: spans))
            }
        }

        return lines
    }

    /// Parses a single line string into styled spans, carrying forward the active style
    public func parseSpans(from line: String, initialStyle: ANSIStyle = .default) -> ([ANSISpan], ANSIStyle) {
        var spans: [ANSISpan] = []
        var activeStyle = initialStyle
        var buffer = ""

        var index = line.startIndex
        while index < line.endIndex {
            if line[index] == "\u{1B}" { // ESC character
                let remaining = line[index...]
                if remaining.hasPrefix("\u{1B}[") {
                    // Flush existing buffer before style transition
                    if !buffer.isEmpty {
                        spans.append(ANSISpan(text: buffer, style: activeStyle))
                        buffer = ""
                    }

                    // Find terminating character of the CSI sequence
                    let csiStart = line.index(index, offsetBy: 2)
                    var csiEnd = csiStart
                    while csiEnd < line.endIndex && !line[csiEnd].isLetter && line[csiEnd] != "@" {
                        csiEnd = line.index(after: csiEnd)
                    }

                    if csiEnd < line.endIndex {
                        let terminator = line[csiEnd]
                        let paramString = String(line[csiStart..<csiEnd])

                        if terminator == "m" {
                            // SGR Graphic Rendition sequence
                            activeStyle = applySGRCodes(paramString, to: activeStyle)
                        }
                        // Non-m CSI sequences (cursor moves, clears) are safely consumed and dropped

                        index = line.index(after: csiEnd)
                        continue
                    }
                } else if remaining.hasPrefix("\u{1B}]") {
                    // Operating System Command (OSC) sequence - e.g. window title: \x1b]0;title\x07
                    if let bellIndex = remaining.firstIndex(of: "\u{07}") {
                        index = line.index(after: bellIndex)
                        continue
                    } else if let stIndex = remaining.range(of: "\u{1B}\\")?.upperBound {
                        index = stIndex
                        continue
                    }
                }
            }

            buffer.append(line[index])
            index = line.index(after: index)
        }

        if !buffer.isEmpty {
            spans.append(ANSISpan(text: buffer, style: activeStyle))
        }

        return (spans, activeStyle)
    }

    // MARK: - SGR Code Interpretation

    private func applySGRCodes(_ paramString: String, to existing: ANSIStyle) -> ANSIStyle {
        var style = existing
        let normalized = paramString.replacingOccurrences(of: ":", with: ";")
        let codes: [Int] = normalized.isEmpty ? [0] : normalized.components(separatedBy: ";").compactMap { Int($0) }

        var i = 0
        while i < codes.count {
            let code = codes[i]
            switch code {
            case 0:
                // Reset all
                style = ANSIStyle.default

            case 1:
                style.isBold = true
            case 2:
                style.isDim = true
            case 3:
                style.isItalic = true
            case 4:
                style.isUnderline = true
            case 7:
                style.isInverse = true

            case 22:
                style.isBold = false
                style.isDim = false
            case 23:
                style.isItalic = false
            case 24:
                style.isUnderline = false
            case 27:
                style.isInverse = false

            // Standard Foreground Colors (30-37)
            case 30...37:
                style.foreground = standard16Color(code - 30, bright: style.isBold)
            case 39:
                style.foreground = nil // Default fg

            // Standard Background Colors (40-47)
            case 40...47:
                style.background = standard16Color(code - 40, bright: false)
            case 49:
                style.background = nil // Default bg

            // High-Intensity / Bright Foreground Colors (90-97)
            case 90...97:
                style.foreground = standard16Color(code - 90, bright: true)

            // High-Intensity / Bright Background Colors (100-107)
            case 100...107:
                style.background = standard16Color(code - 100, bright: true)

            // Extended 256-color or TrueColor Foreground (38;5;N or 38;2;R;G;B)
            case 38:
                if i + 2 < codes.count && codes[i + 1] == 5 {
                    let colorIndex = codes[i + 2]
                    style.foreground = colorFrom256Table(colorIndex)
                    i += 2
                } else if i + 4 < codes.count && codes[i + 1] == 2 {
                    let r = UInt8(clamping: codes[i + 2])
                    let g = UInt8(clamping: codes[i + 3])
                    let b = UInt8(clamping: codes[i + 4])
                    style.foreground = ANSIColor(r: r, g: g, b: b)
                    i += 4
                }

            // Extended 256-color or TrueColor Background (48;5;N or 48;2;R;G;B)
            case 48:
                if i + 2 < codes.count && codes[i + 1] == 5 {
                    let colorIndex = codes[i + 2]
                    style.background = colorFrom256Table(colorIndex)
                    i += 2
                } else if i + 4 < codes.count && codes[i + 1] == 2 {
                    let r = UInt8(clamping: codes[i + 2])
                    let g = UInt8(clamping: codes[i + 3])
                    let b = UInt8(clamping: codes[i + 4])
                    style.background = ANSIColor(r: r, g: g, b: b)
                    i += 4
                }

            default:
                break
            }
            i += 1
        }

        return style
    }

    // MARK: - Color Lookups

    private func standard16Color(_ index: Int, bright: Bool) -> ANSIColor {
        if bright {
            switch index {
            case 0: return ANSIColor(r: 104, g: 110, b: 122) // Bright Black (Gray)
            case 1: return ANSIColor(r: 255, g: 85, b: 85)   // Bright Red
            case 2: return ANSIColor(r: 80, g: 250, b: 123)  // Bright Green
            case 3: return ANSIColor(r: 255, g: 245, b: 100) // Bright Yellow
            case 4: return ANSIColor(r: 96, g: 165, b: 250)  // Bright Blue
            case 5: return ANSIColor(r: 255, g: 121, b: 198) // Bright Magenta
            case 6: return ANSIColor(r: 0, g: 229, b: 255)   // Bright Cyan
            case 7: return ANSIColor(r: 255, g: 255, b: 255) // Bright White
            default: return ANSIColor(r: 255, g: 255, b: 255)
            }
        } else {
            switch index {
            case 0: return ANSIColor(r: 0, g: 0, b: 0)       // Black
            case 1: return ANSIColor(r: 239, g: 68, b: 68)   // Red
            case 2: return ANSIColor(r: 16, g: 185, b: 129)  // Green
            case 3: return ANSIColor(r: 245, g: 158, b: 11)  // Yellow
            case 4: return ANSIColor(r: 59, g: 130, b: 246)  // Blue
            case 5: return ANSIColor(r: 168, g: 85, b: 247)  // Magenta
            case 6: return ANSIColor(r: 6, g: 182, b: 212)   // Cyan
            case 7: return ANSIColor(r: 209, g: 213, b: 219) // White
            default: return ANSIColor(r: 209, g: 213, b: 219)
            }
        }
    }

    private func colorFrom256Table(_ index: Int) -> ANSIColor {
        // Standard 0-15
        if index < 16 {
            return standard16Color(index % 8, bright: index >= 8)
        }
        // 6x6x6 color cube: 16-231
        if index <= 231 {
            let offset = index - 16
            let r = UInt8((offset / 36) * 51)
            let g = UInt8(((offset % 36) / 6) * 51)
            let b = UInt8((offset % 6) * 51)
            return ANSIColor(r: r, g: g, b: b)
        }
        // Grayscale ramp: 232-255
        let gray = UInt8(8 + (index - 232) * 10)
        return ANSIColor(r: gray, g: gray, b: gray)
    }
}
