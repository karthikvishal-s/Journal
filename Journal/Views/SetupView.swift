import SwiftUI

/// First launch: choose a passcode, then write down the recovery key.
///
/// The recovery key step is deliberately awkward to rush past. It is shown
/// once, the continue button stays disabled until the user ticks a box, and
/// the warning says plainly what is lost if both secrets go. Everything after
/// this screen depends on the user having taken it seriously.
struct SetupView: View {

    @EnvironmentObject private var lock: LockController

    private enum Step {
        case welcome
        case choosePasscode
        case showRecoveryKey(String)
    }

    @State private var step: Step = .welcome
    @State private var passcode = ""
    @State private var confirmation = ""
    @State private var enableTouchID = true
    @State private var error: String?
    @State private var hasSavedRecoveryKey = false
    @State private var didCopy = false

    var body: some View {
        VStack(spacing: 0) {
            switch step {
            case .welcome:            welcome
            case .choosePasscode:     choosePasscode
            case .showRecoveryKey(let key): recoveryKey(key)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .paperBackground()
    }

    // MARK: - Welcome

    private var welcome: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "book.closed")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Theme.accent)

            Text("Your journal")
                .font(Theme.reading(30, weight: .medium))
                .foregroundStyle(Theme.ink)
                .padding(.top, 24)

            VStack(alignment: .leading, spacing: 16) {
                promise("lock.fill", "Everything you write is encrypted on this Mac.")
                promise("wifi.slash", "The app has no network access at all — nothing is ever uploaded.")
                promise("key.fill", "Only your passcode or recovery key can open it. Not even this app can read it while locked.")
            }
            .frame(width: 400)
            .padding(.top, 36)

            Button {
                withAnimation(.easeInOut(duration: 0.25)) { step = .choosePasscode }
            } label: {
                Text("Begin")
                    .font(Theme.chromeFont(13, weight: .medium))
                    .frame(width: 180)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .padding(.top, 40)

            Spacer()
        }
    }

    private func promise(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(Theme.accent)
                .frame(width: 20)
                .padding(.top, 2)
            Text(text)
                .font(Theme.reading(14))
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Passcode

    private var passcodeIsValid: Bool {
        passcode.count >= 6 && passcode == confirmation
    }

    private var choosePasscode: some View {
        VStack(spacing: 0) {
            Spacer()

            Text("Choose a passcode")
                .font(Theme.reading(24, weight: .medium))
                .foregroundStyle(Theme.ink)

            Text("At least 6 characters. A short phrase you'll remember is stronger than a short word.")
                .font(Theme.chromeFont(12))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .frame(width: 340)
                .padding(.top, 8)

            VStack(spacing: 10) {
                field("Passcode", text: $passcode)
                field("Confirm passcode", text: $confirmation)

                if BiometricAuth.isAvailable {
                    Toggle(isOn: $enableTouchID) {
                        Text("Also unlock with Touch ID")
                            .font(Theme.chromeFont(12))
                            .foregroundStyle(Theme.inkSoft)
                    }
                    .toggleStyle(.checkbox)
                    .padding(.top, 4)
                }
            }
            .frame(width: 300)
            .padding(.top, 28)

            Group {
                if let error {
                    Text(error).foregroundStyle(Theme.accent)
                } else if !passcode.isEmpty && passcode.count < 6 {
                    Text("A little longer, please.").foregroundStyle(Theme.inkFaint)
                } else if !confirmation.isEmpty && passcode != confirmation {
                    Text("Those don't match yet.").foregroundStyle(Theme.inkFaint)
                }
            }
            .font(Theme.chromeFont(12))
            .frame(height: 20)
            .padding(.top, 12)

            Button(action: createVault) {
                Text("Create journal")
                    .font(Theme.chromeFont(13, weight: .medium))
                    .frame(width: 180)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(!passcodeIsValid)
            .padding(.top, 10)

            Spacer()
        }
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        SecureField(label, text: text)
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
                            .stroke(Theme.rule, lineWidth: 1)
                    )
            )
    }

    private func createVault() {
        guard passcodeIsValid else { return }
        do {
            let key = try lock.completeSetup(passcode: passcode, enableTouchID: enableTouchID)
            passcode = ""
            confirmation = ""
            withAnimation(.easeInOut(duration: 0.25)) { step = .showRecoveryKey(key) }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Recovery key

    private func recoveryKey(_ key: String) -> some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "key.horizontal.fill")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Theme.accent)

            Text("Write this down now")
                .font(Theme.reading(24, weight: .medium))
                .foregroundStyle(Theme.ink)
                .padding(.top, 18)

            Text("This is your recovery key. It is the only way back in if you forget your passcode.")
                .font(Theme.chromeFont(12))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .frame(width: 400)
                .padding(.top, 8)

            Text(key)
                .font(.system(size: 17, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.ink)
                .textSelection(.enabled)
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: Theme.cornerRadius)
                        .fill(Theme.chrome)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                                .stroke(Theme.accent.opacity(0.35), lineWidth: 1)
                        )
                )
                .padding(.top, 26)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(key, forType: .string)
                didCopy = true
            } label: {
                Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                    .font(Theme.chromeFont(12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)
            .padding(.top, 12)

            // The warning, stated plainly rather than softened.
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.accent)
                    .font(.system(size: 13))
                    .padding(.top, 1)
                Text("If you lose both your passcode and this recovery key, your entries cannot be recovered — not by you, not by anyone. There is no backdoor and no reset. Keep this somewhere away from your Mac.")
                    .font(Theme.chromeFont(12))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(width: 440, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .fill(Theme.accent.opacity(0.08))
            )
            .padding(.top, 28)

            Toggle(isOn: $hasSavedRecoveryKey) {
                Text("I've written down my recovery key")
                    .font(Theme.chromeFont(12))
                    .foregroundStyle(Theme.ink)
            }
            .toggleStyle(.checkbox)
            .padding(.top, 20)

            Button {
                // Nothing to do: the session is already unlocked. Clearing the
                // phase is what dismisses this screen.
                lock.finishSetup()
            } label: {
                Text("Start writing")
                    .font(Theme.chromeFont(13, weight: .medium))
                    .frame(width: 180)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(!hasSavedRecoveryKey)
            .padding(.top, 16)

            Spacer()
        }
    }
}
