import SwiftUI

// MARK: - MOROS Design System (iOS Adaptation)

/// iOS-adapted MOROS Design System — same visual language, optimized for touch.
/// Larger touch targets, safe area awareness, iOS-appropriate type scale.
enum MorosIOS {

    // MARK: - Color Primitives (same as macOS)

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

    static let textMain = Color.white.opacity(0.92)
    static let textSub = Color.white.opacity(0.68)
    static let textDim = Color.white.opacity(0.45)
    static let textGhost = Color.white.opacity(0.14)

    // MARK: - Border Colors

    static let borderDim = Color.white.opacity(0.03)
    static let border = Color.white.opacity(0.06)
    static let borderLit = Color.white.opacity(0.11)

    // MARK: - Type Scale (iOS adapted — larger for touch)

    static let fontHero: Font = .system(size: 48, weight: .light)
    static let fontDisplay: Font = .system(size: 34, weight: .light)
    static let fontH1: Font = .system(size: 28, weight: .light)
    static let fontH2: Font = .system(size: 22, weight: .light)
    static let fontH3: Font = .system(size: 18, weight: .regular)
    static let fontSubhead: Font = .system(size: 16, weight: .regular)
    static let fontBody: Font = .system(size: 15, weight: .regular)
    static let fontSmall: Font = .system(size: 13, weight: .regular)
    static let fontCaption: Font = .system(size: 12, weight: .regular)
    static let fontLabel: Font = .system(size: 11, weight: .medium)
    static let fontMicro: Font = .system(size: 10, weight: .medium)

    static let fontMono: Font = .system(size: 13, weight: .regular, design: .monospaced)
    static let fontMonoSmall: Font = .system(size: 11, weight: .regular, design: .monospaced)

    // MARK: - Spacing (4pt grid, iOS adapted)

    static let spacing4: CGFloat = 4
    static let spacing8: CGFloat = 8
    static let spacing12: CGFloat = 12
    static let spacing16: CGFloat = 16
    static let spacing20: CGFloat = 20
    static let spacing24: CGFloat = 24
    static let spacing32: CGFloat = 32

    // MARK: - Touch Targets (minimum 44pt)

    static let touchTargetMin: CGFloat = 44
    static let buttonHeight: CGFloat = 50
    static let cardPadding: CGFloat = 16

    // MARK: - Animation

    static let animFast: Double = 0.15
    static let animBase: Double = 0.25
    static let animSlow: Double = 0.4

    // MARK: - Age Colors (for inbox items)

    static func ageColor(for date: Date?) -> Color {
        guard let date = date else { return ambient }
        let hours = Date().timeIntervalSince(date) / 3600
        if hours < 24 { return verdit }      // green — fresh
        if hours < 72 { return oracle }       // blue — aging
        return signal                         // red — stale
    }
}

// MARK: - iOS View Modifiers

struct MorosIOSBackground: ViewModifier {
    var surface: Color = MorosIOS.void

    func body(content: Content) -> some View {
        content
            .background(surface.ignoresSafeArea())
    }
}

struct MorosIOSGlow: ViewModifier {
    let color: Color
    var radius: CGFloat = 8

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(0.4), radius: radius, x: 0, y: 0)
    }
}

extension View {
    func morosIOSBackground(_ surface: Color = MorosIOS.void) -> some View {
        modifier(MorosIOSBackground(surface: surface))
    }

    func morosIOSGlow(_ color: Color, radius: CGFloat = 8) -> some View {
        modifier(MorosIOSGlow(color: color, radius: radius))
    }
}
