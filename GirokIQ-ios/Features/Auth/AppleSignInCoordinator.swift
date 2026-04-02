import AuthenticationServices
import CryptoKit
import Foundation

/// Manages the Sign in with Apple flow, producing an identity token
/// and nonce pair suitable for Supabase `signInWithIdToken`.
@MainActor
final class AppleSignInCoordinator: NSObject {

    private var continuation: CheckedContinuation<(identityToken: String, nonce: String), Error>?
    private var currentNonce: String?

    func signIn() async throws -> (identityToken: String, nonce: String) {
        let nonce = Self.randomNonce()
        currentNonce = nonce

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            request.requestedScopes = [.email, .fullName]
            request.nonce = Self.sha256(nonce)

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    // MARK: - Nonce Generation

    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
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

    private static func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AppleSignInCoordinator: ASAuthorizationControllerDelegate {

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8) else {
            Task { @MainActor in
                continuation?.resume(throwing: AppleSignInError.missingToken)
                continuation = nil
            }
            return
        }

        Task { @MainActor in
            guard let nonce = currentNonce else {
                continuation?.resume(throwing: AppleSignInError.missingNonce)
                continuation = nil
                return
            }
            continuation?.resume(returning: (identityToken: identityToken, nonce: nonce))
            continuation = nil
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor in
            // ASAuthorizationError.canceled means user dismissed — not a real error
            if let asError = error as? ASAuthorizationError, asError.code == .canceled {
                continuation?.resume(throwing: AppleSignInError.canceled)
            } else {
                continuation?.resume(throwing: error)
            }
            continuation = nil
        }
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension AppleSignInCoordinator: ASAuthorizationControllerPresentationContextProviding {

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // Return the first key window scene's window
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        return windowScene?.windows.first(where: { $0.isKeyWindow }) ?? UIWindow()
    }
}

// MARK: - Errors

enum AppleSignInError: LocalizedError {
    case missingToken
    case missingNonce
    case canceled

    var errorDescription: String? {
        switch self {
        case .missingToken: return "Could not retrieve identity token from Apple."
        case .missingNonce: return "Authentication nonce was not set."
        case .canceled: return nil // User canceled — no error to show
        }
    }
}
