import CryptoKit
import XCTest

@testable import Journal

final class BackupAndExportTests: XCTestCase {

    private var vault: TemporaryVault!
    private var manager: VaultManager!
    private let rounds = TemporaryVault.testRounds

    override func setUpWithError() throws {
        vault = try TemporaryVault()
        manager = vault.manager()
    }

    override func tearDown() {
        manager = nil
        vault = nil
    }

    // MARK: - Backup

    func testBackupRestoreRoundTrip() throws {
        let setup = try manager.createVault(passcode: "pass", rounds: rounds)
        let first = Entry(title: "Monday", body: "the first day", mood: .good, tags: ["a"])
        let second = Entry(day: Date().addingTimeInterval(-86_400), title: "Sunday", body: "the day before")
        try setup.store.save(first)
        try setup.store.save(second)

        let archive = try BackupArchive.create(from: vault.paths)

        // Wipe the journal entirely, as if this were a new Mac.
        try FileManager.default.removeItem(at: vault.paths.root)
        XCTAssertFalse(manager.vaultExists)

        try BackupArchive.restore(archive, to: vault.paths)

        // Same passcode opens it, and the entries came back intact.
        let reopened = try manager.unlock(passcode: "pass")
        XCTAssertEqual(reopened.dataKey, setup.dataKey)
        XCTAssertEqual(reopened.store.index.records.count, 2)
        XCTAssertEqual(try reopened.store.loadEntry(id: first.id).body, "the first day")
        XCTAssertEqual(try reopened.store.loadEntry(id: first.id).mood, .good)
        XCTAssertEqual(try reopened.store.loadEntry(id: second.id).body, "the day before")
    }

    func testBackupIsEncryptedAtRest() throws {
        let setup = try manager.createVault(passcode: "pass", rounds: rounds)
        let secret = "something I would not want read"
        try setup.store.save(Entry(title: "Private", body: secret))

        let archive = try BackupArchive.create(from: vault.paths)

        // The archive is a container of ciphertext, so the words must not be
        // in it — including base64-encoded, which is how JSON carries Data.
        XCTAssertNil(archive.range(of: Data(secret.utf8)))
        XCTAssertNil(archive.range(of: Data(Data(secret.utf8).base64EncodedString().utf8)))
    }

    func testRestoredBackupOpensWithItsOwnRecoveryKey() throws {
        let setup = try manager.createVault(passcode: "pass", rounds: rounds)
        try setup.store.save(Entry(title: "Kept", body: "text"))
        let archive = try BackupArchive.create(from: vault.paths)

        try FileManager.default.removeItem(at: vault.paths.root)
        try BackupArchive.restore(archive, to: vault.paths)

        XCTAssertNoThrow(try manager.unlock(recoveryKeyInput: setup.recoveryKey))
    }

    func testRestoreReplacesExistingEntries() throws {
        let setup = try manager.createVault(passcode: "pass", rounds: rounds)
        let original = Entry(title: "Original", body: "in the backup")
        try setup.store.save(original)
        let archive = try BackupArchive.create(from: vault.paths)

        // Write something after the backup was taken.
        let later = Entry(title: "Later", body: "added after the backup")
        try setup.store.save(later)
        XCTAssertEqual(setup.store.index.records.count, 2)

        try BackupArchive.restore(archive, to: vault.paths)

        let reopened = try manager.unlock(passcode: "pass")
        XCTAssertEqual(reopened.store.index.records.count, 1)
        XCTAssertNotNil(reopened.store.index[original.id])
        XCTAssertNil(reopened.store.index[later.id], "Entries after the backup should be gone")
    }

    func testInspectRejectsNonBackupFile() {
        assertThrows(try BackupArchive.inspect(Data("just some bytes".utf8)))
    }

    func testFailedRestoreLeavesJournalIntact() throws {
        let setup = try manager.createVault(passcode: "pass", rounds: rounds)
        try setup.store.save(Entry(title: "Safe", body: "must survive"))

        assertThrows(try BackupArchive.restore(Data("garbage".utf8), to: vault.paths))

        // The original journal is untouched.
        let reopened = try manager.unlock(passcode: "pass")
        XCTAssertEqual(reopened.store.index.records.count, 1)
    }

    // MARK: - Export

    func testMarkdownExportWritesReadableFiles() throws {
        let setup = try manager.createVault(passcode: "pass", rounds: rounds)
        let entry = Entry(title: "A Title", body: "Body **text** here", mood: .bright, tags: ["one", "two"])
        try setup.store.save(entry)

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: destination) }

        let count = try Exporter.exportMarkdown(entries: [entry], to: destination)
        XCTAssertEqual(count, 1)

        let files = try FileManager.default.contentsOfDirectory(atPath: destination.path)
        XCTAssertEqual(files.count, 1)

        let text = try String(contentsOf: destination.appendingPathComponent(files[0]), encoding: .utf8)
        // An export is supposed to be readable — that's the point of it.
        XCTAssertTrue(text.contains("Body **text** here"))
        XCTAssertTrue(text.contains("title: A Title"))
        XCTAssertTrue(text.contains("mood: bright"))
        XCTAssertTrue(text.contains("tags: [one, two]"))
    }

    func testExportDisambiguatesEntriesSharingADay() throws {
        let day = Date()
        let entries = [
            Entry(day: day, title: "Same", body: "first"),
            Entry(day: day, title: "Same", body: "second"),
        ]

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: destination) }

        try Exporter.exportMarkdown(entries: entries, to: destination)

        // Two entries, two files — neither may overwrite the other.
        let files = try FileManager.default.contentsOfDirectory(atPath: destination.path)
        XCTAssertEqual(files.count, 2)
    }

    func testExportRangeFiltering() throws {
        let today = Date()
        let lastWeek = today.addingTimeInterval(-7 * 86_400)
        let entries = [Entry(day: lastWeek, body: "old"), Entry(day: today, body: "new")]

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: destination) }

        let range = Exporter.Range(start: today.addingTimeInterval(-86_400), end: today)
        let count = try Exporter.exportMarkdown(entries: entries, range: range, to: destination)

        XCTAssertEqual(count, 1)
    }

    func testPDFExportProducesAValidFile() throws {
        let entries = (0 ..< 40).map {
            Entry(
                day: Date().addingTimeInterval(TimeInterval(-$0 * 86_400)),
                title: "Entry \($0)",
                body: String(repeating: "Some words to fill the page. ", count: 20)
            )
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("journal-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }

        try Exporter.exportPDF(entries: entries, to: url)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let data = try Data(contentsOf: url)
        XCTAssertTrue(data.starts(with: Data("%PDF".utf8)), "Should be a real PDF")

        // Enough content to have paginated rather than truncating at page one.
        let document = try XCTUnwrap(PDFDocumentProbe(url: url))
        XCTAssertGreaterThan(document.pageCount, 1)
    }
}

/// Minimal PDF page counter, to avoid pulling in PDFKit just for a test.
private struct PDFDocumentProbe {
    let pageCount: Int

    init?(url: URL) {
        guard let document = CGPDFDocument(url as CFURL) else { return nil }
        pageCount = document.numberOfPages
    }
}
