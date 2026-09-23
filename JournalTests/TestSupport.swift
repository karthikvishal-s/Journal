import Foundation
import XCTest

@testable import Journal

/// A throwaway vault directory that cleans itself up.
final class TemporaryVault {
    let paths: VaultPaths

    /// Cheap KDF for tests. The app never uses this — see
    /// `KeyDerivation.defaultRounds` for the real cost.
    static let testRounds: UInt32 = 1_000

    init() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("JournalTests-\(UUID().uuidString)", isDirectory: true)
        paths = VaultPaths(root: root)
        try paths.createDirectoriesIfNeeded()
    }

    deinit {
        try? FileManager.default.removeItem(at: paths.root)
    }

    func manager() -> VaultManager { VaultManager(paths: paths) }
}

extension XCTestCase {
    /// Asserts that `expression` throws, and hands the error back for checking.
    func assertThrows<T>(
        _ expression: @autoclosure () throws -> T,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ check: (Error) -> Void = { _ in }
    ) {
        do {
            _ = try expression()
            XCTFail("Expected an error, but the call succeeded", file: file, line: line)
        } catch {
            check(error)
        }
    }
}
