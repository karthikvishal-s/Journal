import CryptoKit
import XCTest

@testable import Journal

final class StoreTests: XCTestCase {

    private var vault: TemporaryVault!
    private var key: SymmetricKey!
    private var store: EntryStore!

    override func setUpWithError() throws {
        vault = try TemporaryVault()
        key = SymmetricKey(size: .bits256)
        store = try EntryStore(paths: vault.paths, dataKey: key)
    }

    override func tearDown() {
        store = nil
        key = nil
        vault = nil
    }

    // MARK: - The round trip the brief asks for

    func testSaveThenLoadRoundTrip() throws {
        let entry = Entry(
            day: Date(),
            title: "A good day",
            body: "# Heading\n\nSome **bold** text and a list:\n\n- one\n- two",
            mood: .good,
            tags: ["work", "calm"]
        )

        try store.save(entry)
        let loaded = try store.loadEntry(id: entry.id)

        XCTAssertEqual(loaded.id, entry.id)
        XCTAssertEqual(loaded.title, entry.title)
        XCTAssertEqual(loaded.body, entry.body)
        XCTAssertEqual(loaded.mood, entry.mood)
        XCTAssertEqual(loaded.tags, entry.tags)
        XCTAssertEqual(Calendar.current.startOfDay(for: loaded.day),
                       Calendar.current.startOfDay(for: entry.day))
    }

    func testNothingReadableIsWrittenToDisk() throws {
        let secret = "I told nobody about the interview"
        let entry = Entry(title: "Private", body: secret, tags: ["confidential"])
        try store.save(entry)

        // Walk every byte of every file under the vault root and assert the
        // words never appear. This is the claim the whole app rests on.
        let files = FileManager.default.enumerator(at: vault.paths.root, includingPropertiesForKeys: nil)!
        var filesChecked = 0

        for case let url as URL in files {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            let data = try Data(contentsOf: url)
            filesChecked += 1

            XCTAssertNil(data.range(of: Data(secret.utf8)), "Plaintext body found in \(url.lastPathComponent)")
            XCTAssertNil(data.range(of: Data("Private".utf8)), "Plaintext title found in \(url.lastPathComponent)")
            XCTAssertNil(data.range(of: Data("confidential".utf8)), "Plaintext tag found in \(url.lastPathComponent)")
        }

        XCTAssertGreaterThan(filesChecked, 0, "Expected to have checked some files")
    }

    func testFilenamesLeakNoMetadata() throws {
        try store.save(Entry(title: "Dentist appointment", body: "text"))

        let names = try FileManager.default
            .contentsOfDirectory(atPath: vault.paths.entriesDirectory.path)

        // Filenames are UUIDs only — no dates, no titles.
        for name in names {
            let stem = (name as NSString).deletingPathExtension
            XCTAssertNotNil(UUID(uuidString: stem), "Unexpected filename: \(name)")
        }
    }

    // MARK: - Wrong key

    func testWrongKeyCannotReadEntries() throws {
        let entry = Entry(title: "Secret", body: "contents")
        try store.save(entry)

        let wrongKey = SymmetricKey(size: .bits256)
        let attacker = try EntryStore(paths: vault.paths, dataKey: wrongKey)

        assertThrows(try attacker.loadEntry(id: entry.id)) { error in
            XCTAssertEqual(error as? CryptoError, .authenticationFailed)
        }
    }

    func testWrongKeySeesAnEmptyIndex() throws {
        try store.save(Entry(title: "Secret", body: "contents"))

        // Opening with the wrong key can't decrypt the index either, so the
        // rebuild finds nothing readable and the attacker sees an empty journal
        // rather than any metadata.
        let attacker = try EntryStore(paths: vault.paths, dataKey: SymmetricKey(size: .bits256))
        XCTAssertEqual(attacker.index.records.count, 0)
    }

    func testTamperedEntryFileIsRejected() throws {
        let entry = Entry(title: "Secret", body: "contents")
        try store.save(entry)

        let url = vault.paths.entryFile(id: entry.id)
        var bytes = try Data(contentsOf: url)
        bytes[bytes.count / 2] ^= 0xFF
        try bytes.write(to: url)

        assertThrows(try store.loadEntry(id: entry.id)) { error in
            XCTAssertEqual(error as? CryptoError, .authenticationFailed)
        }
    }

    func testEntryFileCannotBeSwappedForAnother() throws {
        let first = Entry(title: "Monday", body: "monday text")
        let second = Entry(title: "Tuesday", body: "tuesday text")
        try store.save(first)
        try store.save(second)

        // Rename one entry's ciphertext over the other's. The AAD binds each
        // box to its own UUID, so this must be detected rather than silently
        // showing Monday's words on Tuesday.
        let firstBox = try Data(contentsOf: vault.paths.entryFile(id: first.id))
        try firstBox.write(to: vault.paths.entryFile(id: second.id))

        assertThrows(try store.loadEntry(id: second.id)) { error in
            XCTAssertEqual(error as? CryptoError, .authenticationFailed)
        }
    }

    // MARK: - Updates and deletes

    func testSavingAgainUpdatesInPlace() throws {
        var entry = Entry(title: "Draft", body: "first")
        try store.save(entry)

        entry.body = "second"
        entry.title = "Final"
        try store.save(entry)

        let loaded = try store.loadEntry(id: entry.id)
        XCTAssertEqual(loaded.body, "second")
        XCTAssertEqual(loaded.title, "Final")
        XCTAssertEqual(store.index.records.count, 1, "Updating must not create a second record")
    }

    func testDeleteRemovesFileAndIndexRecord() throws {
        let entry = Entry(title: "Temporary", body: "text")
        try store.save(entry)

        try store.delete(id: entry.id)

        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.paths.entryFile(id: entry.id).path))
        XCTAssertNil(store.index[entry.id])
        assertThrows(try store.loadEntry(id: entry.id))
    }

    // MARK: - Index

    func testIndexPersistsAcrossStoreInstances() throws {
        let entry = Entry(title: "Remembered", body: "some words here", mood: .bright, tags: ["x"])
        try store.save(entry)

        let reopened = try EntryStore(paths: vault.paths, dataKey: key)
        let record = try XCTUnwrap(reopened.index[entry.id])

        XCTAssertEqual(record.title, "Remembered")
        XCTAssertEqual(record.mood, .bright)
        XCTAssertEqual(record.tags, ["x"])
        XCTAssertEqual(record.wordCount, 3)
    }

    func testIndexIsRebuiltWhenMissing() throws {
        let entry = Entry(title: "Survivor", body: "still here")
        try store.save(entry)

        try FileManager.default.removeItem(at: vault.paths.indexFile)

        let reopened = try EntryStore(paths: vault.paths, dataKey: key)
        XCTAssertEqual(reopened.index.records.count, 1)
        XCTAssertEqual(reopened.index[entry.id]?.title, "Survivor")
    }

    func testIndexIsRebuiltWhenCorrupt() throws {
        let entry = Entry(title: "Survivor", body: "still here")
        try store.save(entry)

        try Data("garbage that is not a sealed box".utf8).write(to: vault.paths.indexFile)

        let reopened = try EntryStore(paths: vault.paths, dataKey: key)
        XCTAssertEqual(reopened.index.records.count, 1, "A corrupt index must cost work, not entries")
    }

    func testRebuildSkipsUnreadableEntriesWithoutFailing() throws {
        let good = Entry(title: "Good", body: "fine")
        let bad = Entry(title: "Bad", body: "will be corrupted")
        try store.save(good)
        try store.save(bad)

        try Data("not a sealed box".utf8).write(to: vault.paths.entryFile(id: bad.id))
        try FileManager.default.removeItem(at: vault.paths.indexFile)

        let reopened = try EntryStore(paths: vault.paths, dataKey: key)
        XCTAssertEqual(reopened.index.records.count, 1)
        XCTAssertNotNil(reopened.index[good.id])
    }

    // MARK: - Index queries

    func testMultipleEntriesOnTheSameDay() throws {
        let day = Date()
        try store.save(Entry(day: day, title: "Morning", body: "a"))
        try store.save(Entry(day: day, title: "Evening", body: "b"))

        XCTAssertEqual(store.index.records(on: day).count, 2)
        XCTAssertEqual(store.index.daysWithEntries.count, 1)
    }

    func testDaysWithEntriesTracksDistinctDays() throws {
        let today = Date()
        let yesterday = today.addingTimeInterval(-86_400)
        try store.save(Entry(day: today, body: "a"))
        try store.save(Entry(day: yesterday, body: "b"))

        XCTAssertEqual(store.index.daysWithEntries.count, 2)
    }

    func testAllTagsDeduplicatesCaseInsensitively() throws {
        try store.save(Entry(body: "a", tags: ["Work", "calm"]))
        try store.save(Entry(body: "b", tags: ["work", "travel"]))

        let tags = store.index.allTags
        XCTAssertEqual(tags.count, 3)
        XCTAssertEqual(Set(tags.map { $0.lowercased() }), ["work", "calm", "travel"])
    }

    func testLoadAllEntriesReturnsEverythingInOrder() throws {
        let today = Date()
        try store.save(Entry(day: today, body: "today"))
        try store.save(Entry(day: today.addingTimeInterval(-86_400), body: "yesterday"))

        let all = try store.loadAllEntries()
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all.first?.body, "yesterday", "Oldest first")
    }

    // MARK: - Word count

    func testWordCount() {
        XCTAssertEqual(Entry(body: "").wordCount, 0)
        XCTAssertEqual(Entry(body: "one").wordCount, 1)
        XCTAssertEqual(Entry(body: "one two three").wordCount, 3)
        XCTAssertEqual(Entry(body: "line one\nline two").wordCount, 4)
        XCTAssertEqual(Entry(body: "  spaced   out  ").wordCount, 2)
    }

    // MARK: - Display title

    func testDisplayTitleFallsBackToFirstLine() {
        XCTAssertEqual(Entry(title: "Explicit", body: "# Heading").displayTitle, "Explicit")
        XCTAssertEqual(Entry(title: "", body: "# Heading\nmore").displayTitle, "Heading")
        XCTAssertEqual(Entry(title: "", body: "plain first line").displayTitle, "plain first line")
        XCTAssertEqual(Entry(title: "", body: "").displayTitle, "Untitled")
        XCTAssertEqual(Entry(title: "   ", body: "   ").displayTitle, "Untitled")
    }
}
