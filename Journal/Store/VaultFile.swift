import CryptoKit
import Foundation

/// The contents of `vault.json`.
///
/// Everything here is safe to read. The two wrapped keys are AES-GCM boxes
/// around the data encryption key; without the passcode or the recovery key
/// they are noise. Nothing in this file shortens a guessing attack beyond what
/// the KDF cost already allows.
struct VaultFile: Codable, Equatable {

    static let currentVersion = 1

    struct KDFParameters: Codable, Equatable {
        var algorithm: String      // "pbkdf2-sha256"
        var salt: Data
        var rounds: UInt32
    }

    struct WrappedKey: Codable, Equatable {
        var salt: Data
        var box: Data
    }

    var version: Int
    var passcodeKDF: KDFParameters
    var passcodeWrappedKey: Data
    var recovery: WrappedKey
    var biometricEnabled: Bool
    var createdAt: Date

    /// Escalating-delay state for wrong passcode attempts.
    ///
    /// This lives in a file the user can edit, so it is a speed bump against
    /// someone sitting at an unlocked Mac tapping at the lock screen, not a
    /// defence against an attacker who has copied the disk — that attacker is
    /// held off by the PBKDF2 cost instead. Persisting it here (rather than in
    /// memory) is what makes quitting and relaunching the app not reset it.
    var failedAttempts: Int
    var lockedOutUntil: Date?

    // MARK: - Contexts
    //
    // Distinct AAD strings for the two wrapping slots. Without these, a wrapped
    // key lifted from the recovery slot would also open in the passcode slot.

    static let passcodeContext = "journal.vault.passcode.v1"
    static let recoveryContext = "journal.vault.recovery.v1"

    // MARK: - Creation

    /// Builds a brand new vault: a random data encryption key, wrapped twice.
    ///
    /// The DEK itself never leaves memory unwrapped, and is not returned to the
    /// caller by accident — `create` hands it back deliberately so the caller
    /// can start an unlocked session without asking for the passcode again.
    static func create(
        passcode: String,
        recoverySecret: Data,
        rounds: UInt32 = KeyDerivation.defaultRounds
    ) throws -> (file: VaultFile, dataKey: SymmetricKey) {

        let dataKey = SymmetricKey(size: .bits256)
        let dataKeyBytes = dataKey.withUnsafeBytes { Data($0) }

        let passcodeSalt = KeyDerivation.randomSalt()
        let passcodeKEK = try KeyDerivation.key(fromPasscode: passcode, salt: passcodeSalt, rounds: rounds)
        let passcodeBox = try CryptoBox.seal(dataKeyBytes, key: passcodeKEK, context: passcodeContext)

        let recoverySalt = KeyDerivation.randomSalt()
        let recoveryKEK = KeyDerivation.key(fromRecoverySecret: recoverySecret, salt: recoverySalt)
        let recoveryBox = try CryptoBox.seal(dataKeyBytes, key: recoveryKEK, context: recoveryContext)

        let file = VaultFile(
            version: currentVersion,
            passcodeKDF: .init(algorithm: "pbkdf2-sha256", salt: passcodeSalt, rounds: rounds),
            passcodeWrappedKey: passcodeBox,
            recovery: .init(salt: recoverySalt, box: recoveryBox),
            biometricEnabled: false,
            createdAt: Date(),
            failedAttempts: 0,
            lockedOutUntil: nil
        )
        return (file, dataKey)
    }

    // MARK: - Unwrapping

    func unwrapKey(passcode: String) throws -> SymmetricKey {
        let kek = try KeyDerivation.key(
            fromPasscode: passcode,
            salt: passcodeKDF.salt,
            rounds: passcodeKDF.rounds
        )
        let bytes = try CryptoBox.open(passcodeWrappedKey, key: kek, context: Self.passcodeContext)
        return SymmetricKey(data: bytes)
    }

    func unwrapKey(recoverySecret: Data) throws -> SymmetricKey {
        let kek = KeyDerivation.key(fromRecoverySecret: recoverySecret, salt: recovery.salt)
        let bytes = try CryptoBox.open(recovery.box, key: kek, context: Self.recoveryContext)
        return SymmetricKey(data: bytes)
    }

    // MARK: - Re-wrapping

    /// Changing the passcode re-wraps the key. It never touches the entries, so
    /// it is instant no matter how much has been written.
    mutating func rewrap(
        dataKey: SymmetricKey,
        newPasscode: String,
        rounds: UInt32 = KeyDerivation.defaultRounds
    ) throws {
        let dataKeyBytes = dataKey.withUnsafeBytes { Data($0) }
        let salt = KeyDerivation.randomSalt()
        let kek = try KeyDerivation.key(fromPasscode: newPasscode, salt: salt, rounds: rounds)
        passcodeWrappedKey = try CryptoBox.seal(dataKeyBytes, key: kek, context: Self.passcodeContext)
        passcodeKDF = .init(algorithm: "pbkdf2-sha256", salt: salt, rounds: rounds)
    }

    /// Issues a replacement recovery key, invalidating the previous one.
    mutating func rewrapRecovery(dataKey: SymmetricKey, recoverySecret: Data) throws {
        let dataKeyBytes = dataKey.withUnsafeBytes { Data($0) }
        let salt = KeyDerivation.randomSalt()
        let kek = KeyDerivation.key(fromRecoverySecret: recoverySecret, salt: salt)
        recovery = .init(salt: salt, box: try CryptoBox.seal(dataKeyBytes, key: kek, context: Self.recoveryContext))
    }

    // MARK: - Lockout

    /// Delay after `n` consecutive failures. Free for the first few — typos are
    /// normal and this is the owner's own journal — then grows quickly.
    static func lockoutInterval(afterFailures n: Int) -> TimeInterval {
        switch n {
        case ..<5:   return 0
        case 5:      return 5
        case 6:      return 15
        case 7:      return 60
        case 8:      return 300
        default:     return 900     // capped at 15 minutes
        }
    }

    var lockoutRemaining: TimeInterval {
        guard let until = lockedOutUntil else { return 0 }
        return max(0, until.timeIntervalSinceNow)
    }

    mutating func recordFailure(now: Date = Date()) {
        failedAttempts += 1
        let delay = Self.lockoutInterval(afterFailures: failedAttempts)
        lockedOutUntil = delay > 0 ? now.addingTimeInterval(delay) : nil
    }

    mutating func recordSuccess() {
        failedAttempts = 0
        lockedOutUntil = nil
    }

    // MARK: - Persistence

    func write(to url: URL) throws {
        let data = try JSONCoding.encoder.encode(self)
        try data.write(to: url, options: [.atomic])
    }

    static func read(from url: URL) throws -> VaultFile {
        let data = try Data(contentsOf: url)
        let file = try JSONCoding.decoder.decode(VaultFile.self, from: data)
        guard file.version <= currentVersion else { throw VaultError.unsupportedVersion(file.version) }
        return file
    }
}

enum VaultError: LocalizedError, Equatable {
    case noVault
    case vaultAlreadyExists
    case wrongPasscode
    case wrongRecoveryKey
    case malformedRecoveryKey
    case lockedOut(remaining: TimeInterval)
    case unsupportedVersion(Int)
    case locked

    var errorDescription: String? {
        switch self {
        case .noVault:
            return "No journal has been set up yet."
        case .vaultAlreadyExists:
            return "A journal already exists in this location."
        case .wrongPasscode:
            return "That passcode isn't right."
        case .wrongRecoveryKey:
            return "That recovery key isn't right."
        case .malformedRecoveryKey:
            return "That doesn't look like a recovery key. It's 8 groups of 4 characters."
        case .lockedOut(let remaining):
            let seconds = Int(remaining.rounded(.up))
            return "Too many attempts. Try again in \(seconds) second\(seconds == 1 ? "" : "s")."
        case .unsupportedVersion(let version):
            return "This journal was written by a newer version of the app (format \(version))."
        case .locked:
            return "The journal is locked."
        }
    }
}
