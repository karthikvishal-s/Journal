import Foundation

/// One row of the encrypted index: everything the calendar, browse list and
/// search-result rows need, without opening the entry itself.
struct EntryIndexRecord: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var day: Date
    var title: String
    var mood: Mood?
    var tags: [String]
    var wordCount: Int
    var createdAt: Date
    var updatedAt: Date

    init(entry: Entry) {
        self.id = entry.id
        self.day = entry.day
        self.title = entry.displayTitle
        self.mood = entry.mood
        self.tags = entry.tags
        self.wordCount = entry.wordCount
        self.createdAt = entry.createdAt
        self.updatedAt = entry.updatedAt
    }
}

/// The whole index, stored as one sealed box in `index.enc`.
///
/// This is a cache, not a source of truth. Every record here is derivable from
/// the entry files, and `EntryStore.rebuildIndex()` does exactly that if the
/// file is lost or damaged — so a corrupt index costs a moment of work, never
/// an entry.
struct EntryIndex: Codable, Equatable, Sendable {
    var records: [EntryIndexRecord]

    init(records: [EntryIndexRecord] = []) {
        self.records = records
    }

    // MARK: - Lookups

    subscript(id: UUID) -> EntryIndexRecord? {
        records.first { $0.id == id }
    }

    mutating func upsert(_ record: EntryIndexRecord) {
        if let position = records.firstIndex(where: { $0.id == record.id }) {
            records[position] = record
        } else {
            records.append(record)
        }
    }

    mutating func remove(id: UUID) {
        records.removeAll { $0.id == id }
    }

    /// Entries for a given calendar day, oldest first.
    func records(on day: Date) -> [EntryIndexRecord] {
        let target = Calendar.current.startOfDay(for: day)
        return records
            .filter { Calendar.current.isDate($0.day, inSameDayAs: target) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// The distinct days that have at least one entry — what the calendar dots
    /// are drawn from.
    var daysWithEntries: Set<Date> {
        Set(records.map { Calendar.current.startOfDay(for: $0.day) })
    }

    /// Every tag in use, sorted, deduplicated case-insensitively.
    var allTags: [String] {
        var seen: [String: String] = [:]
        for record in records {
            for tag in record.tags {
                seen[tag.lowercased()] = tag
            }
        }
        return seen.values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var newestFirst: [EntryIndexRecord] {
        records.sorted { ($0.day, $0.createdAt) > ($1.day, $1.createdAt) }
    }

    var totalWordCount: Int {
        records.reduce(0) { $0 + $1.wordCount }
    }
}

private func > (lhs: (Date, Date), rhs: (Date, Date)) -> Bool {
    lhs.0 == rhs.0 ? lhs.1 > rhs.1 : lhs.0 > rhs.0
}
