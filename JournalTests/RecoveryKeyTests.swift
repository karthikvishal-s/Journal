import XCTest

@testable import Journal

final class RecoveryKeyTests: XCTestCase {

    /// The regression test for the bug that would have shipped a recovery key
    /// that looked perfectly valid and never worked: if the printed characters
    /// don't carry the whole secret, `parse` cannot reconstruct it.
    func testGeneratedKeyRoundTripsThroughItsPrintedForm() {
        for _ in 0 ..< 200 {
            let generated = RecoveryKey.generate()
            XCTAssertEqual(
                RecoveryKey.parse(generated.formatted),
                generated.secret,
                "Printed key \(generated.formatted) did not parse back to its secret"
            )
        }
    }

    func testFormattedShape() {
        let formatted = RecoveryKey.generate().formatted
        let groups = formatted.split(separator: "-")

        XCTAssertEqual(groups.count, 8)
        XCTAssertTrue(groups.allSatisfy { $0.count == 4 })
        XCTAssertEqual(formatted.count, 8 * 4 + 7)
    }

    func testKeysAreUnique() {
        let keys = (0 ..< 200).map { _ in RecoveryKey.generate().formatted }
        XCTAssertEqual(Set(keys).count, 200)
    }

    func testSecretIs160Bits() {
        XCTAssertEqual(RecoveryKey.generate().secret.count, 20)
    }

    // MARK: - Forgiving input

    func testParsingIgnoresCaseSpacesAndDashes() {
        let generated = RecoveryKey.generate()
        let mangled = generated.formatted
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")

        XCTAssertEqual(RecoveryKey.parse(mangled), generated.secret)
    }

    func testParsingWithNoSeparatorsAtAll() {
        let generated = RecoveryKey.generate()
        let runTogether = generated.formatted.replacingOccurrences(of: "-", with: "")
        XCTAssertEqual(RecoveryKey.parse(runTogether), generated.secret)
    }

    func testParsingFoldsCrockfordLookalikes() {
        // Someone copying by hand writes I for 1 and O for 0. Crockford says
        // those are the same character, and so do we.
        let canonical = "H8K2-M4PQ-RT9W-XYZ3-BCDF-6GHJ-K1MN-PQ70"
        let handCopied = "H8K2-M4PQ-RT9W-XYZ3-BCDF-6GHJ-KIMN-PQ7O"

        XCTAssertNotNil(RecoveryKey.parse(canonical))
        XCTAssertEqual(RecoveryKey.parse(handCopied), RecoveryKey.parse(canonical))
    }

    // MARK: - Rejection

    func testRejectsWrongLength() {
        XCTAssertNil(RecoveryKey.parse("TOO-SHORT"))
        XCTAssertNil(RecoveryKey.parse(""))
        XCTAssertNil(RecoveryKey.parse(RecoveryKey.generate().formatted + "-EXTR"))
    }

    func testLooksLikeRecoveryKeyDistinguishesFromPasscode() {
        XCTAssertTrue(RecoveryKey.looksLikeRecoveryKey(RecoveryKey.generate().formatted))
        XCTAssertFalse(RecoveryKey.looksLikeRecoveryKey("my passcode"))
        XCTAssertFalse(RecoveryKey.looksLikeRecoveryKey("1234"))
    }
}
