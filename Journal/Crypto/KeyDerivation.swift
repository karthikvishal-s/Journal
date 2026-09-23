import CommonCrypto
import CryptoKit
import Foundation

/// Turns secrets the user supplies into 256-bit keys.
///
/// Two very different jobs live here, and they deliberately use different
/// algorithms:
///
/// * A **passcode** is low entropy. Someone who copies `vault.json` off the
///   disk can guess passcodes offline as fast as their hardware allows, so the
///   derivation has to be made expensive on purpose — PBKDF2 with a high round
///   count. The rounds are stored in the vault file, so this can be raised for
///   new vaults without breaking old ones.
///
/// * A **recovery key** is 256 bits straight from the system RNG. There is
///   nothing to guess, so stretching it would buy nothing and only slow down
///   the recovery path. HKDF is the right tool: it just spreads the entropy.
enum KeyDerivation {

    /// Cost for new vaults. Roughly a few hundred milliseconds on Apple silicon
    /// — slow enough to punish a guessing attack, quick enough that unlocking
    /// still feels instant.
    static let defaultRounds: UInt32 = 310_000

    static let saltByteCount = 32

    static func randomSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: saltByteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "System RNG unavailable")
        return Data(bytes)
    }

    /// PBKDF2-HMAC-SHA256. Used only for passcodes.
    static func key(fromPasscode passcode: String, salt: Data, rounds: UInt32) throws -> SymmetricKey {
        let passcodeBytes = Array(passcode.utf8)
        var derived = [UInt8](repeating: 0, count: 32)

        let status = salt.withUnsafeBytes { saltBuffer -> Int32 in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                passcodeBytes.map { Int8(bitPattern: $0) }, passcodeBytes.count,
                saltBuffer.bindMemory(to: UInt8.self).baseAddress, salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                rounds,
                &derived, derived.count
            )
        }

        guard status == kCCSuccess else { throw CryptoError.sealFailed }
        return SymmetricKey(data: Data(derived))
    }

    /// HKDF-SHA256. Used for the recovery key, whose input is already uniform.
    static func key(fromRecoverySecret secret: Data, salt: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: secret),
            salt: salt,
            info: Data("journal.recovery.v1".utf8),
            outputByteCount: 32
        )
    }
}
