import AppKit
import Foundation

/// Fires when the user hasn't touched the app for a while.
///
/// "Touched" means keyboard, mouse or trackpad activity *directed at this app* —
/// the monitor is local, not global, so working in another app still counts as
/// idle here and the journal locks behind you. That is the intent: leaving
/// Journal open while you do something else is exactly when it should lock.
@MainActor
final class IdleMonitor {

    private var timer: Timer?
    private var eventMonitor: Any?
    private var lastActivity = Date()
    private var interval: TimeInterval?
    private let onIdle: () -> Void

    init(onIdle: @escaping () -> Void) {
        self.onIdle = onIdle
    }

    deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        timer?.invalidate()
    }

    /// `interval` of nil disables idle locking.
    func start(interval: TimeInterval?) {
        stop()
        self.interval = interval
        guard let interval else { return }

        lastActivity = Date()

        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel]
        ) { [weak self] event in
            // Must return the event unchanged, or input stops reaching the app.
            self?.noteActivity()
            return event
        }

        // Checked once a second rather than scheduled for the deadline, so that
        // a Mac waking from sleep can't overshoot a fired-but-missed timer.
        let ticker = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let interval = self.interval else { return }
                if Date().timeIntervalSince(self.lastActivity) >= interval {
                    self.stop()
                    self.onIdle()
                }
            }
        }
        RunLoop.main.add(ticker, forMode: .common)
        timer = ticker
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    func noteActivity() {
        lastActivity = Date()
    }
}
