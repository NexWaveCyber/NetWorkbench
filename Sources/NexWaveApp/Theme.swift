import SwiftUI

/// Design tokens and semantic styling for NexWave Network Workbench.
public enum Theme {
    // MARK: - Semantic Colors
    public static let cyanPulse = Color(red: 0.0, green: 0.82, blue: 1.0)
    public static let azurePro = Color(red: 0.0, green: 0.48, blue: 1.0)
    public static let emeraldHealthy = Color(red: 0.20, green: 0.78, blue: 0.35)
    public static let amberWarning = Color(red: 1.0, green: 0.58, blue: 0.0)
    public static let crimsonCritical = Color(red: 1.0, green: 0.23, blue: 0.19)
    public static let purpleInferred = Color(red: 0.69, green: 0.32, blue: 0.87)

    // MARK: - Surfaces
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

    // MARK: - Typography Styles
    public static func monoText(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Styled Card Modifier
public struct EngineeringCardModifier: ViewModifier {
    var padding: CGFloat = 16

    public func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Theme.borderLight, lineWidth: 1)
            )
    }
}

public extension View {
    func engineeringCard(padding: CGFloat = 16) -> some View {
        self.modifier(EngineeringCardModifier(padding: padding))
    }
}
