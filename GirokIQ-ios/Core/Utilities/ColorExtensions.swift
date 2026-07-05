import SwiftUI
import UIKit

// MARK: - Color Hex Initializer

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: Double(a)/255)
    }

    var hexString: String {
        let ui = UIColor(self)

        func byte(_ x: CGFloat) -> Int {
            Int((x * 255).rounded()).clamped(to: 0...255)
        }

        var rF: CGFloat = 0
        var gF: CGFloat = 0
        var bF: CGFloat = 0
        var aF: CGFloat = 1

        // Prefer getRed(...) because it reliably converts to sRGB and avoids
        // precision issues that can happen when reading cgColor.components.
        if ui.getRed(&rF, green: &gF, blue: &bF, alpha: &aF) {
            return String(format: "#%02X%02X%02X", byte(rF), byte(gF), byte(bF))
        }

        let components = ui.cgColor.components ?? [0, 0, 0, 1]
        if components.count >= 3 {
            rF = components[0]
            gF = components[1]
            bF = components[2]
        } else if components.count == 2 {
            rF = components[0]
            gF = components[0]
            bF = components[0]
        } else {
            rF = 0
            gF = 0
            bF = 0
        }

        return String(format: "#%02X%02X%02X", byte(rF), byte(gF), byte(bF))
    }
}

// MARK: - Adaptive Light/Dark Color Initializer

extension Color {
    /// Creates a color that adapts to light/dark mode using UIColor dynamic provider.
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}

// MARK: - UIColor Hex Initializer

extension UIColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        self.init(
            red: CGFloat((int >> 16) & 0xFF) / 255,
            green: CGFloat((int >> 8) & 0xFF) / 255,
            blue: CGFloat(int & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - UIColor Design Tokens (for UIKit / Core Graphics interop)

extension UIColor {
    // Backgrounds
    static let gBackground = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(hex: "#0F0F0E") : UIColor(hex: "#F8F8FA")
    }
    static let gSurface = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(hex: "#1A1A1A") : UIColor(hex: "#FFFFFF")
    }
    static let gElevated = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(hex: "#262626") : UIColor(hex: "#F0F0F5")
    }

    // Brand
    static let gPrimary       = UIColor(hex: "#C9A84C")
    static let gPrimaryMuted  = UIColor(hex: "#C9A84C").withAlphaComponent(0.15)

    // Semantic
    static let gDestructive   = UIColor(hex: "#F87171")
    static let gTextPrimary = UIColor { traits in
        traits.userInterfaceStyle == .dark ? .white : UIColor(hex: "#0D0D0F")
    }
    static let gTextSecondary = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 0.72, alpha: 1) : UIColor(hex: "#4B5563")
    }

    // Borders
    static let gBorder = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 0.15, alpha: 1) : UIColor(white: 0.85, alpha: 1)
    }
    static let gBorderStrong = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 0.25, alpha: 1) : UIColor(white: 0.75, alpha: 1)
    }

    // Grid / Pattern
    static let gGridLine = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.08) : UIColor(white: 0, alpha: 0.08)
    }
    static let gDot = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.18) : UIColor(white: 0, alpha: 0.18)
    }

    // Selection highlight
    static let gSelectionHalo = UIColor(hex: "#6366F1").withAlphaComponent(0.35)

    // Lasso
    static let gLasso         = UIColor(hex: "#6366F1")
}

// MARK: - Comparable Clamping

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
