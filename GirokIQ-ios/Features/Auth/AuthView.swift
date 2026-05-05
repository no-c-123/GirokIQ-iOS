import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var isSignUp = false
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var showPassword = false
    @State private var currentNonce = ""

    var body: some View {
        ZStack {
            // Background
            Color.gBackground.ignoresSafeArea()

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
                        .font(.custom("InstrumentSerif-Regular", size: 36))
                        .foregroundColor(.gTextPrimary)

                    Text("Your intelligent canvas")
                        .font(.custom("PlusJakartaSans-Regular", size: 15))
                        .foregroundColor(.gTextSecondary)
                }
                .padding(.bottom, GSpacing.xxxl)

                // Card
                VStack(spacing: GSpacing.lg) {
                    // Toggle
                    HStack(spacing: 0) {
                        authTabButton("Sign In", isSelected: !isSignUp) { isSignUp = false }
                        authTabButton("Create Account", isSelected: isSignUp) { isSignUp = true }
                    }
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
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.gPrimary)

                            if authViewModel.isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text(isSignUp ? "Create Account" : "Sign In")
                                    .font(.custom("PlusJakartaSans-Medium", size: 16))
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(height: 50)
                    }
                    .buttonStyle(.plain)
                    .disabled(authViewModel.isLoading || email.isEmpty || password.isEmpty)
                    .animation(GAnimation.motionSafe(GAnimation.springFast), value: authViewModel.isLoading)
                    .accessibilityLabel(isSignUp ? "Create account" : "Sign in")
                    .accessibilityHint(authViewModel.isLoading ? "Loading" : "Double tap to \(isSignUp ? "create account" : "sign in")")

                    // "or" divider
                    HStack(spacing: GSpacing.sm) {
                        Rectangle()
                            .fill(Color.gBorder)
                            .frame(height: 0.5)
                        Text("or")
                            .font(.gCaption)
                            .foregroundColor(.gTextTertiary)
                        Rectangle()
                            .fill(Color.gBorder)
                            .frame(height: 0.5)
                    }

                    // Sign in with Apple
                    SignInWithAppleButton(.signIn) { request in
                        let nonce = authViewModel.generateNonce()
                        currentNonce = nonce
                        request.requestedScopes = [.fullName, .email]
                        request.nonce = authViewModel.sha256(nonce)
                    } onCompletion: { result in
                        Task {
                            await authViewModel.handleAppleSignIn(result: result, nonce: currentNonce)
                        }
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 50)
                    .disabled(authViewModel.isLoading)
                    .accessibilityLabel("Sign in with Apple")
                    .accessibilityHint("Double tap to sign in using your Apple ID")
                }
                .padding(GSpacing.xl)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.gSurface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color.gBorder, lineWidth: 0.5)
                        )
                )
                .padding(.horizontal, GSpacing.xl)

                Spacer()

                HStack(spacing: 4) {
                    Text("By continuing, you agree to our")
                        .foregroundColor(.gTextTertiary)
                    Link("Terms", destination: URL(string: "https://GirokIQ.app/terms")!)
                        .foregroundColor(.gPrimary)
                    Text("&")
                        .foregroundColor(.gTextTertiary)
                    Link("Privacy Policy", destination: URL(string: "https://GirokIQ.app/privacy")!)
                        .foregroundColor(.gPrimary)
                }
                .font(.gCaption2)
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
                .font(isSelected ? .custom("PlusJakartaSans-Medium", size: 15) : .custom("PlusJakartaSans-Regular", size: 15))
                .foregroundColor(isSelected ? .gTextPrimary : .gTextSecondary)
                .padding(.bottom, 8)
                .overlay(alignment: .bottom) {
                    if isSelected {
                        Rectangle()
                            .frame(height: 2)
                            .foregroundColor(Color.gPrimary)
                    }
                }
                .padding(.top, GSpacing.sm)
                .frame(maxWidth: .infinity)
                .animation(GAnimation.motionSafe(GAnimation.springFast), value: isSelected)
        }
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
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: GSpacing.sm) {
            Image(systemName: systemIcon)
                .font(.gSubheadline)
                .foregroundColor(.gTextSecondary)
                .frame(width: 20)

            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                        .focused($isFocused)
                } else {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboardType)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .focused($isFocused)
                }
            }
            .font(.gSubheadline)
            .foregroundColor(.gTextPrimary)

            if let icon = trailingIcon, let action = trailingAction {
                Button(action: action) {
                    Image(systemName: icon)
                        .font(.gFootnote)
                        .foregroundColor(.gTextSecondary)
                }
                .minTapTarget()
                .accessibilityLabel(isSecure ? "Show password" : "Hide password")
                .accessibilityHint("Double tap to toggle password visibility")
            }
        }
        .padding(.horizontal, GSpacing.md)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.gElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isFocused ? Color.gPrimary : Color.gBorder, lineWidth: isFocused ? 1 : 0.5)
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
