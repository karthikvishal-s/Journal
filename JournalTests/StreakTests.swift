import XCTest

@testable import Journal

final class StreakTests: XCTestCase {

    private let calendar = Calendar.current
    private lazy var today = calendar.startOfDay(for: Date())

    private func daysAgo(_ counts: [Int]) -> Set<Date> {
        Set(counts.compactMap { calendar.date(byAdding: .day, value: -$0, to: today) })
    }

    // MARK: - Current streak

    func testEmptyJournalHasNoStreak() {
        XCTAssertEqual(Streak.current(days: [], today: today), 0)
    }

    func testSingleEntryToday() {
        XCTAssertEqual(Streak.current(days: daysAgo([0]), today: today), 1)
    }

    func testConsecutiveDaysEndingToday() {
        XCTAssertEqual(Streak.current(days: daysAgo([0, 1, 2, 3]), today: today), 4)
    }

    /// The rule that matters most in daily use: at 9am you haven't written
    /// today yet, and the streak you built must still be there.
    func testStreakSurvivesAnUnwrittenToday() {
        XCTAssertEqual(Streak.current(days: daysAgo([1, 2, 3]), today: today), 3)
    }

    func testStreakBreaksAfterAFullMissedDay() {
        // Wrote up to two days ago, nothing since: the gap at day 1 breaks it.
        XCTAssertEqual(Streak.current(days: daysAgo([2, 3, 4]), today: today), 0)
    }

    func testOnlyTheRunEndingNowCounts() {
        // A long-ago run of five plus today: today's run is 1.
        XCTAssertEqual(Streak.current(days: daysAgo([0, 10, 11, 12, 13, 14]), today: today), 1)
    }

    func testGapInsideTheRunStopsTheCount() {
        XCTAssertEqual(Streak.current(days: daysAgo([0, 1, 3, 4]), today: today), 2)
    }

    func testMultipleEntriesOnOneDayCountOnce() {
        // daysWithEntries is a Set, so this is inherent — asserted to keep it so.
        XCTAssertEqual(Streak.current(days: daysAgo([0, 0, 0]), today: today), 1)
    }

    func testFutureDatesDoNotInflateTheStreak() {
        var days = daysAgo([0, 1])
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) {
            days.insert(tomorrow)
        }
        XCTAssertEqual(Streak.current(days: days, today: today), 2)
    }

    // MARK: - Longest streak

    func testLongestStreak() {
        XCTAssertEqual(Streak.longest(days: []), 0)
        XCTAssertEqual(Streak.longest(days: daysAgo([0])), 1)
        XCTAssertEqual(Streak.longest(days: daysAgo([0, 1, 2])), 3)
        // Runs of 2 and 4; the longer wins.
        XCTAssertEqual(Streak.longest(days: daysAgo([0, 1, 5, 6, 7, 8])), 4)
    }

    // MARK: - Labels

    func testLabels() {
        XCTAssertEqual(Streak.label(0), "No streak yet")
        XCTAssertEqual(Streak.label(1), "1 day")
        XCTAssertEqual(Streak.label(7), "7 days")
    }
}
