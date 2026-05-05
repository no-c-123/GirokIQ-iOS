import SwiftUI

// MARK: - GButton

/// Primary reusable button component for GirokIQ
struct GButton: View {
    let title: String
    let style: Style
    var isLoading: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    enum Style {
        case primary
        case secondary
        case destructive
        case ghost
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                background
                if isLoading {
                    ProgressView()
                        .tint(foregroundColor)
                } else {
                    Text(title)
                        .font(.gHeadline)
                        .foregroundColor(foregroundColor)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
        }
        .disabled(isDisabled || isLoading)
        .opacity(isDisabled ? 0.6 : 1.0)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Private

    @ViewBuilder
    private var background: some View {
        switch style {
        case .primary:
            RoundedRectangle(cornerRadius: GRadius.sm, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.gPrimary, .gSecondary],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        case .secondary:
            RoundedRectangle(cornerRadius: GRadius.sm, style: .continuous)
                .fill(Color.gPrimary.opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: GRadius.sm, style: .continuous)
                        .stroke(Color.gPrimary.opacity(0.3), lineWidth: 1)
                )
        case .destructive:
            RoundedRectangle(cornerRadius: GRadius.sm, style: .continuous)
                .fill(Color.gDestructive)
        case .ghost:
            RoundedRectangle(cornerRadius: GRadius.sm, style: .continuous)
                .fill(Color.clear)
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .primary, .destructive:
            return .white
        case .secondary:
            return .gPrimary
        case .ghost:
            return .gPrimary
        }
    }
}

// MARK: - GTextField

/// Styled text field matching GirokIQ design system
struct GTextField: View {
    let placeholder: String
    @Binding var text: String
    var systemIcon: String? = nil
    var keyboardType: UIKeyboardType = .default
    var isSecure: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: GSpacing.sm) {
            if let icon = systemIcon {
                Image(systemName: icon)
                    .font(.gSubheadline)
                    .foregroundColor(.gTextSecondary)
                    .frame(width: 20)
            }

            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboardType)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                }
            }
            .font(.gSubheadline)
            .foregroundColor(.gTextPrimary)
        }
        .padding(.horizontal, GSpacing.md)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: GRadius.sm, style: .continuous)
                .fill(Color.gElevated.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: GRadius.sm, style: .continuous)
                        .stroke(Color.gBorder, lineWidth: 0.5)
                )
        )
    }
}

// MARK: - GCard

/// Card container matching GirokIQ design system
struct GCard<Content: View>: View {
    var cornerRadius: CGFloat = GRadius.md
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.gSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.gBorder, lineWidth: 0.5)
                    )
            )
    }
}

// MARK: - Scale Button Style

struct GScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(GAnimation.springFast, value: configuration.isPressed)
    }
}
