import SwiftUI

/// Chooses what the window shows. The journal proper is reachable from exactly
/// one branch of this switch, and only with a `Session` in hand.
struct RootView: View {

    @EnvironmentObject private var lock: LockController

    var body: some View {
        Group {
            if lock.isPresentingSetup {
                SetupView()
            } else {
                switch lock.phase {
                case .loading:
                    Color.clear
                case .needsSetup:
                    SetupView()
                case .locked:
                    LockScreenView()
                case .unlocked(let session):
                    JournalWindow(session: session)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: lock.isUnlocked)
        // The curtain sits outside the switch so it covers every phase,
        // including the unlocked journal.
        .privacyCurtain(isObscured: lock.isObscured && lock.isUnlocked)
        .background(WindowConfigurator())
        .preferredColorScheme(nil)
    }
}
