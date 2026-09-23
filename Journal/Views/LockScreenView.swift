import SwiftUI

/// What the app shows every time it opens. Nothing from the journal appears
/// here — not a title, not a date, not a count. Someone looking at this screen
/// learns only that a journal exists.
struct LockScreenView: View {

    @EnvironmentObject private var lock: LockController
    @State private var secret = ""
    @State private var isAuthenticating = false
    @FocusState private var fieldFocused: Bool

    private var isLockedOut: Bool { lock.lockoutRemaining > 0 }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "book.closed")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.accent)
                .padding(.bottom, 24)

            Text("Journal")
                .font(Theme.reading(28, weight: .medium))
                .foregroundStyle(Theme.ink)

            Text("Locked")
                .font(Theme.chromeFont(13))
                .foregroundStyle(Theme.inkSoft)
                .padding(.top, 6)

            VStack(spacing: 12) {
                SecureField("Passcode or recovery key", text: $secret)
                    .textFieldStyle(.plain)
                    .font(Theme.reading(15))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.cornerRadius)
                            .fill(Theme.chrome)
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                                    .stroke(fieldFocused ? Theme.accent.opacity(0.6) : Theme.rule, lineWidth: 1)
                            )
                    )
                    .focused($fieldFocused)
                    .disabled(isLockedOut)
                    .onSubmit(submit)

                Button(action: submit) {
                    Text("Unlock")
                        .font(Theme.chromeFont(13, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(secret.isEmpty || isLockedOut)

                if lock.canUseTouchID {
                    Button {
                        Task { await touchID() }
                    } label: {
                        Label("Unlock with Touch ID", systemImage: "touchid")
                            .font(Theme.chromeFont(12))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                    .disabled(isAuthenticating || isLockedOut)
                }
            }
            .frame(width: 280)
            .padding(.top, 32)

            // Reserved space, so the panel doesn't jump when a message appears.
            Group {
                if isLockedOut {
                    Text(lockoutMessage)
                        .foregroundStyle(Theme.accent)
                } else if let error = lock.unlockError {
                    Text(error)
                        .foregroundStyle(Theme.inkSoft)
                }
            }
            .font(Theme.chromeFont(12))
            .multilineTextAlignment(.center)
            .frame(width: 300, height: 34, alignment: .top)
            .padding(.top, 14)

            Spacer()

            Text("Your entries are encrypted on this Mac and never leave it.")
                .font(Theme.chromeFont(11))
                .foregroundStyle(Theme.inkFaint)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .paperBackground()
        .onAppear {
            fieldFocused = true
            // Offer Touch ID immediately — the common case is the owner sitting
            // down at their own Mac, and making them click first is friction.
            if lock.canUseTouchID && !isLockedOut {
                Task { await touchID() }
            }
        }
        .onChange(of: lock.phase.isUnlocked) { _, unlocked in
            if unlocked { secret = "" }
        }
    }

    private var lockoutMessage: String {
        let seconds = Int(lock.lockoutRemaining.rounded(.up))
        if seconds >= 60 {
            let minutes = (seconds + 59) / 60
            return "Too many attempts. Try again in \(minutes) minute\(minutes == 1 ? "" : "s")."
        }
        return "Too many attempts. Try again in \(seconds) second\(seconds == 1 ? "" : "s")."
    }

    private func submit() {
        guard !secret.isEmpty, !isLockedOut else { return }
        lock.submitSecret(secret)
        secret = ""
    }

    private func touchID() async {
        isAuthenticating = true
        await lock.unlockWithTouchID()
        isAuthenticating = false
    }
}

extension LockController.Phase {
    var isUnlocked: Bool {
        if case .unlocked = self { return true }
        return false
    }
}
