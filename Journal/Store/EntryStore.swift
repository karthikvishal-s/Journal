import CryptoKit
import Foundation

/// Reads and writes entries, always encrypted.
///
/// An `EntryStore` cannot be constructed without a data key, which is the point:
/// there is no such thing as a store you can read from while the app is locked.
/// Locking drops the store, and with it the only reference to the key.
final class EntryStore {

    private let paths: VaultPaths
    private let dataKey: SymmetricKey

    /// Kept in memory while unlocked so the calendar and search don't hit the
    /// disk on every keystroke. Dropped wholesale on lock.
    private(set) var index: EntryIndex

    init(paths: VaultPaths, dataKey: SymmetricKey) throws {
        self.paths = paths
        self.dataKey = dataKey
        try paths.createDirectoriesIfNeeded()

        // A damaged or missing index is recoverable; a damaged entry is not, so
        // only the index gets this treatment.
        if let loaded = try? Self.loadIndex(paths: paths, key: dataKey) {
            self.index = loaded
        } else {
            self.index = EntryIndex()
            try rebuildIndex()
        }
    }

    // MARK: - Contexts

    private static func entryContext(id: UUID) -> String {
        // Binding the entry's own id into the AAD is what stops one day's file
        // being renamed over another's.
        "journal.entry.v1:\(id.uuidString)"
    }

    private static let indexContext = "journal.index.v1"

    // MARK: - Entries

    func loadEntry(id: UUID) throws -> Entry {
        let box = try Data(contentsOf: paths.entryFile(id: id))
        return try CryptoBox.open(box, as: Entry.self, key: dataKey, context: Self.entryContext(id: id))
    }

    func save(_ entry: Entry) throws {
        var entry = entry
        entry.updatedAt = Date()

        let box = try CryptoBox.seal(entry, key: dataKey, context: Self.entryContext(id: entry.id))
        try paths.createDirectoriesIfNeeded()
        try box.write(to: paths.entryFile(id: entry.id), options: [.atomic])

        index.upsert(EntryIndexRecord(entry: entry))
        try persistIndex()
    }

    func delete(id: UUID) throws {
        let url = paths.entryFile(id: id)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        index.remove(id: id)
        try persistIndex()
    }

    /// Loads every entry. Used by export, backup and full-text search, all of
    /// which need the bodies; the results stay in memory only.
    func loadAllEntries() throws -> [Entry] {
        try index.records
            .map { try loadEntry(id: $0.id) }
            .sorted { ($0.day, $0.createdAt) < ($1.day, $1.createdAt) }
    }

    // MARK: - Index

    private static func loadIndex(paths: VaultPaths, key: SymmetricKey) throws -> EntryIndex {
        let box = try Data(contentsOf: paths.indexFile)
        return try CryptoBox.open(box, as: EntryIndex.self, key: key, context: indexContext)
    }

    private func persistIndex() throws {
        let box = try CryptoBox.seal(index, key: dataKey, context: Self.indexContext)
        try box.write(to: paths.indexFile, options: [.atomic])
    }

    /// Reconstructs the index by opening every entry file. The fallback when
    /// `index.enc` is missing or unreadable.
    @discardableResult
    func rebuildIndex() throws -> EntryIndex {
        var rebuilt = EntryIndex()

        let files = (try? FileManager.default.contentsOfDirectory(
            at: paths.entriesDirectory,
            includingPropertiesForKeys: nil
        )) ?? []

        for file in files where file.pathExtension == "enc" {
            guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent) else { continue }
            // Skip anything that won't open rather than failing the whole
            // rebuild — one damaged file shouldn't cost access to the rest.
            guard let entry = try? loadEntry(id: id) else { continue }
            rebuilt.upsert(EntryIndexRecord(entry: entry))
        }

        index = rebuilt
        try persistIndex()
        return rebuilt
    }
}

private func < (lhs: (Date, Date), rhs: (Date, Date)) -> Bool {
    lhs.0 == rhs.0 ? lhs.1 < rhs.1 : lhs.0 < rhs.0
}
