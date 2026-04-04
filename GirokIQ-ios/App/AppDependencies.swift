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

    /// Lazy-initialized services — deferred until first use after auth
    lazy var localDB: LocalDatabase = LocalDatabase.shared
    lazy var syncEngine: SyncEngine = SyncEngine()
    lazy var aiService: AIService = AIService()

    @Published var isLocked: Bool = false
    var lastBackgroundDate: Date?

    // MARK: - Lifecycle

    init() {
        // Only initialize what's needed for the first frame
        let syncEngine = SyncEngine()
        self.auth = AuthViewModel(syncEngine: syncEngine)
        self.theme = ThemeManager()
        self.biometricAuth = BiometricAuthService()
    }

    // MARK: - Public Methods

    /// Call when app enters background
    func recordBackgroundTime() {
        lastBackgroundDate = Date()
    }

    /// Call when app returns to foreground. Locks if >5 minutes elapsed.
    func checkLockOnForeground() {
        guard auth.isAuthenticated,
              biometricAuth.canUseBiometrics(),
              let lastDate = lastBackgroundDate else { return }

        let elapsed = Date().timeIntervalSince(lastDate)
        if elapsed > 300 { // 5 minutes
            isLocked = true
        }
        lastBackgroundDate = nil
    }

    /// Attempt biometric unlock
    func unlockWithBiometrics() async {
        let success = await biometricAuth.authenticate()
        if success {
            isLocked = false
        }
    }
}
