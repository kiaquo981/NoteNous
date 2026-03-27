import SwiftUI

// MARK: - MOROS Design System

/// The MOROS Design System — a dark-only, sharp-cornered, glow-based visual language.
/// All colors, typography, spacing, and animation constants for NoteNous.
enum Moros {

    // MARK: - Color Primitives (9)

    /// #000000 — absolute black background
    static let void = Color(red: 0, green: 0, blue: 0)
    /// #06060a — base surface
    static let limit01 = Color(red: 0.024, green: 0.024, blue: 0.039)
    /// #0b0b11 — elevated surface
    static let limit02 = Color(red: 0.043, green: 0.043, blue: 0.067)
    /// #121219 — hover state
    static let limit03 = Color(red: 0.071, green: 0.071, blue: 0.098)
    /// #191921 — active/selected
    static let limit04 = Color(red: 0.098, green: 0.098, blue: 0.129)
    /// #8899bb — idle/neutral text
    static let ambient = Color(red: 0.533, green: 0.6, blue: 0.733)
    /// #cc2233 — alert/active/error
    static let signal = Color(red: 0.8, green: 0.133, blue: 0.2)
    /// #4477cc — processing/info/accent
    static let oracle = Color(red: 0.267, green: 0.467, blue: 0.8)
    /// #c8d4f0 — output/resolution/success
    static let verdit = Color(red: 0.784, green: 0.831, blue: 0.941)

    // MARK: - Text Colors (White Opacity-Based)

    /// rgba(255,255,255,0.92)
    static let textMain = Color.white.opacity(0.92)
    /// rgba(255,255,255,0.68)
    static let textSub = Color.white.opacity(0.68)
    /// rgba(255,255,255,0.45)
    static let textDim = Color.white.opacity(0.45)
    /// rgba(255,255,255,0.14)
    static let textGhost = Color.white.opacity(0.14)

    // MARK: - Border Colors

    /// rgba(255,255,255,0.03)
    static let borderDim = Color.white.opacity(0.03)
    /// rgba(255,255,255,0.06)
    static let border = Color.white.opacity(0.06)
    /// rgba(255,255,255,0.11)
    static let borderLit = Color.white.opacity(0.11)

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

/// Applies the MOROS VOID background to a view.
struct MorosBackground: ViewModifier {
    var surface: Color = Moros.void

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
