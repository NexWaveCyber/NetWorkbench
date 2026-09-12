import SwiftUI

/// Design tokens and semantic styling for NexWave Network Workbench.
/// Combines Apple macOS HIG precision with high-tech engineering workstation aesthetics.
public enum Theme {
    // MARK: - Semantic Cyber & Telemetry Colors
    public static let cyanPulse = Color(red: 0.0, green: 0.88, blue: 1.0)
    public static let neonCyan = Color(red: 0.0, green: 0.94, blue: 1.0)
    public static let azurePro = Color(red: 0.04, green: 0.52, blue: 1.0)
    public static let electricAzure = Color(red: 0.12, green: 0.58, blue: 1.0)
    public static let emeraldHealthy = Color(red: 0.18, green: 0.82, blue: 0.38)
    public static let signalEmerald = Color(red: 0.20, green: 0.88, blue: 0.42)
    public static let amberWarning = Color(red: 1.0, green: 0.62, blue: 0.05)
    public static let solarAmber = Color(red: 1.0, green: 0.68, blue: 0.10)
    public static let crimsonCritical = Color(red: 1.0, green: 0.24, blue: 0.24)
    public static let pulseCrimson = Color(red: 1.0, green: 0.28, blue: 0.30)
    public static let purpleInferred = Color(red: 0.72, green: 0.36, blue: 0.96)
    public static let quantumViolet = Color(red: 0.76, green: 0.40, blue: 1.0)

    // MARK: - Surfaces & Depths
    public static var surfaceBackground: Color {
        Color(nsColor: .windowBackgroundColor)
    }

    public static var cardBackground: Color {
        Color(nsColor: .controlBackgroundColor)
    }

    public static var secondaryBackground: Color {
        Color(nsColor: .underPageBackgroundColor)
    }

    public static var borderLight: Color {
        Color.primary.opacity(0.08)
    }

    public static var borderHighlight: Color {
        Color.white.opacity(0.12)
    }

    public static var glassBackground: Color {
        Color.primary.opacity(0.03)
    }

    // MARK: - Gradients
    public static var cyanGlowGradient: LinearGradient {
        LinearGradient(
            colors: [neonCyan, azurePro],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    public static var emeraldGlowGradient: LinearGradient {
        LinearGradient(
            colors: [signalEmerald, Color(red: 0.0, green: 0.65, blue: 0.45)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    public static var amberGlowGradient: LinearGradient {
        LinearGradient(
            colors: [solarAmber, Color(red: 1.0, green: 0.45, blue: 0.0)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    public static var crimsonGlowGradient: LinearGradient {
        LinearGradient(
            colors: [pulseCrimson, Color(red: 0.85, green: 0.1, blue: 0.2)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    public static var darkHeaderGradient: LinearGradient {
        LinearGradient(
            colors: [Color.primary.opacity(0.04), Color.primary.opacity(0.01)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Typography Styles
    public static func monoText(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Advanced Engineering Card Modifier
public struct EngineeringCardModifier: ViewModifier {
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 12
    var hasHoverEffect: Bool = false
    var accentBorder: Color? = nil
    
    @State private var isHovered = false

    public func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Theme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        accentBorder ?? (isHovered ? Theme.cyanPulse.opacity(0.35) : Theme.borderLight),
                        lineWidth: isHovered ? 1.5 : 1.0
                    )
            )
            .shadow(
                color: isHovered ? Theme.cyanPulse.opacity(0.12) : Color.black.opacity(0.04),
                radius: isHovered ? 8 : 2,
                x: 0,
                y: isHovered ? 3 : 1
            )
            .onHover { hovering in
                if hasHoverEffect {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isHovered = hovering
                    }
                }
            }
    }
}

// MARK: - Glassmorphic Container Modifier
public struct GlassHUDCardModifier: ViewModifier {
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 12

    public func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.15), Color.primary.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
    }
}

// MARK: - View Extensions
public extension View {
    func engineeringCard(
        padding: CGFloat = 16,
        cornerRadius: CGFloat = 12,
        hasHoverEffect: Bool = false,
        accentBorder: Color? = nil
    ) -> some View {
        self.modifier(EngineeringCardModifier(
            padding: padding,
            cornerRadius: cornerRadius,
            hasHoverEffect: hasHoverEffect,
            accentBorder: accentBorder
        ))
    }

    func glassHUDCard(padding: CGFloat = 16, cornerRadius: CGFloat = 12) -> some View {
        self.modifier(GlassHUDCardModifier(padding: padding, cornerRadius: cornerRadius))
    }
}

// MARK: - Reusable HUD Status Badge
public struct HUDStatusBadge: View {
    let title: String
    let color: Color
    var isPulsing: Bool = false
    var icon: String? = nil

    public init(title: String, color: Color, isPulsing: Bool = false, icon: String? = nil) {
        self.title = title
        self.color = color
        self.isPulsing = isPulsing
        self.icon = icon
    }

    public var body: some View {
        HStack(spacing: 5) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
            }

            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.12))
        .foregroundStyle(color)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(color.opacity(0.25), lineWidth: 0.75)
        )
    }
}

// MARK: - Color Hex Initializer
public extension Color {
    init(hex: String) {
        let cleanHex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleanHex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch cleanHex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 128, 128, 128)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
