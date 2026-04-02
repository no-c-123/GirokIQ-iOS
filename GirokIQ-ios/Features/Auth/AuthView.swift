import SwiftUI

struct AuthView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var isSignUp = false
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var showPassword = false

    var body: some View {
        ZStack {
            // Background
            Color.gBackground(for: colorScheme).ignoresSafeArea()

            // Subtle grid pattern overlay
            GridPatternBackground()
                .opacity(0.15)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Logo
                VStack(spacing: GSpacing.sm) {
                    ZStack {
                        RoundedRectangle(cornerRadius: GRadius.xl, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.gPrimary, .gSecondary],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 72, height: 72)
                            .shadow(color: .gPrimary.opacity(0.4), radius: 20, y: 8)

                        Image(systemName: "pencil.and.outline")
                            .font(.gEmojiMedium.weight(.medium))
                            .foregroundColor(.white)
                    }

                    Text("GirokIQ")
                        .font(.gLargeTitle)
                        .foregroundColor(.gTextPrimary(for: colorScheme))

                    Text("Your intelligent canvas")
                        .font(.gSubheadline)
                        .foregroundColor(.gTextTertiary(for: colorScheme))
                }
                .padding(.bottom, GSpacing.xxxl)

                // Card
                VStack(spacing: GSpacing.lg) {
                    // Toggle
                    HStack(spacing: 0) {
                        authTabButton("Sign In", isSelected: !isSignUp) { isSignUp = false }
                        authTabButton("Create Account", isSelected: isSignUp) { isSignUp = true }
                    }
                    .background(Color.gElevated(for: colorScheme).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: GRadius.sm, style: .continuous))
                    .padding(.bottom, GSpacing.xxs)

                    // Fields
                    VStack(spacing: GSpacing.sm) {
                        if isSignUp {
                            AuthTextField(
                                placeholder: "Display Name",
                                text: $displayName,
                                systemIcon: "person"
                            )
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        AuthTextField(
                            placeholder: "Email",
                            text: $email,
                            systemIcon: "envelope",
                            keyboardType: .emailAddress
                        )

                        AuthTextField(
                            placeholder: "Password",
                            text: $password,
                            systemIcon: "lock",
                            isSecure: !showPassword,
                            trailingIcon: showPassword ? "eye.slash" : "eye",
                            trailingAction: { showPassword.toggle() }
                        )
                    }
                    .animation(GAnimation.spring, value: isSignUp)

                    // Error
                    if let error = authViewModel.errorMessage {
                        HStack(spacing: GSpacing.xs) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.gDestructive)
                            Text(error)
                                .font(.gCaption)
                                .foregroundColor(.gDestructive)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)
                    }

                    // CTA
                    Button {
                        Task {
                            if isSignUp {
                                await authViewModel.signUp(email: email, password: password, displayName: displayName)
                            } else {
                                await authViewModel.signIn(email: email, password: password)
                            }
                        }
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: GRadius.sm, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [.gPrimary, .gSecondary],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )

                            if authViewModel.isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text(isSignUp ? "Create Account" : "Sign In")
                                    .font(.gCallout.weight(.semibold))
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(height: 50)
                    }
                    .disabled(authViewModel.isLoading || email.isEmpty || password.isEmpty)
                    .opacity(email.isEmpty || password.isEmpty ? 0.6 : 1.0)
                    .animation(GAnimation.motionSafe(GAnimation.springFast), value: authViewModel.isLoading)
                    .accessibilityLabel(isSignUp ? "Create account" : "Sign in")
                    .accessibilityHint(authViewModel.isLoading ? "Loading" : "Double tap to \(isSignUp ? "create account" : "sign in")")

                    // "or" divider
                    HStack(spacing: GSpacing.sm) {
                        Rectangle()
                            .fill(Color.gBorder(for: colorScheme))
                            .frame(height: 0.5)
                        Text("or")
                            .font(.gCaption)
                            .foregroundColor(.gTextTertiary(for: colorScheme))
                        Rectangle()
                            .fill(Color.gBorder(for: colorScheme))
                            .frame(height: 0.5)
                    }

                    // Sign in with Apple
                    Button {
                        Task {
                            await authViewModel.signInWithApple()
                        }
                    } label: {
                        HStack(spacing: GSpacing.sm) {
                            Image(systemName: "apple.logo")
                                .font(.gBody.weight(.medium))
                            Text("Sign in with Apple")
                                .font(.gCallout.weight(.semibold))
                        }
                        .foregroundColor(.gTextPrimary(for: colorScheme))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: GRadius.sm, style: .continuous)
                                .fill(Color.gElevated(for: colorScheme))
                                .overlay(
                                    RoundedRectangle(cornerRadius: GRadius.sm, style: .continuous)
                                        .stroke(Color.gBorder(for: colorScheme), lineWidth: 1)
                                )
                        )
                    }
                    .disabled(authViewModel.isLoading)
                    .accessibilityLabel("Sign in with Apple")
                    .accessibilityHint("Double tap to sign in using your Apple ID")
                }
                .padding(GSpacing.xl)
                .background(
                    RoundedRectangle(cornerRadius: GRadius.xl, style: .continuous)
                        .fill(Color.gSurface(for: colorScheme))
                        .overlay(
                            RoundedRectangle(cornerRadius: GRadius.xl, style: .continuous)
                                .stroke(Color.gBorder(for: colorScheme), lineWidth: 1)
                        )
                )
                .padding(.horizontal, GSpacing.xl)

                Spacer()

                Text("By continuing, you agree to our Terms & Privacy Policy")
                    .font(.gCaption2)
                    .foregroundColor(.gTextTertiary(for: colorScheme))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, GSpacing.xxl)
                    .padding(.horizontal, GSpacing.xxxl)
            }
        }
    }

    @ViewBuilder
    func authTabButton(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.gFootnote.weight(.medium))
                .foregroundColor(isSelected ? .white : .gTextSecondary(for: colorScheme))
                .frame(maxWidth: .infinity)
                .padding(.vertical, GSpacing.xs)
                .background(
                    isSelected ?
                    RoundedRectangle(cornerRadius: GRadius.xs, style: .continuous)
                        .fill(Color.gPrimary) : nil
                )
                .animation(GAnimation.motionSafe(GAnimation.springFast), value: isSelected)
        }
        .padding(GSpacing.xxs)
        .minTapTarget()
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Auth Text Field

struct AuthTextField: View {
    let placeholder: String
    @Binding var text: String
    var systemIcon: String
    var keyboardType: UIKeyboardType = .default
    var isSecure: Bool = false
    var trailingIcon: String? = nil
    var trailingAction: (() -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: GSpacing.sm) {
            Image(systemName: systemIcon)
                .font(.gSubheadline)
                .foregroundColor(.gTextSecondary(for: colorScheme))
                .frame(width: 20)

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
            .foregroundColor(.gTextPrimary(for: colorScheme))

            if let icon = trailingIcon, let action = trailingAction {
                Button(action: action) {
                    Image(systemName: icon)
                        .font(.gFootnote)
                        .foregroundColor(.gTextSecondary(for: colorScheme))
                }
                .minTapTarget()
                .accessibilityLabel(isSecure ? "Show password" : "Hide password")
                .accessibilityHint("Double tap to toggle password visibility")
            }
        }
        .padding(.horizontal, GSpacing.md)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: GRadius.sm, style: .continuous)
                .fill(Color.gElevated(for: colorScheme).opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: GRadius.sm, style: .continuous)
                        .stroke(Color.gBorder(for: colorScheme), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Grid Pattern Background

struct GridPatternBackground: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 30
            var path = Path()

            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += spacing
            }

            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += spacing
            }

            context.stroke(path, with: .color(.gPrimary), lineWidth: 0.5)
        }
    }
}

#Preview {
    AuthView()
        .environmentObject(AuthViewModel())
}
