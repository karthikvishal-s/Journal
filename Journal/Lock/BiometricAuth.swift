import Foundation
import LocalAuthentication

/// Thin wrapper over LocalAuthentication.
enum BiometricAuth {

    /// Whether this Mac can do Touch ID at all. Checked before offering the
    /// option, so a Mac without a sensor never shows a toggle it can't honour.
    static var isAvailable: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    static func makeContext() -> LAContext {
        let context = LAContext()
        context.localizedFallbackTitle = "Use Passcode"
        // Each unlock should require a fresh touch; never reuse a recent one.
        context.touchIDAuthenticationAllowableReuseDuration = 0
        return context
    }

    /// Runs the Touch ID prompt. Used directly in `.appEnforced` keychain mode;
    /// in `.dataProtection` mode the Keychain read runs its own prompt instead.
    static func authenticate(reason: String, context: LAContext) async throws {
        do {
            let ok = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            guard ok else { throw KeychainError.cancelled }
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .userFallback, .systemCancel, .appCancel:
                throw KeychainError.cancelled
            default:
                throw error
            }
        }
    }
}
