import Foundation
import UserNotifications

/// The optional daily nudge.
///
/// A local notification only — it is scheduled on this Mac by this app and
/// delivered by macOS. Nothing is sent anywhere, and the text is fixed and
/// generic: a notification is visible on a lock screen, so it must never carry
/// anything from the journal itself.
@MainActor
enum Reminders {

    private static let identifier = "journal.daily.reminder"

    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Schedules (or reschedules) the daily reminder.
    static func schedule(hour: Int, minute: Int) async {
        await cancel()

        let content = UNMutableNotificationContent()
        content.title = "Journal"
        content.body = "A few minutes to write?"
        content.sound = .default

        var components = DateComponents()
        components.hour = hour
        components.minute = minute

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        )

        try? await UNUserNotificationCenter.current().add(request)
    }

    static func cancel() async {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    /// Brings the scheduled reminder in line with the current settings.
    static func sync(with settings: AppSettings) async {
        guard settings.reminderEnabled else {
            await cancel()
            return
        }
        guard await authorizationStatus() == .authorized else { return }
        await schedule(hour: settings.reminderHour, minute: settings.reminderMinute)
    }
}
