import SwiftUI

// MARK: - Standard Animations

extension Animation {
    /// Snappy spring for UI interactions (buttons, toggles, selections)
    static let morosSnap = Animation.spring(response: 0.3, dampingFraction: 0.8)

    /// Smooth spring for panels opening/closing
    static let morosPanel = Animation.spring(response: 0.4, dampingFraction: 0.85)

    /// Gentle spring for content transitions
    static let morosGentle = Animation.spring(response: 0.5, dampingFraction: 0.9)

    /// Quick for micro-interactions (hover, press states)
    static let morosMicro = Animation.easeOut(duration: 0.15)

    /// Slow for dramatic reveals
    static let morosReveal = Animation.spring(response: 0.6, dampingFraction: 0.85)
}

// MARK: - Transition Presets

extension AnyTransition {
    /// Slide from right with fade
    static let morosSlideIn = AnyTransition.asymmetric(
        insertion: .move(edge: .trailing).combined(with: .opacity),
        removal: .move(edge: .trailing).combined(with: .opacity)
    )

    /// Scale up from center with fade
    static let morosScale = AnyTransition.asymmetric(
        insertion: .scale(scale: 0.9).combined(with: .opacity),
        removal: .scale(scale: 0.95).combined(with: .opacity)
    )

    /// Slide down with fade (for panels/dropdowns)
    static let morosDropDown = AnyTransition.asymmetric(
        insertion: .move(edge: .top).combined(with: .opacity),
        removal: .move(edge: .top).combined(with: .opacity)
    )

    /// Fade only
    static let morosFade = AnyTransition.opacity
}

// MARK: - View Modifiers for Motion

struct HoverScale: ViewModifier {
    @State private var isHovered = false
    var scale: CGFloat = 1.02

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? scale : 1.0)
            .animation(.morosSnap, value: isHovered)
            .onHover { isHovered = $0 }
    }
}

struct PressEffect: ViewModifier {
    @State private var isPressed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .opacity(isPressed ? 0.8 : 1.0)
            .animation(.morosMicro, value: isPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { _ in isPressed = false }
            )
    }
}

extension View {
    func hoverScale(_ scale: CGFloat = 1.02) -> some View {
        modifier(HoverScale(scale: scale))
    }

    func pressEffect() -> some View {
        modifier(PressEffect())
    }
}
