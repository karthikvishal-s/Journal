import Foundation

/// Full-text search over decrypted entries.
///
/// There is no search index on disk, and there never will be one — an index of
/// the words in a journal is nearly as revealing as the journal. Instead the
/// bodies are decrypted into memory on demand and scanned there, and the
/// results are dropped when the app locks. For a personal journal this is
/// comfortably fast: tens of thousands of entries would still scan in
/// milliseconds.
struct SearchEngine {

    struct Result: Identifiable {
        let id: UUID
        let record: EntryIndexRecord
        /// A window of text around the first match, for the result row.
        let snippet: AttributedString
        let score: Int
    }

    /// Scans `entries` for `query`. Matching is case- and diacritic-insensitive,
    /// so "cafe" finds "café".
    static func search(query: String, in entries: [Entry], index: EntryIndex) -> [Result] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard needle.count >= 1 else { return [] }

        var results: [Result] = []

        for entry in entries {
            guard let record = index[entry.id] else { continue }

            var score = 0
            let titleHit = entry.title.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            let tagHit = entry.tags.contains { $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            let bodyRange = entry.body.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive])

            // Weighted so a title match outranks a passing mention in a body.
            if titleHit { score += 10 }
            if tagHit { score += 6 }
            if bodyRange != nil { score += 3 }

            guard score > 0 else { continue }

            results.append(
                Result(
                    id: entry.id,
                    record: record,
                    snippet: snippet(for: entry, matchRange: bodyRange, needle: needle),
                    score: score
                )
            )
        }

        return results.sorted {
            $0.score == $1.score ? $0.record.day > $1.record.day : $0.score > $1.score
        }
    }

    /// Builds a short excerpt with the match emphasised.
    private static func snippet(for entry: Entry, matchRange: Range<String.Index>?, needle: String) -> AttributedString {
        let body = entry.body.replacingOccurrences(of: "\n", with: " ")
        guard !body.isEmpty else { return AttributedString(entry.title) }

        // Re-find the range in the newline-flattened copy so the offsets line up.
        guard matchRange != nil,
              let range = body.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive])
        else {
            return AttributedString(String(body.prefix(140)))
        }

        let contextBefore = 40
        let contextAfter = 100

        let start = body.index(range.lowerBound, offsetBy: -contextBefore, limitedBy: body.startIndex)
            ?? body.startIndex
        let end = body.index(range.upperBound, offsetBy: contextAfter, limitedBy: body.endIndex)
            ?? body.endIndex

        var excerpt = String(body[start ..< end])
        if start > body.startIndex { excerpt = "…" + excerpt }
        if end < body.endIndex { excerpt += "…" }

        var attributed = AttributedString(excerpt)
        if let highlight = attributed.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) {
            attributed[highlight].inlinePresentationIntent = .stronglyEmphasized
        }
        return attributed
    }
}
