import Foundation
import SwiftUI
import Combine

// MARK: - App Dependencies

/// Single source of truth for shared services and managers.
/// Injected at the app root via `.environmentObject()`.
///
/// ## Performance: Cold Launch Optimization
/// - Only `auth`, `theme`, and `biometricAuth` are created at launch (required for first frame).
/// - `syncEngine`, `aiService`, and `localDB` are accessed lazily — they initialize
///   on first use (typically after authentication), keeping cold launch under 1.5s.
final class AppDependencies: ObservableObject {

    // MARK: - Properties

    let auth: AuthViewModel
    let theme: ThemeManager
    let biometricAuth: BiometricAuthService
    let syncEngine: SyncEngine
    let purchaseManager: PurchaseManager

    /// Lazy-initialized services — deferred until first use after auth
    lazy var localDB: LocalDatabase = LocalDatabase.shared
    lazy var aiService: AIService = AIService()

    @Published var isLocked: Bool = false
    @Published var shouldPromptForUnlock: Bool = false
    private let biometricLockDefaultsKey = "biometricLockEnabled"
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Lifecycle

    init() {
        // Only initialize what's needed for the first frame
        let syncEngine = SyncEngine()
        self.syncEngine = syncEngine
        self.auth = AuthViewModel(syncEngine: syncEngine)
        self.theme = ThemeManager()
        self.biometricAuth = BiometricAuthService()
        self.purchaseManager = PurchaseManager()
        self.purchaseManager.bind(authViewModel: self.auth)
        if Configuration.cloudSyncEnabled {
            if !PerfBisect.disableAutoSyncLoop {
                syncEngine.startAutoSync()
            }
        }

        auth.$currentUserId
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.purchaseManager.handleAuthenticationStateChanged()
            }
            .store(in: &cancellables)
    }

    deinit {
        syncEngine.stopAutoSync()
    }

    // MARK: - Public Methods

    private var isBiometricLockEnabled: Bool {
        UserDefaults.standard.bool(forKey: biometricLockDefaultsKey)
    }

    private var shouldRequirePrivacyLock: Bool {
        auth.isAuthenticated &&
        isBiometricLockEnabled &&
        biometricAuth.canAuthenticate()
    }

    /// Call as soon as the app is moving away from the foreground so the
    /// App Switcher snapshot never captures notebook content.
    func protectContentForBackground() {
        guard shouldRequirePrivacyLock else { return }
        isLocked = true
        shouldPromptForUnlock = false
    }

    /// Call when app becomes active. Keeps the shield in place until the user
    /// authenticates, or clears it if lock requirements no longer apply.
    func handleAppDidBecomeActive() {
        guard shouldRequirePrivacyLock else {
            isLocked = false
            shouldPromptForUnlock = false
            return
        }

        if isLocked {
            shouldPromptForUnlock = true
        }
    }

    /// Attempt biometric unlock
    func unlockWithBiometrics() async {
        guard shouldRequirePrivacyLock else {
            isLocked = false
            shouldPromptForUnlock = false
            return
        }

        await MainActor.run {
            shouldPromptForUnlock = false
        }

        let success = await biometricAuth.authenticate()
        await MainActor.run {
            if success {
                isLocked = false
            }
        }
    }
}
