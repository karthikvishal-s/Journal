import Foundation

/// A single journal entry.
///
/// This is the *plaintext* shape. It only ever exists in memory or inside an
/// AES-GCM sealed box — it is never written to disk as-is. See `EntryStore`.
struct Entry: Codable, Identifiable, Equatable, Sendable {
    let id: UUID

    /// The day this entry belongs to, normalised to the start of that day in
    /// the current calendar. Several entries may share a `day`.
    var day: Date

    var title: String
    var body: String
    var mood: Mood?
    var tags: [String]

    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        day: Date = Date(),
        title: String = "",
        body: String = "",
        mood: Mood? = nil,
        tags: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.day = Calendar.current.startOfDay(for: day)
        self.title = title
        self.body = body
        self.mood = mood
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Words in the body. Computed rather than stored so it can never drift out
    /// of sync with the text; `EntryIndex` caches it for the browse view.
    var wordCount: Int {
        body.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    /// Title to show when the user hasn't written one: the first non-empty line
    /// of the body, stripped of any leading Markdown heading markers.
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }

        let firstLine = body
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces)
            .drop(while: { $0 == "#" || $0 == " " })

        let candidate = firstLine.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        return candidate.isEmpty ? "Untitled" : String(candidate.prefix(80))
    }

    var isEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && mood == nil
            && tags.isEmpty
    }
}
