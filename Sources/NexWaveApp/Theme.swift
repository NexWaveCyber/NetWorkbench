import SwiftUI
import AppKit
import TerminalKit

/// Curated engineering themes for NexWave Network Workbench.
public enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    case cyberDark = "cyberDark"
    case systemNative = "systemNative"
    case midnightOLED = "midnightOLED"
    case daylightClean = "daylightClean"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .cyberDark: return "NexWave Cyber Dark"
        case .systemNative: return "macOS System Native"
        case .midnightOLED: return "Midnight OLED"
        case .daylightClean: return "Daylight Clean"
        }
    }

    public var subtitle: String {
        switch self {
        case .cyberDark: return "Obsidian slate with signature electric cyan telemetry glow"
        case .systemNative: return "Harmonizes with macOS Sequoia appearance (auto day/night)"
        case .midnightOLED: return "Pitch-black #000000 with razor-sharp contrast for XDR screens"
        case .daylightClean: return "Crisp, bright engineering paper aesthetic for daylight environments"
        }
    }

    public var iconName: String {
        switch self {
        case .cyberDark: return "sparkles"
        case .systemNative: return "macwindow"
        case .midnightOLED: return "moon.stars.fill"
        case .daylightClean: return "sun.max.fill"
        }
    }

    public var previewAccent: Color {
        switch self {
        case .cyberDark: return Color(red: 0.0, green: 0.94, blue: 1.0)
        case .systemNative: return Color(red: 0.04, green: 0.52, blue: 1.0)
        case .midnightOLED: return Color(red: 0.0, green: 0.94, blue: 1.0)
        case .daylightClean: return Color(red: 0.02, green: 0.44, blue: 0.92)
        }
    }

    public var previewBackground: Color {
        switch self {
        case .cyberDark: return Color(red: 0.07, green: 0.09, blue: 0.14)
        case .systemNative: return Color(nsColor: .windowBackgroundColor)
        case .midnightOLED: return Color.black
        case .daylightClean: return Color(red: 0.95, green: 0.96, blue: 0.98)
        }
    }
}

/// Reactive Theme Manager controlling application appearance across all workspaces.
public final class ThemeManager: ObservableObject, @unchecked Sendable {
    public static let shared = ThemeManager()

    nonisolated(unsafe) private static var _cachedTheme: AppTheme = .cyberDark

    @Published public var currentTheme: AppTheme {
        didSet {
            Self._cachedTheme = currentTheme
            UserDefaults.standard.set(currentTheme.rawValue, forKey: "workbenchTheme")
            if isLight {
                UserDefaults.standard.set(TerminalTheme.cleanLight.rawValue, forKey: "terminal_theme")
            } else {
                let existing = UserDefaults.standard.string(forKey: "terminal_theme")
                if existing == TerminalTheme.cleanLight.rawValue || existing == nil {
                    UserDefaults.standard.set(TerminalTheme.obsidian.rawValue, forKey: "terminal_theme")
                }
            }
        }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: "workbenchTheme") ?? "cyberDark"
        let resolved: AppTheme
        switch saved {
        case "obsidian", "midnightOLED":
            resolved = .midnightOLED
        case "light", "daylightClean":
            resolved = .daylightClean
        case "system", "systemNative":
            resolved = .systemNative
        case "cyberDark", "dark", "cyberpunk", "midnight":
            resolved = .cyberDark
        default:
            resolved = AppTheme(rawValue: saved) ?? .cyberDark
        }
        Self._cachedTheme = resolved
        self.currentTheme = resolved

        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            let updated = UserDefaults.standard.string(forKey: "workbenchTheme") ?? "cyberDark"
            let next: AppTheme
            switch updated {
            case "obsidian", "midnightOLED":
                next = .midnightOLED
            case "light", "daylightClean":
                next = .daylightClean
            case "system", "systemNative":
                next = .systemNative
            case "cyberDark", "dark", "cyberpunk", "midnight":
                next = .cyberDark
            default:
                next = AppTheme(rawValue: updated) ?? .cyberDark
            }
            if self.currentTheme != next {
                self.currentTheme = next
            }
        }

        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    public var activeTheme: AppTheme {
        Self._cachedTheme
    }

    public var currentColorScheme: ColorScheme? {
        switch activeTheme {
        case .cyberDark, .midnightOLED:
            return .dark
        case .daylightClean:
            return .light
        case .systemNative:
            return nil // Lets macOS dynamically adapt to the user's OS Dark/Light mode!
        }
    }

    public var isLight: Bool {
        switch activeTheme {
        case .daylightClean:
            return true
        case .cyberDark, .midnightOLED:
            return false
        case .systemNative:
            #if canImport(AppKit)
            if Thread.isMainThread {
                return MainActor.assumeIsolated {
                    NSApplication.shared.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua
                }
            } else {
                return DispatchQueue.main.sync {
                    MainActor.assumeIsolated {
                        NSApplication.shared.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua
                    }
                }
            }
            #else
            return false
            #endif
        }
    }
}

/// Design tokens and semantic styling for NexWave Network Workbench.
/// Combines Apple macOS HIG precision with high-tech engineering workstation aesthetics.
public enum Theme {
    // MARK: - Semantic Cyber & Telemetry Colors
    public static var cyanPulse: Color {
        ThemeManager.shared.isLight ? Color(red: 0.02, green: 0.48, blue: 0.90) : Color(red: 0.0, green: 0.88, blue: 1.0)
    }

    public static var neonCyan: Color {
        ThemeManager.shared.isLight ? Color(red: 0.01, green: 0.45, blue: 0.86) : Color(red: 0.0, green: 0.94, blue: 1.0)
    }

    public static let azurePro = Color(red: 0.04, green: 0.52, blue: 1.0)
    public static let electricAzure = Color(red: 0.12, green: 0.58, blue: 1.0)

    public static var emeraldHealthy: Color {
        ThemeManager.shared.isLight ? Color(red: 0.08, green: 0.58, blue: 0.28) : Color(red: 0.18, green: 0.82, blue: 0.38)
    }

    public static var signalEmerald: Color {
        ThemeManager.shared.isLight ? Color(red: 0.06, green: 0.62, blue: 0.30) : Color(red: 0.20, green: 0.88, blue: 0.42)
    }

    public static var amberWarning: Color {
        ThemeManager.shared.isLight ? Color(red: 0.82, green: 0.48, blue: 0.02) : Color(red: 1.0, green: 0.62, blue: 0.05)
    }

    public static var solarAmber: Color {
        ThemeManager.shared.isLight ? Color(red: 0.85, green: 0.52, blue: 0.05) : Color(red: 1.0, green: 0.68, blue: 0.10)
    }

    public static var crimsonCritical: Color {
        ThemeManager.shared.isLight ? Color(red: 0.85, green: 0.18, blue: 0.18) : Color(red: 1.0, green: 0.24, blue: 0.24)
    }

    public static var pulseCrimson: Color {
        ThemeManager.shared.isLight ? Color(red: 0.88, green: 0.20, blue: 0.22) : Color(red: 1.0, green: 0.28, blue: 0.30)
    }

    public static var purpleInferred: Color {
        ThemeManager.shared.isLight ? Color(red: 0.55, green: 0.22, blue: 0.82) : Color(red: 0.72, green: 0.36, blue: 0.96)
    }

    public static var quantumViolet: Color {
        ThemeManager.shared.isLight ? Color(red: 0.58, green: 0.25, blue: 0.86) : Color(red: 0.76, green: 0.40, blue: 1.0)
    }

    // MARK: - Dynamic Theme-Adaptive Surfaces & Depths
    public static var surfaceBackground: Color {
        switch ThemeManager.shared.activeTheme {
        case .cyberDark:
            return Color(red: 0.04, green: 0.05, blue: 0.08)
        case .midnightOLED:
            return Color.black
        case .daylightClean:
            return Color(red: 0.93, green: 0.94, blue: 0.96)
        case .systemNative:
            if ThemeManager.shared.isLight {
                return Color(red: 0.93, green: 0.94, blue: 0.96)
            } else {
                return Color(nsColor: .windowBackgroundColor)
            }
        }
    }

    public static var cardBackground: Color {
        switch ThemeManager.shared.activeTheme {
        case .cyberDark:
            return Color(red: 0.08, green: 0.10, blue: 0.15)
        case .midnightOLED:
            return Color(red: 0.05, green: 0.05, blue: 0.06)
        case .daylightClean:
            return Color.white
        case .systemNative:
            if ThemeManager.shared.isLight {
                return Color.white
            } else {
                return Color(nsColor: .controlBackgroundColor)
            }
        }
    }

    public static var secondaryBackground: Color {
        switch ThemeManager.shared.activeTheme {
        case .cyberDark:
            return Color(red: 0.05, green: 0.07, blue: 0.11)
        case .midnightOLED:
            return Color(red: 0.02, green: 0.02, blue: 0.03)
        case .daylightClean:
            return Color(red: 0.89, green: 0.91, blue: 0.94)
        case .systemNative:
            if ThemeManager.shared.isLight {
                return Color(red: 0.89, green: 0.91, blue: 0.94)
            } else {
                return Color(nsColor: .underPageBackgroundColor)
            }
        }
    }

    public static var elevatedCardBackground: Color {
        switch ThemeManager.shared.activeTheme {
        case .cyberDark:
            return Color(red: 0.10, green: 0.13, blue: 0.19)
        case .midnightOLED:
            return Color(red: 0.08, green: 0.08, blue: 0.09)
        case .daylightClean:
            return Color.white
        case .systemNative:
            if ThemeManager.shared.isLight {
                return Color.white
            } else {
                return Color(nsColor: .controlBackgroundColor)
            }
        }
    }

    public static var innerChipBackground: Color {
        switch ThemeManager.shared.activeTheme {
        case .cyberDark:
            return Color(red: 0.05, green: 0.07, blue: 0.11)
        case .midnightOLED:
            return Color(red: 0.03, green: 0.03, blue: 0.04)
        case .daylightClean:
            return Color(red: 0.90, green: 0.92, blue: 0.95)
        case .systemNative:
            return Color.primary.opacity(ThemeManager.shared.isLight ? 0.07 : 0.04)
        }
    }

    public static var borderLight: Color {
        switch ThemeManager.shared.activeTheme {
        case .cyberDark:
            return Color.white.opacity(0.09)
        case .midnightOLED:
            return Color.white.opacity(0.14)
        case .daylightClean:
            return Color(red: 0.78, green: 0.82, blue: 0.88)
        case .systemNative:
            return Color.primary.opacity(ThemeManager.shared.isLight ? 0.14 : 0.08)
        }
    }

    public static var borderHighlight: Color {
        switch ThemeManager.shared.activeTheme {
        case .cyberDark:
            return Color.white.opacity(0.16)
        case .midnightOLED:
            return Color.white.opacity(0.25)
        case .daylightClean:
            return Color.black.opacity(0.20)
        case .systemNative:
            return Color.primary.opacity(ThemeManager.shared.isLight ? 0.22 : 0.14)
        }
    }

    public static var glassBackground: Color {
        Color.primary.opacity(0.03)
    }

    public static var cardBorderHighContrast: Color {
        switch ThemeManager.shared.activeTheme {
        case .cyberDark:
            return Color.white.opacity(0.14)
        case .midnightOLED:
            return Color.white.opacity(0.24)
        case .daylightClean:
            return Color.black.opacity(0.12)
        case .systemNative:
            return Color.primary.opacity(0.12)
        }
    }

    public static var primaryAccent: Color {
        switch ThemeManager.shared.activeTheme {
        case .cyberDark:
            return neonCyan
        case .midnightOLED:
            return neonCyan
        case .daylightClean:
            return Color(red: 0.01, green: 0.44, blue: 0.88)
        case .systemNative:
            return ThemeManager.shared.isLight ? Color(red: 0.01, green: 0.44, blue: 0.88) : azurePro
        }
    }

    public static var obsidianDark: Color {
        Color(red: 0.04, green: 0.05, blue: 0.08)
    }

    // MARK: - Gradients
    public static var titleGradient: LinearGradient {
        if ThemeManager.shared.isLight {
            return LinearGradient(
                colors: [Color(red: 0.08, green: 0.12, blue: 0.20), Color(red: 0.20, green: 0.26, blue: 0.36)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [.white, Color.white.opacity(0.88)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    public static var cyanGlowGradient: LinearGradient {
        if ThemeManager.shared.isLight {
            return LinearGradient(
                colors: [Color(red: 0.02, green: 0.44, blue: 0.92), Color(red: 0.05, green: 0.32, blue: 0.80)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [neonCyan, azurePro],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
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

    public static var ambientMeshView: some View {
        ZStack {
            switch ThemeManager.shared.activeTheme {
            case .cyberDark:
                Color(red: 0.04, green: 0.05, blue: 0.08)
                RadialGradient(
                    colors: [Color(red: 0.0, green: 0.28, blue: 0.42).opacity(0.16), Color.clear],
                    center: .topLeading,
                    startRadius: 80,
                    endRadius: 750
                )
                RadialGradient(
                    colors: [Color(red: 0.15, green: 0.05, blue: 0.35).opacity(0.12), Color.clear],
                    center: .bottomTrailing,
                    startRadius: 100,
                    endRadius: 800
                )
                RadialGradient(
                    colors: [Color(red: 0.0, green: 0.35, blue: 0.30).opacity(0.08), Color.clear],
                    center: .center,
                    startRadius: 50,
                    endRadius: 600
                )

            case .midnightOLED:
                Color.black

            case .daylightClean:
                Color(red: 0.95, green: 0.96, blue: 0.98)
                RadialGradient(
                    colors: [Color(red: 0.0, green: 0.44, blue: 0.92).opacity(0.04), Color.clear],
                    center: .topLeading,
                    startRadius: 80,
                    endRadius: 750
                )

            case .systemNative:
                Color(nsColor: .windowBackgroundColor)
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Typography Styles
    public static func monoText(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    public static func terminalFont(family: String, size: CGFloat, weight: Font.Weight = .regular, isItalic: Bool = false) -> Font {
        let cleanFamily = family.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanFamily.isEmpty || cleanFamily == "SF Mono (System)" || cleanFamily == "SF Mono" || cleanFamily == "System Monospaced" {
            var f = Font.system(size: size, weight: weight, design: .monospaced)
            if isItalic { f = f.italic() }
            return f
        } else {
            let resolvedName = TerminalFontFamily(rawValue: cleanFamily)?.fontName ?? cleanFamily
            var f = Font.custom(resolvedName, size: size)
            if weight == .bold { f = f.bold() }
            if isItalic { f = f.italic() }
            return f
        }
    }
}

// MARK: - Continuous Pulsing Beacon
public struct PulsingBeacon: View {
    let color: Color
    var size: CGFloat = 8
    var isLive: Bool = true

    public init(color: Color, size: CGFloat = 8, isLive: Bool = true) {
        self.color = color
        self.size = size
        self.isLive = isLive
    }

    public var body: some View {
        ZStack {
            if isLive {
                Circle()
                    .fill(color.opacity(0.35))
                    .frame(width: size * 2.1, height: size * 2.1)
            }
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .shadow(color: isLive ? color.opacity(0.6) : .clear, radius: 4)
        }
    }
}

// MARK: - Reusable Metric Stat Capsule
public struct MetricStatCard: View {
    let title: String
    let value: String
    let unit: String
    let statusColor: Color
    var icon: String? = nil
    var delta: String? = nil
    var deltaIsPositive: Bool = true

    public init(
        title: String,
        value: String,
        unit: String = "",
        statusColor: Color = Theme.signalEmerald,
        icon: String? = nil,
        delta: String? = nil,
        deltaIsPositive: Bool = true
    ) {
        self.title = title
        self.value = value
        self.unit = unit
        self.statusColor = statusColor
        self.icon = icon
        self.delta = delta
        self.deltaIsPositive = deltaIsPositive
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(statusColor)
                }
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                if let delta = delta {
                    HStack(spacing: 2) {
                        Image(systemName: deltaIsPositive ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 9, weight: .bold))
                        Text(delta)
                            .font(Theme.monoText(10, weight: .bold))
                    }
                    .foregroundStyle(deltaIsPositive ? Theme.signalEmerald : Theme.solarAmber)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(Capsule())
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundStyle(.primary)

                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Theme.borderLight, lineWidth: 1)
        )
    }
}

// MARK: - Advanced Engineering Card Modifier with Smooth Hover Lift
public struct EngineeringCardModifier: ViewModifier {
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 12
    var hasHoverEffect: Bool = false
    var accentBorder: Color? = nil
    
    @ObservedObject private var themeManager = ThemeManager.shared
    @State private var isHovered = false

    public func body(content: Content) -> some View {
        let isLight = themeManager.isLight
        let cardBg = Theme.cardBackground
        let strokeColor = accentBorder ?? (isHovered ? Theme.primaryAccent.opacity(0.45) : Theme.borderLight)
        let strokeWidth: CGFloat = (hasHoverEffect && isHovered) ? 1.5 : 1.0

        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(cardBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(strokeColor, lineWidth: strokeWidth)
            )
            .modifier(CardInteractiveLiftModifier(
                hasHoverEffect: hasHoverEffect,
                isHovered: $isHovered,
                isLight: isLight,
                accentColor: Theme.primaryAccent
            ))
    }
}

private struct CardInteractiveLiftModifier: ViewModifier {
    let hasHoverEffect: Bool
    @Binding var isHovered: Bool
    let isLight: Bool
    let accentColor: Color

    func body(content: Content) -> some View {
        if hasHoverEffect {
            content
                .scaleEffect(isHovered ? 1.01 : 1.0)
                .shadow(
                    color: isHovered ? accentColor.opacity(isLight ? 0.14 : 0.18) : Color.black.opacity(isLight ? 0.06 : 0.08),
                    radius: isHovered ? 8 : 3,
                    x: 0,
                    y: isHovered ? 3 : 1.5
                )
                .onHover { hovering in
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                        isHovered = hovering
                    }
                }
        } else {
            content
                .shadow(
                    color: Color.black.opacity(isLight ? 0.05 : 0.07),
                    radius: 3,
                    x: 0,
                    y: 1.5
                )
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
                            colors: [Color.white.opacity(0.18), Color.white.opacity(0.04)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 3)
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
            if isPulsing {
                PulsingBeacon(color: color, size: 6, isLive: true)
            } else if let icon = icon {
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
                .strokeBorder(color.opacity(0.28), lineWidth: 0.75)
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
