import SwiftUI

// MARK: - GirokIQ Spacing Tokens

enum GSpacing {
    static let xxs:  CGFloat = 4
    static let xs:   CGFloat = 8
    static let sm:   CGFloat = 12
    static let md:   CGFloat = 16
    static let lg:   CGFloat = 20
    static let xl:   CGFloat = 24
    static let xxl:  CGFloat = 32
    static let xxxl: CGFloat = 48
}

// MARK: - GirokIQ Corner Radius Tokens

enum GRadius {
    static let xs:   CGFloat = 6
    static let sm:   CGFloat = 10
    static let md:   CGFloat = 14
    static let lg:   CGFloat = 18
    static let xl:   CGFloat = 24
    static let pill: CGFloat = 999
}

// MARK: - Animation Constants

enum GAnimation {
    /// Standard interactive spring — use for buttons, toggles, panels
    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.82)

    /// Quick spring for micro-interactions
    static let springFast = Animation.spring(response: 0.25, dampingFraction: 0.82)

    /// Gentle spring for page transitions, large movements
    static let springGentle = Animation.spring(response: 0.45, dampingFraction: 0.82)

    /// Returns instant (no animation) when Reduce Motion is enabled, otherwise the given animation
    static func motionSafe(_ animation: Animation = GAnimation.spring) -> Animation? {
        UIAccessibility.isReduceMotionEnabled ? .none : animation
    }
}
