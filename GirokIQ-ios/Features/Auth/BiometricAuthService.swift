import LocalAuthentication

/// Wraps LAContext for Face ID / Touch ID biometric authentication.
/// Used for privacy lock after the app has been in the background.
final class BiometricAuthService {

    /// Whether biometric authentication is available on this device.
    func canUseBiometrics() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    /// The type of biometric available (Face ID, Touch ID, or none).
    var biometricType: LABiometryType {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType
    }

    /// Prompt the user for biometric authentication. Returns `true` on success.
    func authenticate() async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Use Passcode"

        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Unlock GirokIQ"
            ) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
}
