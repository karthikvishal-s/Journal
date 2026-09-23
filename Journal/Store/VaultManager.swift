import CryptoKit
import Foundation

/// Owns the vault file and the transition between locked and unlocked.
///
/// The only way to get an `EntryStore` is to come through here with a correct
/// passcode or recovery key. Nothing else in the app can manufacture one.
final class VaultManager {

    let paths: VaultPaths

    init(paths: VaultPaths) {
        self.paths = paths
    }

    convenience init() throws {
        self.init(paths: try VaultPaths.standard())
    }

    var vaultExists: Bool { paths.vaultExists }

    // MARK: - First run

    struct SetupResult {
        let recoveryKey: String     // formatted, to show once and never again
        let store: EntryStore
        let dataKey: SymmetricKey
    }

    /// Creates the vault and returns an already-unlocked session. The recovery
    /// key string is the only time the user will ever see it — it is derived
    /// from a secret that is not stored anywhere in recoverable form.
    /// `rounds` is injectable purely so the test suite can use a cheap KDF;
    /// the app always uses the default.
    func createVault(passcode: String, rounds: UInt32 = KeyDerivation.defaultRounds) throws -> SetupResult {
        guard !vaultExists else { throw VaultError.vaultAlreadyExists }
        try paths.createDirectoriesIfNeeded()

        let recovery = RecoveryKey.generate()
        let (file, dataKey) = try VaultFile.create(
            passcode: passcode,
            recoverySecret: recovery.secret,
            rounds: rounds
        )
        try file.write(to: paths.vaultFile)

        let store = try EntryStore(paths: paths, dataKey: dataKey)
        return SetupResult(recoveryKey: recovery.formatted, store: store, dataKey: dataKey)
    }

    // MARK: - Unlocking

    struct UnlockResult {
        let store: EntryStore
        let dataKey: SymmetricKey
    }

    func unlock(passcode: String) throws -> UnlockResult {
        try unlock { file in try file.unwrapKey(passcode: passcode) }
    }

    func unlock(recoveryKeyInput: String) throws -> UnlockResult {
        guard let secret = RecoveryKey.parse(recoveryKeyInput) else {
            throw VaultError.malformedRecoveryKey
        }
        return try unlock(isRecovery: true) { file in try file.unwrapKey(recoverySecret: secret) }
    }

    /// Unlock with a key the Keychain released after a successful Touch ID
    /// check. The key itself is the proof, so there is nothing to verify here
    /// beyond it actually opening the vault.
    func unlock(dataKey: SymmetricKey) throws -> UnlockResult {
        guard vaultExists else { throw VaultError.noVault }
        let store = try EntryStore(paths: paths, dataKey: dataKey)
        var file = try VaultFile.read(from: paths.vaultFile)
        if file.failedAttempts != 0 || file.lockedOutUntil != nil {
            file.recordSuccess()
            try? file.write(to: paths.vaultFile)
        }
        return UnlockResult(store: store, dataKey: dataKey)
    }

    private func unlock(
        isRecovery: Bool = false,
        unwrap: (VaultFile) throws -> SymmetricKey
    ) throws -> UnlockResult {
        guard vaultExists else { throw VaultError.noVault }

        var file = try VaultFile.read(from: paths.vaultFile)

        let remaining = file.lockoutRemaining
        guard remaining <= 0 else { throw VaultError.lockedOut(remaining: remaining) }

        let dataKey: SymmetricKey
        do {
            dataKey = try unwrap(file)
        } catch {
            file.recordFailure()
            try? file.write(to: paths.vaultFile)
            throw isRecovery ? VaultError.wrongRecoveryKey : VaultError.wrongPasscode
        }

        file.recordSuccess()
        try? file.write(to: paths.vaultFile)

        let store = try EntryStore(paths: paths, dataKey: dataKey)
        return UnlockResult(store: store, dataKey: dataKey)
    }

    // MARK: - Maintenance

    /// Re-wraps the data key under a new passcode. Entries are untouched, so
    /// this is instant regardless of how much has been written.
    func changePasscode(current: String, new: String, rounds: UInt32 = KeyDerivation.defaultRounds) throws {
        var file = try VaultFile.read(from: paths.vaultFile)

        let remaining = file.lockoutRemaining
        guard remaining <= 0 else { throw VaultError.lockedOut(remaining: remaining) }

        let dataKey: SymmetricKey
        do {
            dataKey = try file.unwrapKey(passcode: current)
        } catch {
            file.recordFailure()
            try? file.write(to: paths.vaultFile)
            throw VaultError.wrongPasscode
        }

        file.recordSuccess()
        try file.rewrap(dataKey: dataKey, newPasscode: new, rounds: rounds)
        try file.write(to: paths.vaultFile)
    }

    /// Issues a fresh recovery key and invalidates the old one.
    func regenerateRecoveryKey(passcode: String) throws -> String {
        var file = try VaultFile.read(from: paths.vaultFile)
        let dataKey: SymmetricKey
        do {
            dataKey = try file.unwrapKey(passcode: passcode)
        } catch {
            throw VaultError.wrongPasscode
        }

        let recovery = RecoveryKey.generate()
        try file.rewrapRecovery(dataKey: dataKey, recoverySecret: recovery.secret)
        try file.write(to: paths.vaultFile)
        return recovery.formatted
    }

    func setBiometricEnabled(_ enabled: Bool) throws {
        var file = try VaultFile.read(from: paths.vaultFile)
        file.biometricEnabled = enabled
        try file.write(to: paths.vaultFile)
    }

    var biometricEnabled: Bool {
        (try? VaultFile.read(from: paths.vaultFile))?.biometricEnabled ?? false
    }

    var lockoutRemaining: TimeInterval {
        (try? VaultFile.read(from: paths.vaultFile))?.lockoutRemaining ?? 0
    }
}
