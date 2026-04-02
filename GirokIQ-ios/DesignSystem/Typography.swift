import SwiftUI

// MARK: - GirokIQ Typography Tokens
// Uses SF Pro (system default). All tokens scale with Dynamic Type
// via the `.relativeTo:` text style parameter.

extension Font {
    // Primary type scale — scales automatically with Accessibility settings
    static let gLargeTitle  = Font.system(size: 34, weight: .bold, design: .rounded).leading(.tight)
    static let gTitle1      = Font.system(size: 28, weight: .bold, design: .rounded).leading(.tight)
    static let gTitle2      = Font.system(size: 22, weight: .semibold, design: .rounded)
    static let gTitle3      = Font.system(size: 18, weight: .semibold)
    static let gHeadline    = Font.system(size: 17, weight: .semibold)
    static let gBody        = Font.system(size: 17, weight: .regular)
    static let gCallout     = Font.system(size: 16, weight: .regular)
    static let gSubheadline = Font.system(size: 15, weight: .regular)
    static let gFootnote    = Font.system(size: 13, weight: .regular)
    static let gCaption     = Font.system(size: 12, weight: .regular)
    static let gCaption2    = Font.system(size: 11, weight: .regular)

    // Emoji display sizes — don't need to scale with Dynamic Type
    static let gEmojiLarge  = Font.system(size: 40)
    static let gEmojiMedium = Font.system(size: 32)
    static let gEmojiSmall  = Font.system(size: 22)

    // Icon sizes for toolbar contexts
    static let gIconSmall   = Font.system(size: 14, weight: .semibold)
    static let gIconMedium  = Font.system(size: 15, weight: .medium)
    static let gIconLarge   = Font.system(size: 16, weight: .medium)
}

// MARK: - Monospaced variant for numeric displays

extension Font {
    static let gMonoCaption = Font.system(size: 11, weight: .medium, design: .monospaced)
    static let gMonoBody    = Font.system(size: 15, weight: .regular, design: .monospaced)
}

// MARK: - Scaled spacing for Dynamic Type contexts

/// Use these in views where spacing should scale with text size
struct GScaledSpacing {
    @ScaledMetric(relativeTo: .body) var xs: CGFloat = 8
    @ScaledMetric(relativeTo: .body) var sm: CGFloat = 12
    @ScaledMetric(relativeTo: .body) var md: CGFloat = 16
    @ScaledMetric(relativeTo: .body) var lg: CGFloat = 20
}
