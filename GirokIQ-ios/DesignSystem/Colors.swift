import SwiftUI

// MARK: - GirokIQ Color Tokens

extension Color {

    // MARK: - Backgrounds (adaptive light/dark)

    /// Deepest background — near-black in dark, off-white in light
    static let gBackground = Color(light: Color(hex: "#F8F8FA"), dark: Color(hex: "#0F0F0E"))
    /// Cards, sheets
    static let gSurface = Color(light: Color(hex: "#FFFFFF"), dark: Color(hex: "#1A1A1A"))
    /// Hover, selected states
    static let gElevated = Color(light: Color(hex: "#F0F0F5"), dark: Color(hex: "#262626"))
    /// Modals, overlays
    static let gOverlay = Color(light: Color(hex: "#E8E8ED"), dark: Color(hex: "#2C2C35"))

    // MARK: - Brand

    /// Warm gold — main accent
    static let gPrimary = Color(hex: "#C9A84C")
    /// Primary at 15% opacity for subtle highlights
    static let gPrimaryMuted = Color(hex: "#C9A84C").opacity(0.15)
    /// Deep ink blue — secondary accent
    static let gSecondary = Color(hex: "#3D5A80")

    // MARK: - Semantic

    static let gSuccess = Color(hex: "#34D399")
    static let gWarning = Color(hex: "#FBBF24")
    static let gDestructive = Color(hex: "#F87171")

    // MARK: - Text (adaptive light/dark)

    static let gTextPrimary = Color(light: Color(hex: "#0D0D0F"), dark: .white)
    static let gTextSecondary = Color(light: Color(white: 0.4), dark: Color(white: 0.6))
    static let gTextTertiary = Color(light: Color(white: 0.55), dark: Color(white: 0.35))

    // MARK: - Borders (adaptive light/dark)

    static let gBorder = Color(light: Color(white: 0.85), dark: Color(white: 0.15))
    static let gBorderStrong = Color(light: Color(white: 0.75), dark: Color(white: 0.25))
}

// MARK: - Resolved Color Helpers (for contexts without asset catalog)

extension Color {

    /// Returns the appropriate background color for the given color scheme
    static func gBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "#0F0F0E") : Color(hex: "#F8F8FA")
    }

    static func gSurface(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "#1A1A1A") : Color(hex: "#FFFFFF")
    }

    static func gElevated(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "#262626") : Color(hex: "#F0F0F5")
    }

    static func gOverlay(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "#2C2C35") : Color(hex: "#E8E8ED")
    }

    static func gTextPrimary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? .white : Color(hex: "#0D0D0F")
    }

    static func gTextSecondary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.6) : Color(white: 0.4)
    }

    static func gTextTertiary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.35) : Color(white: 0.55)
    }

    static func gBorder(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.15) : Color(white: 0.85)
    }

    static func gBorderStrong(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.25) : Color(white: 0.75)
    }
}

// MARK: - Notebook Cover Colors

extension Color {
    static let notebookCovers: [Color] = [
        Color(hex: "#6366F1"),
        Color(hex: "#8B5CF6"),
        Color(hex: "#EC4899"),
        Color(hex: "#F87171"),
        Color(hex: "#FB923C"),
        Color(hex: "#FBBF24"),
        Color(hex: "#34D399"),
        Color(hex: "#06B6D4"),
        Color(hex: "#60A5FA"),
        Color(hex: "#A78BFA")
    ]
}
