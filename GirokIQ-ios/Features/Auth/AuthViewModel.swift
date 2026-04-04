import Foundation
import Combine
import Supabase
import AuthenticationServices

// MARK: - Auth ViewModel

@MainActor
final class AuthViewModel: ObservableObject {

    // MARK: - Properties

    @Published var isAuthenticated: Bool = false
    @Published var currentUserId: UUID?
    @Published var currentUserEmail: String?
    @Published var isLoading: Bool = false
    @Published var isSyncing: Bool = false
    @Published var errorMessage: String?

    @Published var displayName: String = "User"

    private let syncEngine: SyncEngine

    // MARK: - Lifecycle

    init(syncEngine: SyncEngine? = nil) {
        self.syncEngine = syncEngine ?? SyncEngine()
        Task {
            await restoreSession()
        }
    }

    // MARK: - Private Methods

    private func restoreSession() async {
        do {
            let session = try await supabase.auth.session
            applyUser(session.user)
        } catch {
            // No stored session — user needs to sign in
            self.isAuthenticated = false
        }
    }

    private func applyUser(_ user: Auth.User) {
        self.currentUserId = user.id
        self.currentUserEmail = user.email
        if let name = user.userMetadata["display_name"]?.stringValue {
            self.displayName = name
        } else {
            self.displayName = user.email ?? "User"
        }
        self.isAuthenticated = true
    }

    // MARK: - Email/Password Auth

    func signIn(email: String, password: String) async {
        isLoading = true
        errorMessage = nil

        do {
            let session = try await supabase.auth.signIn(
                email: email,
                password: password
            )
            applyUser(session.user)
            await performPostSignInSync()
        } catch {
            self.errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func signUp(email: String, password: String, displayName: String) async {
        isLoading = true
        errorMessage = nil

        do {
            let response = try await supabase.auth.signUp(
                email: email,
                password: password,
                data: ["display_name": .string(displayName)]
            )
            if let session = response.session {
                applyUser(session.user)
                await performPostSignInSync()
            }
        } catch {
            self.errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Sign in with Apple

    func signInWithApple() async {
        isLoading = true
        errorMessage = nil

        do {
            let coordinator = AppleSignInCoordinator()
            let result = try await coordinator.signIn()

            let session = try await supabase.auth.signInWithIdToken(
                credentials: .init(
                    provider: .apple,
                    idToken: result.identityToken,
                    nonce: result.nonce
                )
            )
            applyUser(session.user)
            await performPostSignInSync()
        } catch let error as AppleSignInError where error == .canceled {
            // User canceled — no error message needed
        } catch {
            self.errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Post-Sign-In Sync

    private func performPostSignInSync() async {
        guard let userId = currentUserId else { return }
        isSyncing = true
        await syncEngine.pullAll(userId: userId)
        isSyncing = false
    }

    // MARK: - Sign Out

    func signOut() async {
        do {
            try await supabase.auth.signOut()
        } catch {
            print("[Auth] Sign out network error (ignored): \(error)")
        }

        self.currentUserId = nil
        self.currentUserEmail = nil
        self.displayName = "User"
        self.isAuthenticated = false
    }
}

// MARK: - Lightweight Keychain Wrapper (still used by AIService)

final class KeychainService {
    static let shared = KeychainService()
    private let service = "com.girokiq.app"

    func set(_ value: String, forKey key: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
