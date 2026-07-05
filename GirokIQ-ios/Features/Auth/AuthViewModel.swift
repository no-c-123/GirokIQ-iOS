import Foundation
import CryptoKit
import Combine
import Supabase
import AuthenticationServices
import Security

// MARK: - Auth ViewModel

@MainActor
final class AuthViewModel: ObservableObject {

    // MARK: - Properties

    @Published var isAuthenticated: Bool = false
    @Published var isRestoringSession: Bool = true
    @Published var currentUserId: UUID?
    @Published var currentUserEmail: String?
    @Published var isLoading: Bool = false
    @Published var isSyncing: Bool = false
    @Published var errorMessage: String?
    @Published var infoMessage: String?
    @Published var backfillStatusMessage: String?

    @Published var displayName: String = "User"

    let syncMonitor: SyncEngine
    private let localDatabase: LocalDatabase

    // MARK: - Lifecycle

    init(syncEngine: SyncEngine? = nil) {
        let resolvedSyncEngine = syncEngine ?? SyncEngine()
        self.syncMonitor = resolvedSyncEngine
        self.localDatabase = .shared
        Task {
            await restoreSession()
        }
    }

    // MARK: - Private Methods

    private func restoreSession() async {
        defer { isRestoringSession = false }

        do {
            let session = try await supabase.auth.session
            // With `emitLocalSessionAsInitialSession` enabled, a locally stored session
            // can be surfaced even when expired, so verify validity before treating the
            // user as signed in. An expired session means they must re-authenticate.
            guard !session.isExpired else {
                clearLocalSessionState()
                return
            }
            applyUser(session.user)
            await performPostSignInSync()
        } catch {
            // No stored session — user needs to sign in
            clearLocalSessionState()
        }
    }

    private func applyUser(_ user: Auth.User) {
        currentUserId = user.id
        currentUserEmail = user.email

        if let displayName = resolvedDisplayName(from: user) {
            self.displayName = displayName
        } else {
            self.displayName = user.email ?? "User"
        }

        isAuthenticated = true

        if !Configuration.cloudSyncEnabled {
            Task.detached(priority: .utility) {
                try? await LocalDatabase.shared.markAllSyncChangesAsSynced()
            }
        }
    }

    private func resolvedDisplayName(from user: Auth.User) -> String? {
        let candidates = [
            user.userMetadata["display_name"]?.stringValue,
            user.userMetadata["full_name"]?.stringValue,
            user.userMetadata["name"]?.stringValue,
            user.email
        ]

        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
    }

    private func clearLocalSessionState() {
        currentUserId = nil
        currentUserEmail = nil
        displayName = "User"
        isSyncing = false
        isAuthenticated = false
        backfillStatusMessage = nil
    }

    private func ensureSyncCompletedSuccessfully() throws {
        switch syncMonitor.state {
        case .idle, .syncing:
            return
        case .paused(let message):
            throw AuthViewModelError.syncFailed(message: message)
        case .error(let message):
            throw AuthViewModelError.syncFailed(message: message)
        }
    }

    private func userFacingAuthMessage(for error: Error) -> String {
        if let appleError = error as? AppleSignInError {
            return appleError.errorDescription ?? "Sign in with Apple failed."
        }

        let message = error.localizedDescription
        let lowered = message.lowercased()

        if lowered.contains("invalid login credentials") || lowered.contains("invalid_credentials") {
            return "Incorrect email or password."
        }

        if lowered.contains("network") || lowered.contains("internet") || lowered.contains("offline") {
            return "Check your internet connection and try again."
        }

        if lowered.contains("cancel") {
            return "The sign-in flow was canceled."
        }

        return message
    }

    private func authorizedEdgeFunctionRequest(
        name: String,
        body: [String: Any]? = nil
    ) async throws -> URLRequest {
        let session = try await supabase.auth.session
        guard !session.isExpired else {
            throw AuthViewModelError.sessionExpired
        }

        let url = Configuration.supabaseFunctionsBaseURL.appendingPathComponent(name)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        return request
    }

    private func parseEdgeFunctionError(data: Data) -> String {
        if
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let message = (json["error"] as? String) ?? (json["message"] as? String),
            !message.isEmpty
        {
            return message
        }

        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            return text
        }

        return "The request failed."
    }

    // MARK: - Email/Password Auth

    func signIn(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        infoMessage = nil

        do {
            let session = try await supabase.auth.signIn(
                email: email,
                password: password
            )
            applyUser(session.user)
            await performPostSignInSync()
        } catch {
            self.errorMessage = userFacingAuthMessage(for: error)
        }

        isLoading = false
    }

    func signUp(email: String, password: String, displayName: String) async {
        isLoading = true
        errorMessage = nil
        infoMessage = nil

        do {
            let response = try await supabase.auth.signUp(
                email: email,
                password: password,
                data: ["display_name": .string(displayName)]
            )
            if let session = response.session {
                applyUser(session.user)
                await performPostSignInSync()
            } else {
                infoMessage = "Check your email to confirm your account, then sign in."
            }
        } catch {
            self.errorMessage = userFacingAuthMessage(for: error)
        }

        isLoading = false
    }

    func resetPassword(email: String) async {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty else {
            errorMessage = "Enter your email first."
            infoMessage = nil
            return
        }

        isLoading = true
        errorMessage = nil
        infoMessage = nil

        do {
            try await supabase.auth.resetPasswordForEmail(trimmedEmail)
            infoMessage = "Password reset email sent. Check your inbox and follow the link to continue."
        } catch {
            errorMessage = userFacingAuthMessage(for: error)
        }

        isLoading = false
    }

    // MARK: - Sign in with Apple (Custom Button)

    func signInWithApple() async {
        isLoading = true
        errorMessage = nil
        infoMessage = nil

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
            self.errorMessage = userFacingAuthMessage(for: error)
        }

        isLoading = false
    }

    // MARK: - Sign in with Apple (Native Button)

    func handleAppleSignIn(result: Result<ASAuthorization, Error>, nonce: String) async {
        isLoading = true
        errorMessage = nil
        infoMessage = nil

        do {
            switch result {
            case .success(let authorization):
                guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                      let tokenData = credential.identityToken,
                      let identityToken = String(data: tokenData, encoding: .utf8) else {
                    throw AppleSignInError.missingToken
                }

                let session = try await supabase.auth.signInWithIdToken(
                    credentials: .init(
                        provider: .apple,
                        idToken: identityToken,
                        nonce: nonce
                    )
                )
                applyUser(session.user)
                await performPostSignInSync()

            case .failure(let error):
                if let asError = error as? ASAuthorizationError, asError.code == .canceled {
                    // User canceled — no error message needed
                } else {
                    throw error
                }
            }
        } catch {
            self.errorMessage = userFacingAuthMessage(for: error)
        }

        isLoading = false
    }

    // MARK: - Helper to generate nonce

    func generateNonce() -> String {
        return randomNonceString()
    }

    func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = CryptoKit.SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            var random: UInt8 = 0
            _ = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            if random < charset.count {
                result.append(charset[Int(random)])
                remainingLength -= 1
            }
        }
        return result
    }

    // MARK: - Post-Sign-In Sync

    private func performPostSignInSync() async {
        guard let userId = currentUserId else { return }
        guard Configuration.cloudSyncEnabled else {
            // Local-only launch mode: keep Supabase for auth (and optionally app_state),
            // but do not pull notebooks/pages/chats.
            isSyncing = false
            _ = userId
            Task.detached(priority: .utility) {
                try? await LocalDatabase.shared.markAllSyncChangesAsSynced()
            }
            return
        }
        isSyncing = true
        let hasBackfillWork = await syncMonitor.enqueueInitialBackfillIfNeeded(userId: userId)
        if hasBackfillWork {
            await syncMonitor.pushPending()
        }
        await syncMonitor.pullAll(userId: userId)
        isSyncing = false
    }

    // MARK: - Account Management

    func updateDisplayName(_ newValue: String) async throws {
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AuthViewModelError.invalidDisplayName
        }

        try await supabase.auth.update(
            user: UserAttributes(
                data: ["display_name": .string(trimmed)]
            )
        )

        displayName = trimmed
    }

    func deleteAccount() async throws {
        let localImageFileNames = await localCanvasImageFileNames()
        let request = try await authorizedEdgeFunctionRequest(name: "delete-account")
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthViewModelError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw AuthViewModelError.edgeFunctionFailed(
                message: parseEdgeFunctionError(data: data)
            )
        }

        try? await supabase.auth.signOut()
        deleteLocalCanvasImages(named: localImageFileNames)
        try? await localDatabase.resetAllData()
        clearLocalSessionState()
    }

    // MARK: - Sign Out

    func signOut() async {
        do {
            try await supabase.auth.signOut()
        } catch {
            print("[Auth] Sign out network error (ignored): \(error)")
        }

        errorMessage = nil
        infoMessage = nil
        clearLocalSessionState()
    }

    func forceCloudBackfill() async throws {
        guard Configuration.cloudSyncEnabled else { return }
        guard let userId = currentUserId else { return }

        isSyncing = true
        backfillStatusMessage = "Rebuilding cloud backup queue..."
        defer { isSyncing = false }

        let pendingAfterEnqueue = try await syncMonitor.forceReenqueueInitialBackfill(userId: userId)
        backfillStatusMessage = pendingAfterEnqueue > 0
            ? "Uploading \(pendingAfterEnqueue) queued items to cloud..."
            : "No local content needed re-enqueueing."

        if pendingAfterEnqueue > 0 {
            await syncMonitor.pushPending()
            try ensureSyncCompletedSuccessfully()
        }

        backfillStatusMessage = "Refreshing from cloud..."
        await syncMonitor.pullAll(userId: userId)
        try ensureSyncCompletedSuccessfully()
        backfillStatusMessage = "Cloud backup refresh completed."
    }

    private func localCanvasImageFileNames() async -> Set<String> {
        guard let userId = currentUserId else { return [] }

        do {
            let notebooks = try await localDatabase.fetchNotebooks(userId: userId)
            var fileNames = Set<String>()

            for notebook in notebooks {
                let pages = try await localDatabase.fetchPages(notebookId: notebook.id)
                for tuple in pages {
                    for element in tuple.page.settings?.elements ?? []
                    where element.type == "image"
                    {
                        guard let fileName = element.content?.trimmingCharacters(in: .whitespacesAndNewlines),
                              !fileName.isEmpty else { continue }
                        fileNames.insert(fileName)
                    }
                }
            }

            fileNames.formUnion(NotebookTransferSupport.localCanvasImageFileNamesOnDisk())

            return fileNames
        } catch {
            print("[Auth] Failed to collect local image files before account deletion: \(error)")
            return []
        }
    }

    private func deleteLocalCanvasImages(named fileNames: Set<String>) {
        guard !fileNames.isEmpty else { return }

        for fileName in fileNames {
            let url = NotebookTransferSupport.localImageURL(for: fileName)
            do {
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
                ImageCache.shared.remove(for: fileName)
            } catch {
                print("[Auth] Failed to delete local image file \(fileName): \(error)")
            }
        }
    }
}

enum AuthViewModelError: LocalizedError {
    case invalidDisplayName
    case sessionExpired
    case invalidResponse
    case edgeFunctionFailed(message: String)
    case syncFailed(message: String)

    var errorDescription: String? {
        switch self {
        case .invalidDisplayName:
            return "Display name can’t be empty."
        case .sessionExpired:
            return "Your session expired. Please sign in again."
        case .invalidResponse:
            return "The server returned an invalid response."
        case .edgeFunctionFailed(let message):
            return message
        case .syncFailed(let message):
            return message
        }
    }
}

// MARK: - Lightweight Keychain Wrapper (still used by AIService)

final class KeychainService {
    static let shared = KeychainService()
    private let service = "app.girokiq.app"

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
