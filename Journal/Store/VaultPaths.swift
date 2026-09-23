import Foundation

/// Where everything lives on disk.
///
/// Because the app is sandboxed, `.applicationSupportDirectory` resolves inside
/// the app's container rather than at the bare `~/Library/Application Support`.
/// The real path is:
///
///     ~/Library/Containers/com.karthikvishal.Journal/Data/
///         Library/Application Support/Journal/
///
/// That is a consequence of the sandbox, not a choice — and it is a good one:
/// the container is unreadable by other sandboxed apps. Settings has a "Reveal
/// in Finder" button because the path is not one anybody would type by hand.
struct VaultPaths {

    let root: URL

    /// `vault.json` — salts, KDF parameters and the wrapped keys. No plaintext
    /// secrets: useless without the passcode or the recovery key.
    var vaultFile: URL { root.appendingPathComponent("vault.json") }

    /// `index.enc` — encrypted metadata for every entry, so the calendar and
    /// browse views can draw without opening each entry. Rebuildable.
    var indexFile: URL { root.appendingPathComponent("index.enc") }

    /// One sealed box per entry, named by UUID. The directory listing therefore
    /// leaks nothing: not dates, not titles, not word counts.
    var entriesDirectory: URL { root.appendingPathComponent("entries", isDirectory: true) }

    func entryFile(id: UUID) -> URL {
        entriesDirectory.appendingPathComponent("\(id.uuidString).enc")
    }

    static let applicationDirectoryName = "Journal"

    static func standard() throws -> VaultPaths {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return VaultPaths(root: base.appendingPathComponent(applicationDirectoryName, isDirectory: true))
    }

    /// Used by the tests, which run against a throwaway directory.
    init(root: URL) {
        self.root = root
    }

    func createDirectoriesIfNeeded() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: entriesDirectory, withIntermediateDirectories: true)
    }

    var vaultExists: Bool {
        FileManager.default.fileExists(atPath: vaultFile.path)
    }
}
