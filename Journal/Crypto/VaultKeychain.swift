import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// Stores the data encryption key in the macOS Keychain so Touch ID can release
/// it, and reports honestly about how well it is protected.
///
/// There are two possible storage modes, and which one is available depends on
/// how the app was signed:
///
/// * `.dataProtection` — the modern keychain, with the key held under a
///   `.biometryCurrentSet` access control. macOS itself refuses to hand the key
///   over without a fingerprint, and re-enrolling a finger invalidates it. This
///   needs a real Team ID, which means signing with a development team.
///
/// * `.appEnforced` — the legacy keychain, with no biometric ACL. The key comes
///   back on request, and it is *this app* that insists on a Touch ID check
///   first. Fine against someone sitting at the Mac; weaker against someone who
///   can run code as you, because the check is in the app rather than the
///   kernel. This is the fallback for ad-hoc signed builds.
///
/// Settings shows which mode is in effect rather than implying the strong one.
/// The passcode and recovery key paths are unaffected either way — they never
/// touch the Keychain.
final class VaultKeychain {

    enum Mode: String {
        case dataProtection
        case appEnforced

        var explanation: String {
            switch self {
            case .dataProtection:
                return "Touch ID is enforced by macOS. The key is stored under a biometric lock and cannot be read without your fingerprint."
            case .appEnforced:
                return "Touch ID is enforced by this app rather than by macOS, because the app isn't signed with a developer team. Your passcode and recovery key are unaffected."
            }
        }
    }

    private let service: String
    private let account = "data-encryption-key"

    private(set) var mode: Mode = .dataProtection

    init(service: String = "com.karthikvishal.Journal.vault") {
        self.service = service
    }

    // MARK: - Storing

    /// Stores the key, preferring the strong mode and falling back if the
    /// entitlements aren't there. Returns the mode actually used.
    @discardableResult
    func store(dataKey: SymmetricKey) throws -> Mode {
        let bytes = dataKey.withUnsafeBytes { Data($0) }
        remove()

        if let accessControl = makeBiometricAccessControl() {
            var query = baseQuery(dataProtection: true)
            query[kSecValueData as String] = bytes
            query[kSecAttrAccessControl as String] = accessControl

            let status = SecItemAdd(query as CFDictionary, nil)
            if status == errSecSuccess {
                mode = .dataProtection
                return .dataProtection
            }
            // errSecMissingEntitlement is the expected failure for an ad-hoc
            // signed build. Anything else is unexpected but equally fatal to
            // this path, so both fall through to the weaker mode.
        }

        var query = baseQuery(dataProtection: false)
        query[kSecValueData as String] = bytes
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.storeFailed(status)
        }
        mode = .appEnforced
        return .appEnforced
    }

    // MARK: - Loading

    /// Retrieves the key. In `.dataProtection` mode macOS runs the Touch ID
    /// prompt itself as part of this call; in `.appEnforced` mode the caller
    /// must have already passed `BiometricAuth.authenticate`.
    func loadDataKey(context: LAContext, prompt: String) throws -> SymmetricKey {
        for dataProtection in [true, false] {
            var query = baseQuery(dataProtection: dataProtection)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            query[kSecUseAuthenticationContext as String] = context
            if dataProtection {
                query[kSecUseOperationPrompt as String] = prompt
            }

            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)

            switch status {
            case errSecSuccess:
                guard let data = item as? Data else { throw KeychainError.malformedItem }
                mode = dataProtection ? .dataProtection : .appEnforced
                return SymmetricKey(data: data)
            case errSecUserCanceled, errSecAuthFailed:
                throw KeychainError.cancelled
            default:
                continue    // try the other keychain
            }
        }
        throw KeychainError.notFound
    }

    var hasStoredKey: Bool {
        for dataProtection in [true, false] {
            var query = baseQuery(dataProtection: dataProtection)
            query[kSecReturnData as String] = false
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            // Do not trigger a biometric prompt merely to check for existence.
            query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail

            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            // interactionNotAllowed means "it's there, but I'd have to ask" —
            // which for this question is a yes.
            if status == errSecSuccess || status == errSecInteractionNotAllowed {
                return true
            }
        }
        return false
    }

    func remove() {
        for dataProtection in [true, false] {
            SecItemDelete(baseQuery(dataProtection: dataProtection) as CFDictionary)
        }
    }

    // MARK: - Internals

    private func baseQuery(dataProtection: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if dataProtection {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        return query
    }

    private func makeBiometricAccessControl() -> SecAccessControl? {
        // .biometryCurrentSet, not .biometryAny: adding a fingerprint after the
        // fact should not silently grant access to the journal.
        SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryCurrentSet,
            nil
        )
    }
}

enum KeychainError: LocalizedError, Equatable {
    case storeFailed(OSStatus)
    case notFound
    case malformedItem
    case cancelled

    var errorDescription: String? {
        switch self {
        case .storeFailed(let status):
            return "Couldn't save to the Keychain (code \(status))."
        case .notFound:
            return "No Touch ID key is stored for this journal."
        case .malformedItem:
            return "The stored Keychain item is damaged."
        case .cancelled:
            return "Touch ID was cancelled."
        }
    }
}
