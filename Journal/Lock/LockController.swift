import AppKit
import CryptoKit
import Foundation
import LocalAuthentication
import SwiftUI

/// The gate. Owns the unlocked session and every path in and out of it.
///
/// `phase` is the app's whole top-level state. Because the decrypted `EntryStore`
/// lives *inside* the `.unlocked` case rather than beside it, locking cannot
/// leave a decrypted store reachable — dropping the phase drops the store, and
/// with it the only strong reference to the data key.
@MainActor
final class LockController: ObservableObject {

    enum Phase {
        case loading
        case needsSetup
        case locked
        case unlocked(Session)
    }

    /// An unlocked session. Deliberately a class with no public initialiser
    /// path other than through `LockController`.
    final class Session {
        let store: EntryStore
        let dataKey: SymmetricKey
        init(store: EntryStore, dataKey: SymmetricKey) {
            self.store = store
            self.dataKey = dataKey
        }
    }

    @Published private(set) var phase: Phase = .loading
    @Published var unlockError: String?
    @Published private(set) var lockoutRemaining: TimeInterval = 0

    /// True while the app is in the background or hidden. Drives the privacy
    /// overlay that covers the window in Mission Control and the app switcher.
    @Published private(set) var isObscured = false

    @Published private(set) var keychainMode: VaultKeychain.Mode?

    /// Setup owns the screen until the user has acknowledged the recovery key.
    ///
    /// Needed because `completeSetup` unlocks the vault immediately — without
    /// this flag the phase change would whisk the recovery key off screen the
    /// instant it was generated, which is the one moment it can ever be shown.
    @Published private(set) var isPresentingSetup = false

    let vault: VaultManager
    let settings: AppSettings
    private let keychain = VaultKeychain()
    private var idleMonitor: IdleMonitor?
    private var lockoutTicker: Timer?
    private var observers: [Any] = []

    var isUnlocked: Bool {
        if case .unlocked = phase { return true }
        return false
    }

    var session: Session? {
        if case .unlocked(let session) = phase { return session }
        return nil
    }

    init(vault: VaultManager, settings: AppSettings) {
        self.vault = vault
        self.settings = settings
        self.idleMonitor = IdleMonitor { [weak self] in
            self?.lock(reason: .idle)
        }
        registerSystemObservers()
        refreshPhase()
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            DistributedNotificationCenter.default().removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    // MARK: - Phase

    private func refreshPhase() {
        let exists = vault.vaultExists
        phase = exists ? .locked : .needsSetup
        isPresentingSetup = !exists
        updateLockoutRemaining()
    }

    // MARK: - Setup

    func completeSetup(passcode: String, enableTouchID: Bool) throws -> String {
        let result = try vault.createVault(passcode: passcode)

        if enableTouchID && BiometricAuth.isAvailable {
            if let mode = try? keychain.store(dataKey: result.dataKey) {
                keychainMode = mode
                try? vault.setBiometricEnabled(true)
                settings.touchIDEnabled = true
            } else {
                settings.touchIDEnabled = false
            }
        } else {
            settings.touchIDEnabled = false
        }

        enterUnlocked(store: result.store, dataKey: result.dataKey)
        return result.recoveryKey
    }

    /// Called once the user confirms they've written the recovery key down.
    func finishSetup() {
        isPresentingSetup = false
    }

    // MARK: - Unlocking

    func unlock(passcode: String) {
        attempt { try self.vault.unlock(passcode: passcode) }
    }

    func unlock(recoveryKey: String) {
        attempt { try self.vault.unlock(recoveryKeyInput: recoveryKey) }
    }

    /// Routes a single text field to the right path: a recovery key is
    /// recognisable by its shape, so the user never has to say which they're
    /// typing.
    func submitSecret(_ text: String) {
        if RecoveryKey.looksLikeRecoveryKey(text) {
            unlock(recoveryKey: text)
        } else {
            unlock(passcode: text)
        }
    }

    var canUseTouchID: Bool {
        settings.touchIDEnabled && BiometricAuth.isAvailable && keychain.hasStoredKey && vault.biometricEnabled
    }

    func unlockWithTouchID() async {
        guard canUseTouchID else { return }
        guard vault.lockoutRemaining <= 0 else {
            updateLockoutRemaining()
            unlockError = VaultError.lockedOut(remaining: vault.lockoutRemaining).localizedDescription
            return
        }

        let context = BiometricAuth.makeContext()
        let reason = "Unlock your journal"

        do {
            // In .appEnforced mode this app-side check is the only gate, so it
            // must run before the key is fetched. In .dataProtection mode the
            // Keychain runs its own prompt and this one is skipped to avoid
            // asking for a fingerprint twice.
            if keychain.mode == .appEnforced {
                try await BiometricAuth.authenticate(reason: reason, context: context)
            }

            let dataKey = try keychain.loadDataKey(context: context, prompt: reason)
            let result = try vault.unlock(dataKey: dataKey)
            keychainMode = keychain.mode
            enterUnlocked(store: result.store, dataKey: result.dataKey)
        } catch KeychainError.cancelled {
            // Silent: the user chose the passcode field instead.
        } catch {
            unlockError = error.localizedDescription
        }
    }

    private func attempt(_ work: () throws -> VaultManager.UnlockResult) {
        do {
            let result = try work()
            enterUnlocked(store: result.store, dataKey: result.dataKey)
        } catch {
            unlockError = error.localizedDescription
            updateLockoutRemaining()
        }
    }

    private func enterUnlocked(store: EntryStore, dataKey: SymmetricKey) {
        unlockError = nil
        lockoutRemaining = 0
        lockoutTicker?.invalidate()
        phase = .unlocked(Session(store: store, dataKey: dataKey))
        idleMonitor?.start(interval: settings.autoLockInterval)
    }

    // MARK: - Locking

    enum LockReason {
        case manual, idle, systemSleep, screenLocked, resignedActive

        var message: String? {
            switch self {
            case .manual:          return nil
            case .idle:            return "Locked after inactivity"
            case .systemSleep:     return "Locked when your Mac slept"
            case .screenLocked:    return "Locked with your screen"
            case .resignedActive:  return nil
            }
        }
    }

    func lock(reason: LockReason = .manual) {
        guard isUnlocked else { return }
        idleMonitor?.stop()
        // Dropping the phase releases the Session, the EntryStore and the key.
        phase = .locked
        unlockError = reason.message
        updateLockoutRemaining()
    }

    /// Called when settings change while unlocked.
    func restartIdleTimer() {
        guard isUnlocked else { return }
        idleMonitor?.start(interval: settings.autoLockInterval)
    }

    // MARK: - Touch ID management

    func enableTouchID(dataKey: SymmetricKey) throws {
        let mode = try keychain.store(dataKey: dataKey)
        keychainMode = mode
        try vault.setBiometricEnabled(true)
    }

    func disableTouchID() {
        keychain.remove()
        keychainMode = nil
        try? vault.setBiometricEnabled(false)
    }

    /// After a passcode change the stored key is unchanged (only its wrapping
    /// changed), so nothing needs re-storing — but this keeps the two in step
    /// if that ever stops being true.
    func refreshKeychainMode() {
        keychainMode = keychain.hasStoredKey ? keychain.mode : nil
    }

    // MARK: - Lockout countdown

    private func updateLockoutRemaining() {
        lockoutRemaining = vault.lockoutRemaining
        lockoutTicker?.invalidate()
        guard lockoutRemaining > 0 else { return }

        let ticker = Timer(timeInterval: 1.0, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else { return }
                self.lockoutRemaining = self.vault.lockoutRemaining
                if self.lockoutRemaining <= 0 {
                    timer.invalidate()
                    self.unlockError = nil
                }
            }
        }
        RunLoop.main.add(ticker, forMode: .common)
        lockoutTicker = ticker
    }

    // MARK: - System triggers

    private func registerSystemObservers() {
        let workspace = NSWorkspace.shared.notificationCenter

        observers.append(workspace.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.lock(reason: .systemSleep) }
        })

        observers.append(workspace.addObserver(
            forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.lock(reason: .systemSleep) }
        })

        // Posted when the user locks the screen or fast-user-switches away.
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.lock(reason: .screenLocked) }
        })

        // The privacy overlay: cover the content whenever the app is not
        // frontmost, which is what Mission Control and the app switcher capture.
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.isObscured = true }
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isObscured = false
                self?.idleMonitor?.noteActivity()
            }
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didHideNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.isObscured = true }
        })
    }
}
