import Foundation

/// Consecutive-day counting for the streak indicator.
///
/// Pure functions over a set of days, so the rules are testable without a
/// store, a clock or a UI.
enum Streak {

    /// Days in a row ending today.
    ///
    /// A streak survives a today with nothing written in it: if you wrote
    /// yesterday and it's now 9am, you still have a streak — you simply haven't
    /// written *yet*. It only breaks once a whole day has gone by unwritten.
    /// Counting today's absence as a break would nag the user from midnight
    /// onwards, which is the opposite of what this number is for.
    static func current(days: Set<Date>, today: Date = Date(), calendar: Calendar = .current) -> Int {
        let normalised = Set(days.map { calendar.startOfDay(for: $0) })
        let todayStart = calendar.startOfDay(for: today)

        guard !normalised.isEmpty else { return 0 }

        // Anchor on today if it has an entry, otherwise on yesterday.
        var cursor: Date
        if normalised.contains(todayStart) {
            cursor = todayStart
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: todayStart),
                  normalised.contains(yesterday) {
            cursor = yesterday
        } else {
            return 0
        }

        var count = 0
        while normalised.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    /// The longest run ever recorded, for the Settings summary.
    static func longest(days: Set<Date>, calendar: Calendar = .current) -> Int {
        let sorted = Set(days.map { calendar.startOfDay(for: $0) }).sorted()
        guard !sorted.isEmpty else { return 0 }

        var best = 1
        var run = 1

        for index in 1 ..< sorted.count {
            let expected = calendar.date(byAdding: .day, value: 1, to: sorted[index - 1])
            if let expected, calendar.isDate(sorted[index], inSameDayAs: expected) {
                run += 1
                best = max(best, run)
            } else {
                run = 1
            }
        }
        return best
    }

    static func label(_ count: Int) -> String {
        switch count {
        case 0:  return "No streak yet"
        case 1:  return "1 day"
        default: return "\(count) days"
        }
    }
}
