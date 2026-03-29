import SwiftUI

// MARK: - Theme Mode

enum MorosThemeMode: String, CaseIterable, Identifiable {
    case auto = "Auto"
    case dark = "Dark"
    case light = "Light"

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .auto: return nil  // follows system
        case .dark: return .dark
        case .light: return .light
        }
    }

    var icon: String {
        switch self {
        case .auto: return "circle.lefthalf.filled"
        case .dark: return "moon.fill"
        case .light: return "sun.max.fill"
        }
    }

    static var current: MorosThemeMode {
        let raw = UserDefaults.standard.string(forKey: "morosThemeMode") ?? "Auto"
        return MorosThemeMode(rawValue: raw) ?? .auto
    }

    static func setCurrent(_ mode: MorosThemeMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: "morosThemeMode")
    }
}

// MARK: - Adaptive Colors

/// Resolves MOROS colors based on current color scheme (dark or light).
/// Since Moros static colors now use system-adaptive NSColors, these simply delegate.
struct MorosAdaptive {
    let colorScheme: ColorScheme

    // Backgrounds — already adaptive via NSColor
    var void: Color { Moros.void }
    var limit01: Color { Moros.limit01 }
    var limit02: Color { Moros.limit02 }
    var limit03: Color { Moros.limit03 }
    var limit04: Color { Moros.limit04 }

    // Text — already adaptive via NSColor
    var textMain: Color { Moros.textMain }
    var textSub: Color { Moros.textSub }
    var textDim: Color { Moros.textDim }
    var textGhost: Color { Moros.textGhost }

    // Borders — already adaptive via NSColor
    var border: Color { Moros.border }
    var borderLit: Color { Moros.borderLit }

    // Accent colors stay the same in both modes
    var oracle: Color { Moros.oracle }
    var signal: Color { Moros.signal }
    var verdit: Color { Moros.verdit }
    var ambient: Color { Moros.ambient }
}

// MARK: - Environment Key

private struct MorosAdaptiveKey: EnvironmentKey {
    static let defaultValue = MorosAdaptive(colorScheme: .dark)
}

extension EnvironmentValues {
    var moros: MorosAdaptive {
        get { self[MorosAdaptiveKey.self] }
        set { self[MorosAdaptiveKey.self] = newValue }
    }
}

// MARK: - Theme Modifier

struct MorosThemeModifier: ViewModifier {
    @Environment(\.colorScheme) private var systemColorScheme
    @AppStorage("morosThemeMode") private var themeMode: String = "Auto"

    private var effectiveScheme: ColorScheme {
        let mode = MorosThemeMode(rawValue: themeMode) ?? .auto
        switch mode {
        case .auto: return systemColorScheme
        case .dark: return .dark
        case .light: return .light
        }
    }

    func body(content: Content) -> some View {
        let mode = MorosThemeMode(rawValue: themeMode) ?? .auto
        content
            .environment(\.moros, MorosAdaptive(colorScheme: effectiveScheme))
            .preferredColorScheme(mode.colorScheme)
    }
}

extension View {
    func morosTheme() -> some View {
        modifier(MorosThemeModifier())
    }
}

// MARK: - MOROS Design System

/// The MOROS Design System — adaptive visual language using macOS native colors.
/// All background and text colors adapt automatically to light/dark mode.
/// Accent colors (oracle, signal, verdit, ambient) are brand colors and stay consistent.
enum Moros {

    // MARK: - Color Primitives (system-adaptive backgrounds)

    /// Window background — adapts to light/dark
    static let void = Color(NSColor.windowBackgroundColor)
    /// Base surface
    static let limit01 = Color(NSColor.windowBackgroundColor)
    /// Elevated surface
    static let limit02 = Color(NSColor.controlBackgroundColor)
    /// Hover/active state
    static let limit03 = Color(NSColor.unemphasizedSelectedContentBackgroundColor)
    /// Selected state
    static let limit04 = Color(NSColor.selectedContentBackgroundColor)

    // MARK: - Accent Colors (brand — same in both modes)

    /// #8899bb — idle/neutral text
    static let ambient = Color(red: 0.533, green: 0.6, blue: 0.733)
    /// #cc2233 — alert/active/error
    static let signal = Color(red: 0.8, green: 0.133, blue: 0.2)
    /// #4477cc — processing/info/accent
    static let oracle = Color(red: 0.267, green: 0.467, blue: 0.8)
    /// #c8d4f0 — output/resolution/success
    static let verdit = Color(red: 0.784, green: 0.831, blue: 0.941)

    // MARK: - Text Colors (system-adaptive)

    /// Primary text — adapts to light/dark
    static let textMain = Color(NSColor.labelColor)
    /// Secondary text
    static let textSub = Color(NSColor.secondaryLabelColor)
    /// Tertiary text
    static let textDim = Color(NSColor.tertiaryLabelColor)
    /// Quaternary text
    static let textGhost = Color(NSColor.quaternaryLabelColor)

    // MARK: - Border Colors (system-adaptive)

    /// Subtle separator
    static let borderDim = Color(NSColor.separatorColor).opacity(0.5)
    /// Standard separator
    static let border = Color(NSColor.separatorColor)
    /// Emphasized separator
    static let borderLit = Color(NSColor.separatorColor)

    // MARK: - Type Scale (macOS adapted)

    static let fontHero: Font = .system(size: 58, weight: .light)
    static let fontDisplay: Font = .system(size: 38, weight: .light)
    static let fontH1: Font = .system(size: 29, weight: .light)
    static let fontH2: Font = .system(size: 24, weight: .light)
    static let fontH3: Font = .system(size: 19, weight: .regular)
    static let fontSubhead: Font = .system(size: 16, weight: .regular)
    static let fontBody: Font = .system(size: 13, weight: .regular)
    static let fontSmall: Font = .system(size: 11, weight: .regular)
    static let fontCaption: Font = .system(size: 10, weight: .regular)
    static let fontLabel: Font = .system(size: 9, weight: .medium)
    static let fontMicro: Font = .system(size: 8, weight: .medium)

    /// Monospaced variant for data/labels/zettelIds
    static let fontMono: Font = .system(size: 11, weight: .regular, design: .monospaced)
    static let fontMonoSmall: Font = .system(size: 9, weight: .regular, design: .monospaced)
    static let fontMonoCaption: Font = .system(size: 10, weight: .regular, design: .monospaced)

    // MARK: - Spacing (4pt grid)

    static let spacing2: CGFloat = 2
    static let spacing4: CGFloat = 4
    static let spacing8: CGFloat = 8
    static let spacing12: CGFloat = 12
    static let spacing16: CGFloat = 16
    static let spacing20: CGFloat = 20
    static let spacing24: CGFloat = 24
    static let spacing32: CGFloat = 32

    // MARK: - Animation Durations

    static let animInstant: Double = 0.08
    static let animFast: Double = 0.15
    static let animBase: Double = 0.25
    static let animSlow: Double = 0.4
    static let animRitual: Double = 0.7

    // MARK: - Glow Effect Helper

    /// Creates a glow shadow effect using the MOROS glow system (colored blur, no drop shadows).
    static func glow(color: Color, radius: CGFloat = 8, x: CGFloat = 0, y: CGFloat = 0) -> some View {
        // Returns a clear view — use as .background(Moros.glow(...))
        // Instead, use the ViewModifier below
        Color.clear
    }
}

// MARK: - View Modifiers

/// Applies the MOROS background to a view. Colors are already system-adaptive.
struct MorosBackground: ViewModifier {
    var surface: Color = Color(NSColor.windowBackgroundColor)

    func body(content: Content) -> some View {
        content
            .background(surface)
    }
}

/// Applies a MOROS glow effect (shadow with colored blur).
struct MorosGlow: ViewModifier {
    let color: Color
    var radius: CGFloat = 8

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(0.4), radius: radius, x: 0, y: 0)
    }
}

extension View {
    /// Apply MOROS void background
    func morosBackground(_ surface: Color = Moros.void) -> some View {
        modifier(MorosBackground(surface: surface))
    }

    /// Apply MOROS glow effect
    func morosGlow(_ color: Color, radius: CGFloat = 8) -> some View {
        modifier(MorosGlow(color: color, radius: radius))
    }
}
