import SwiftUI
import LocalAuthentication

@main
struct GirokIQ_iosApp: App {
    @StateObject private var deps = AppDependencies()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(deps.auth)
                .environmentObject(deps.theme)
                .environmentObject(deps)
                .environmentObject(deps.purchaseManager)
                .preferredColorScheme(deps.theme.colorSchemeOverride)
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .inactive:
                deps.protectContentForBackground()
            case .background:
                deps.protectContentForBackground()
            case .active:
                deps.handleAppDidBecomeActive()
            default:
                break
            }
        }
    }
}

// MARK: - Root View

struct RootView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var deps: AppDependencies

    var body: some View {
        ZStack {
            Group {
                if authViewModel.isRestoringSession {
                    LaunchLoadingView()
                } else if authViewModel.isAuthenticated {
                    AdaptiveNavigationView()
                } else {
                    AuthView()
                }
            }
            .animation(GAnimation.spring, value: authViewModel.isAuthenticated)

            // Biometric lock overlay
            if deps.isLocked && authViewModel.isAuthenticated {
                LockOverlayView()
                    .zIndex(1)
            }
        }
        .task(id: deps.shouldPromptForUnlock) {
            guard deps.shouldPromptForUnlock else { return }
            await deps.unlockWithBiometrics()
        }
    }
}

// MARK: - Launch Loading

struct LaunchLoadingView: View {
    var body: some View {
        ZStack {
            Color.gBackground
                .ignoresSafeArea()

            VStack(spacing: GSpacing.lg) {
                ProgressView()
                    .tint(.gPrimary)

                Text("Restoring your session…")
                    .font(.gSubheadline)
                    .foregroundColor(.gTextSecondary)
            }
        }
    }
}

// MARK: - Adaptive Navigation

struct AdaptiveNavigationView: View {
    @StateObject private var viewModel = HomeViewModel()
    @State private var selectedNotebook: Notebook?

    var body: some View {
        HomeView(
            viewModel: viewModel,
            selectedNotebook: $selectedNotebook
        )
    }
}

// MARK: - Lock Overlay

struct LockOverlayView: View {
    @EnvironmentObject var deps: AppDependencies

    var body: some View {
        ZStack {
            // Blurred background
            Color.gBackground
                .ignoresSafeArea()

            VStack(spacing: GSpacing.lg) {
                Image(systemName: deps.biometricAuth.biometricType == .faceID ? "faceid" : "touchid")
                    .font(.system(size: 48))
                    .foregroundColor(.gPrimary)

                Text("GirokIQ is Locked")
                    .font(.gTitle2)
                    .foregroundColor(.gTextPrimary)

                Text("Authenticate to continue")
                    .font(.gSubheadline)
                    .foregroundColor(.gTextSecondary)

                Button {
                    Task {
                        await deps.unlockWithBiometrics()
                    }
                } label: {
                    Text("Unlock")
                        .font(.gCallout.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(width: 160, height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: GRadius.sm, style: .continuous)
                                .fill(Color.gPrimary)
                        )
                }
                .padding(.top, GSpacing.sm)
            }
        }
    }
}
