import CryptoKit
import XCTest

@testable import Journal

final class VaultTests: XCTestCase {

    private var vault: TemporaryVault!
    private var manager: VaultManager!
    private let rounds = TemporaryVault.testRounds

    override func setUpWithError() throws {
        vault = try TemporaryVault()
        manager = vault.manager()
    }

    override func tearDown() {
        manager = nil
        vault = nil
    }

    // MARK: - Setup

    func testCreateVaultProducesUnlockedSessionAndRecoveryKey() throws {
        let result = try manager.createVault(passcode: "correct horse", rounds: rounds)

        XCTAssertTrue(manager.vaultExists)
        XCTAssertTrue(RecoveryKey.looksLikeRecoveryKey(result.recoveryKey))
        XCTAssertEqual(result.store.index.records.count, 0)
    }

    func testCannotCreateTwice() throws {
        _ = try manager.createVault(passcode: "a", rounds: rounds)
        assertThrows(try manager.createVault(passcode: "b", rounds: rounds)) { error in
            XCTAssertEqual(error as? VaultError, .vaultAlreadyExists)
        }
    }

    func testVaultFileContainsNoPlaintextSecrets() throws {
        let passcode = "SuperSecretPasscode"
        _ = try manager.createVault(passcode: passcode, rounds: rounds)

        let raw = try Data(contentsOf: vault.paths.vaultFile)
        XCTAssertNil(raw.range(of: Data(passcode.utf8)))
    }

    // MARK: - Unlocking

    func testUnlockWithCorrectPasscode() throws {
        _ = try manager.createVault(passcode: "correct horse", rounds: rounds)
        XCTAssertNoThrow(try manager.unlock(passcode: "correct horse"))
    }

    func testUnlockWithWrongPasscodeFails() throws {
        _ = try manager.createVault(passcode: "correct horse", rounds: rounds)
        assertThrows(try manager.unlock(passcode: "wrong horse")) { error in
            XCTAssertEqual(error as? VaultError, .wrongPasscode)
        }
    }

    func testUnlockWithRecoveryKey() throws {
        let setup = try manager.createVault(passcode: "correct horse", rounds: rounds)
        XCTAssertNoThrow(try manager.unlock(recoveryKeyInput: setup.recoveryKey))
    }

    func testRecoveryKeyAndPasscodeYieldTheSameDataKey() throws {
        let setup = try manager.createVault(passcode: "correct horse", rounds: rounds)

        let viaPasscode = try manager.unlock(passcode: "correct horse")
        let viaRecovery = try manager.unlock(recoveryKeyInput: setup.recoveryKey)

        XCTAssertEqual(viaPasscode.dataKey, viaRecovery.dataKey)
        XCTAssertEqual(viaPasscode.dataKey, setup.dataKey)
    }

    func testWrongRecoveryKeyFails() throws {
        _ = try manager.createVault(passcode: "correct horse", rounds: rounds)
        let other = RecoveryKey.generate().formatted

        assertThrows(try manager.unlock(recoveryKeyInput: other)) { error in
            XCTAssertEqual(error as? VaultError, .wrongRecoveryKey)
        }
    }

    func testMalformedRecoveryKeyIsReportedDistinctly() throws {
        _ = try manager.createVault(passcode: "correct horse", rounds: rounds)
        assertThrows(try manager.unlock(recoveryKeyInput: "nope")) { error in
            XCTAssertEqual(error as? VaultError, .malformedRecoveryKey)
        }
    }

    // MARK: - Changing the passcode

    func testChangePasscodeKeepsDataKeyAndEntries() throws {
        let setup = try manager.createVault(passcode: "old", rounds: rounds)
        let entry = Entry(title: "Before", body: "written under the old passcode")
        try setup.store.save(entry)

        try manager.changePasscode(current: "old", new: "new", rounds: rounds)

        // Old passcode is dead, new one works...
        assertThrows(try manager.unlock(passcode: "old"))
        let reopened = try manager.unlock(passcode: "new")

        // ...and crucially the underlying key is unchanged, so entries written
        // before the change are still readable.
        XCTAssertEqual(reopened.dataKey, setup.dataKey)
        XCTAssertEqual(try reopened.store.loadEntry(id: entry.id).body, "written under the old passcode")
    }

    func testChangePasscodeRejectsWrongCurrent() throws {
        _ = try manager.createVault(passcode: "old", rounds: rounds)
        assertThrows(try manager.changePasscode(current: "nope", new: "new", rounds: rounds)) { error in
            XCTAssertEqual(error as? VaultError, .wrongPasscode)
        }
        XCTAssertNoThrow(try manager.unlock(passcode: "old"))
    }

    func testRecoveryKeySurvivesPasscodeChange() throws {
        let setup = try manager.createVault(passcode: "old", rounds: rounds)
        try manager.changePasscode(current: "old", new: "new", rounds: rounds)
        XCTAssertNoThrow(try manager.unlock(recoveryKeyInput: setup.recoveryKey))
    }

    func testRegenerateRecoveryKeyInvalidatesTheOldOne() throws {
        let setup = try manager.createVault(passcode: "pass", rounds: rounds)
        let replacement = try manager.regenerateRecoveryKey(passcode: "pass")

        XCTAssertNotEqual(replacement, setup.recoveryKey)
        XCTAssertNoThrow(try manager.unlock(recoveryKeyInput: replacement))
        assertThrows(try manager.unlock(recoveryKeyInput: setup.recoveryKey)) { error in
            XCTAssertEqual(error as? VaultError, .wrongRecoveryKey)
        }
    }

    // MARK: - Lockout

    func testLockoutBeginsAfterFiveFailures() throws {
        _ = try manager.createVault(passcode: "right", rounds: rounds)

        // The first four are free — typos happen.
        for _ in 0 ..< 4 {
            assertThrows(try manager.unlock(passcode: "wrong")) { error in
                XCTAssertEqual(error as? VaultError, .wrongPasscode)
            }
        }
        XCTAssertEqual(manager.lockoutRemaining, 0)

        // The fifth starts the delay.
        assertThrows(try manager.unlock(passcode: "wrong"))
        XCTAssertGreaterThan(manager.lockoutRemaining, 0)

        // And now even the correct passcode has to wait.
        assertThrows(try manager.unlock(passcode: "right")) { error in
            guard case .lockedOut = error as? VaultError else {
                return XCTFail("Expected lockedOut, got \(error)")
            }
        }
    }

    func testLockoutStatePersistsAcrossManagerInstances() throws {
        _ = try manager.createVault(passcode: "right", rounds: rounds)
        for _ in 0 ..< 5 {
            assertThrows(try manager.unlock(passcode: "wrong"))
        }

        // Quitting and relaunching the app must not clear the penalty.
        let freshManager = vault.manager()
        XCTAssertGreaterThan(freshManager.lockoutRemaining, 0)
    }

    func testSuccessfulUnlockClearsFailureCount() throws {
        _ = try manager.createVault(passcode: "right", rounds: rounds)
        for _ in 0 ..< 3 {
            assertThrows(try manager.unlock(passcode: "wrong"))
        }

        XCTAssertNoThrow(try manager.unlock(passcode: "right"))

        let file = try VaultFile.read(from: vault.paths.vaultFile)
        XCTAssertEqual(file.failedAttempts, 0)
        XCTAssertNil(file.lockedOutUntil)
    }

    func testLockoutIntervalEscalates() {
        XCTAssertEqual(VaultFile.lockoutInterval(afterFailures: 1), 0)
        XCTAssertEqual(VaultFile.lockoutInterval(afterFailures: 4), 0)
        XCTAssertEqual(VaultFile.lockoutInterval(afterFailures: 5), 5)
        XCTAssertEqual(VaultFile.lockoutInterval(afterFailures: 6), 15)
        XCTAssertEqual(VaultFile.lockoutInterval(afterFailures: 7), 60)
        XCTAssertEqual(VaultFile.lockoutInterval(afterFailures: 8), 300)
        XCTAssertEqual(VaultFile.lockoutInterval(afterFailures: 20), 900, "should cap")
    }

    // MARK: - Missing vault

    func testUnlockingWithNoVaultFails() {
        assertThrows(try manager.unlock(passcode: "anything")) { error in
            XCTAssertEqual(error as? VaultError, .noVault)
        }
    }
}
