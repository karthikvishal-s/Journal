import Foundation

/// Encrypted backup and restore.
///
/// The design here is deliberately boring: entries on disk are *already*
/// AES-GCM ciphertext, and `vault.json` already carries the data key wrapped
/// under both the passcode and the recovery key. So a backup is simply those
/// bytes collected into one envelope. Nothing is decrypted to make it, and
/// nothing new has to be encrypted.
///
/// That buys two things worth having. A backup opens with the same passcode or
/// recovery key as the journal itself — there is no separate backup password to
/// invent, forget, and lose the archive to. And no new cryptography was written
/// for this path, so it cannot have its own separate bugs.
enum BackupArchive {

    static let fileExtension = "journalbackup"
    static let currentVersion = 1

    struct Envelope: Codable {
        var version: Int
        var createdAt: Date
        var vault: Data                  // vault.json, verbatim
        var index: Data?                 // index.enc, verbatim
        var entries: [String: Data]      // uuid string -> sealed entry
        var entryCount: Int
    }

    /// Reads the vault directory and produces an archive. Requires an unlocked
    /// app only because the UI demands it — the bytes themselves are already
    /// encrypted and could be copied at any time.
    static func create(from paths: VaultPaths) throws -> Data {
        guard paths.vaultExists else { throw VaultError.noVault }

        let vaultData = try Data(contentsOf: paths.vaultFile)
        let indexData = try? Data(contentsOf: paths.indexFile)

        var entries: [String: Data] = [:]
        let files = (try? FileManager.default.contentsOfDirectory(
            at: paths.entriesDirectory,
            includingPropertiesForKeys: nil
        )) ?? []

        for file in files where file.pathExtension == "enc" {
            let name = file.deletingPathExtension().lastPathComponent
            guard UUID(uuidString: name) != nil else { continue }
            entries[name] = try Data(contentsOf: file)
        }

        let envelope = Envelope(
            version: currentVersion,
            createdAt: Date(),
            vault: vaultData,
            index: indexData,
            entries: entries,
            entryCount: entries.count
        )
        return try JSONCoding.encoder.encode(envelope)
    }

    /// Describes an archive without restoring it, so the user can be told what
    /// they're about to overwrite before anything is touched.
    static func inspect(_ data: Data) throws -> Envelope {
        let envelope = try JSONCoding.decoder.decode(Envelope.self, from: data)
        guard envelope.version <= currentVersion else {
            throw VaultError.unsupportedVersion(envelope.version)
        }
        return envelope
    }

    /// Replaces the contents of `paths` with the archive.
    ///
    /// Destructive by nature, so it is staged: everything is written to a
    /// temporary directory first and only swapped in once it has all landed. A
    /// failure halfway through therefore leaves the existing journal intact
    /// rather than half-replaced.
    static func restore(_ data: Data, to paths: VaultPaths) throws {
        let envelope = try inspect(data)

        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("JournalRestore-\(UUID().uuidString)", isDirectory: true)
        let stagingPaths = VaultPaths(root: staging)
        try stagingPaths.createDirectoriesIfNeeded()
        defer { try? FileManager.default.removeItem(at: staging) }

        try envelope.vault.write(to: stagingPaths.vaultFile)
        if let index = envelope.index {
            try index.write(to: stagingPaths.indexFile)
        }
        for (name, bytes) in envelope.entries {
            guard let id = UUID(uuidString: name) else { continue }
            try bytes.write(to: stagingPaths.entryFile(id: id))
        }

        // Staging succeeded; now swap.
        try paths.createDirectoriesIfNeeded()

        if FileManager.default.fileExists(atPath: paths.entriesDirectory.path) {
            try FileManager.default.removeItem(at: paths.entriesDirectory)
        }
        try FileManager.default.moveItem(at: stagingPaths.entriesDirectory, to: paths.entriesDirectory)

        _ = try FileManager.default.replaceItemAt(paths.vaultFile, withItemAt: stagingPaths.vaultFile)

        if FileManager.default.fileExists(atPath: stagingPaths.indexFile.path) {
            if FileManager.default.fileExists(atPath: paths.indexFile.path) {
                _ = try FileManager.default.replaceItemAt(paths.indexFile, withItemAt: stagingPaths.indexFile)
            } else {
                try FileManager.default.moveItem(at: stagingPaths.indexFile, to: paths.indexFile)
            }
        } else if FileManager.default.fileExists(atPath: paths.indexFile.path) {
            // Archive had no index; drop the stale one so it gets rebuilt.
            try FileManager.default.removeItem(at: paths.indexFile)
        }
    }

    static func suggestedFilename(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "Journal-\(formatter.string(from: date)).\(fileExtension)"
    }
}
