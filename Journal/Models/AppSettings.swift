import Foundation
import SwiftUI

/// User preferences. Deliberately *not* encrypted: an auto-lock interval and a
/// reminder time say nothing about what's in the journal. Anything that does —
/// titles, tags, moods, word counts — lives in `index.enc` instead.
@MainActor
final class AppSettings: ObservableObject {

    private enum Key {
        static let autoLockMinutes = "autoLockMinutes"
        static let touchIDEnabled = "touchIDEnabled"
        static let reminderEnabled = "reminderEnabled"
        static let reminderHour = "reminderHour"
        static let reminderMinute = "reminderMinute"
        static let hasCompletedSetup = "hasCompletedSetup"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.autoLockMinutes: 5,
            Key.touchIDEnabled: true,
            Key.reminderEnabled: false,
            Key.reminderHour: 21,
            Key.reminderMinute: 0,
        ])
        self.autoLockMinutes = defaults.integer(forKey: Key.autoLockMinutes)
        self.touchIDEnabled = defaults.bool(forKey: Key.touchIDEnabled)
        self.reminderEnabled = defaults.bool(forKey: Key.reminderEnabled)
        self.reminderHour = defaults.integer(forKey: Key.reminderHour)
        self.reminderMinute = defaults.integer(forKey: Key.reminderMinute)
    }

    /// 0 means "never idle-lock". The other triggers (sleep, screen lock, ⌘L)
    /// still apply — there is no way to turn locking off entirely.
    @Published var autoLockMinutes: Int {
        didSet { defaults.set(autoLockMinutes, forKey: Key.autoLockMinutes) }
    }

    @Published var touchIDEnabled: Bool {
        didSet { defaults.set(touchIDEnabled, forKey: Key.touchIDEnabled) }
    }

    @Published var reminderEnabled: Bool {
        didSet { defaults.set(reminderEnabled, forKey: Key.reminderEnabled) }
    }

    @Published var reminderHour: Int {
        didSet { defaults.set(reminderHour, forKey: Key.reminderHour) }
    }

    @Published var reminderMinute: Int {
        didSet { defaults.set(reminderMinute, forKey: Key.reminderMinute) }
    }

    var autoLockInterval: TimeInterval? {
        autoLockMinutes > 0 ? TimeInterval(autoLockMinutes * 60) : nil
    }

    var reminderTime: Date {
        get {
            Calendar.current.date(
                from: DateComponents(hour: reminderHour, minute: reminderMinute)
            ) ?? Date()
        }
        set {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            reminderHour = parts.hour ?? 21
            reminderMinute = parts.minute ?? 0
        }
    }

    static let autoLockChoices = [1, 2, 5, 10, 15, 30, 0]

    static func autoLockLabel(_ minutes: Int) -> String {
        switch minutes {
        case 0:  return "Never"
        case 1:  return "1 minute"
        default: return "\(minutes) minutes"
        }
    }
}
