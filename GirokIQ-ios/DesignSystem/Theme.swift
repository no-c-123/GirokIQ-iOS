import SwiftUI
import Combine

// MARK: - AppTheme

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    
    var colorSchemeOverride: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - ThemeManager

/// Centralized theme manager that bridges the design tokens with runtime color scheme.
/// Use via @EnvironmentObject for views that need reactive theme changes.
/// For static token access, use Color.gPrimary, Font.gBody, GSpacing.md etc. directly.
final class ThemeManager: ObservableObject {
    @AppStorage("appTheme") var appTheme: AppTheme = .dark {
        didSet {
            objectWillChange.send()
        }
    }

    var colorSchemeOverride: ColorScheme? {
        appTheme.colorSchemeOverride
    }
}
