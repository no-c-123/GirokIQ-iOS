import SwiftUI
import Combine

// MARK: - ThemeManager

/// Centralized theme manager that bridges the design tokens with runtime color scheme.
/// Use via @EnvironmentObject for views that need reactive theme changes.
/// For static token access, use Color.gPrimary, Font.gBody, GSpacing.md etc. directly.
final class ThemeManager: ObservableObject {
    @Published var colorScheme: ColorScheme = .dark

    var isDark: Bool { colorScheme == .dark }

    // MARK: - Resolved Colors

    var backgroundColor: Color { .gBackground(for: colorScheme) }
    var surfaceColor: Color { .gSurface(for: colorScheme) }
    var elevatedSurface: Color { .gElevated(for: colorScheme) }
    var overlayColor: Color { .gOverlay(for: colorScheme) }
    var primaryColor: Color { .gPrimary }
    var secondaryColor: Color { .gSecondary }
    var textPrimary: Color { .gTextPrimary(for: colorScheme) }
    var textSecondary: Color { .gTextSecondary(for: colorScheme) }
    var textTertiary: Color { .gTextTertiary(for: colorScheme) }
    var borderColor: Color { .gBorder(for: colorScheme) }
    var borderStrong: Color { .gBorderStrong(for: colorScheme) }
}
