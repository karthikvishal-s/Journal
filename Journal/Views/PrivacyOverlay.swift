import SwiftUI

/// Covers the window whenever the app isn't frontmost.
///
/// This is what hides the journal in Mission Control, the ⌘-Tab switcher and
/// window previews, all of which snapshot the window while the app is in the
/// background. It is a real opaque view rather than a blur filter, because a
/// heavy blur of a page of text can still betray its shape and length.
///
/// `NSWindow.sharingType = .none` (see `WindowConfigurator`) covers the other
/// half of the problem: screen recording and screen sharing.
struct PrivacyCurtain: ViewModifier {

    let isObscured: Bool

    func body(content: Content) -> some View {
        content
            .overlay {
                if isObscured {
                    ZStack {
                        Rectangle()
                            .fill(Theme.paper)
                        VStack(spacing: 14) {
                            Image(systemName: "book.closed")
                                .font(.system(size: 30, weight: .light))
                                .foregroundStyle(Theme.accent.opacity(0.7))
                            Text("Journal")
                                .font(Theme.reading(16))
                                .foregroundStyle(Theme.inkSoft)
                        }
                    }
                    .ignoresSafeArea()
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.12), value: isObscured)
    }
}

extension View {
    func privacyCurtain(isObscured: Bool) -> some View {
        modifier(PrivacyCurtain(isObscured: isObscured))
    }
}

/// Applies window-level settings SwiftUI doesn't expose.
struct WindowConfigurator: NSViewRepresentable {

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            // Keeps the window out of screen recordings, screenshots taken by
            // other apps, and screen sharing sessions.
            window.sharingType = .none
            window.titlebarAppearsTransparent = true
            window.backgroundColor = NSColor(Theme.paper)
            window.isMovableByWindowBackground = true
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
