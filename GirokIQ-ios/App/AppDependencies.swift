import Foundation
import SwiftUI
import Combine

// MARK: - App Dependencies

/// Single source of truth for shared services and managers.
/// Injected at the app root via `.environmentObject()`.
final class AppDependencies: ObservableObject {
    let auth: AuthViewModel
    let theme: ThemeManager
    let localDB: LocalDatabase
    let syncEngine: SyncEngine
    let aiService: AIService
    let biometricAuth: BiometricAuthService

    @Published var isLocked: Bool = false
    var lastBackgroundDate: Date?

    init() {
        let syncEngine = SyncEngine()
        self.syncEngine = syncEngine
        self.auth = AuthViewModel(syncEngine: syncEngine)
        self.theme = ThemeManager()
        self.localDB = LocalDatabase.shared
        self.aiService = AIService()
        self.biometricAuth = BiometricAuthService()
    }

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
