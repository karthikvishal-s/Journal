import CryptoKit
import XCTest

@testable import Journal

final class CryptoTests: XCTestCase {

    private let context = "test.context.v1"

    // MARK: - Round trip

    func testSealAndOpenRoundTrip() throws {
        let key = SymmetricKey(size: .bits256)
        let plaintext = Data("A quiet Tuesday. Nothing much happened.".utf8)

        let box = try CryptoBox.seal(plaintext, key: key, context: context)
        let recovered = try CryptoBox.open(box, key: key, context: context)

        XCTAssertEqual(recovered, plaintext)
    }

    func testCiphertextDoesNotContainPlaintext() throws {
        let key = SymmetricKey(size: .bits256)
        let secret = "MySecretPassphraseAppearsHere"
        let box = try CryptoBox.seal(Data(secret.utf8), key: key, context: context)

        // The whole point of encryption at rest: the words must not be findable
        // in the bytes that hit the disk.
        XCTAssertNil(box.range(of: Data(secret.utf8)))
    }

    func testSealingSamePlaintextTwiceProducesDifferentCiphertext() throws {
        let key = SymmetricKey(size: .bits256)
        let plaintext = Data("same text".utf8)

        let first = try CryptoBox.seal(plaintext, key: key, context: context)
        let second = try CryptoBox.seal(plaintext, key: key, context: context)

        // Random nonce per seal — otherwise identical entries would be
        // recognisable as identical from the ciphertext alone.
        XCTAssertNotEqual(first, second)
    }

    // MARK: - Failure modes

    func testWrongKeyFails() throws {
        let key = SymmetricKey(size: .bits256)
        let wrongKey = SymmetricKey(size: .bits256)
        let box = try CryptoBox.seal(Data("secret".utf8), key: key, context: context)

        assertThrows(try CryptoBox.open(box, key: wrongKey, context: context)) { error in
            XCTAssertEqual(error as? CryptoError, .authenticationFailed)
        }
    }

    func testWrongContextFails() throws {
        let key = SymmetricKey(size: .bits256)
        let box = try CryptoBox.seal(Data("secret".utf8), key: key, context: "context.a")

        // This is what prevents a sealed box being moved between slots.
        assertThrows(try CryptoBox.open(box, key: key, context: "context.b")) { error in
            XCTAssertEqual(error as? CryptoError, .authenticationFailed)
        }
    }

    func testTamperedCiphertextFails() throws {
        let key = SymmetricKey(size: .bits256)
        var box = try CryptoBox.seal(Data("secret words here".utf8), key: key, context: context)

        // Flip one bit in the middle of the ciphertext.
        let target = box.count / 2
        box[target] ^= 0x01

        assertThrows(try CryptoBox.open(box, key: key, context: context)) { error in
            XCTAssertEqual(error as? CryptoError, .authenticationFailed)
        }
    }

    func testTruncatedBoxFails() throws {
        let key = SymmetricKey(size: .bits256)
        let box = try CryptoBox.seal(Data("secret".utf8), key: key, context: context)

        assertThrows(try CryptoBox.open(box.prefix(8), key: key, context: context))
    }

    // MARK: - Codable helpers

    func testCodableRoundTrip() throws {
        let key = SymmetricKey(size: .bits256)
        let entry = Entry(
            day: Date(),
            title: "Title",
            body: "Body text",
            mood: .good,
            tags: ["a", "b"]
        )

        let box = try CryptoBox.seal(entry, key: key, context: context)
        let recovered = try CryptoBox.open(box, as: Entry.self, key: key, context: context)

        XCTAssertEqual(recovered.id, entry.id)
        XCTAssertEqual(recovered.title, entry.title)
        XCTAssertEqual(recovered.body, entry.body)
        XCTAssertEqual(recovered.mood, entry.mood)
        XCTAssertEqual(recovered.tags, entry.tags)
    }

    // MARK: - Key derivation

    func testPasscodeDerivationIsDeterministic() throws {
        let salt = KeyDerivation.randomSalt()
        let a = try KeyDerivation.key(fromPasscode: "hunter2", salt: salt, rounds: 1_000)
        let b = try KeyDerivation.key(fromPasscode: "hunter2", salt: salt, rounds: 1_000)
        XCTAssertEqual(a, b)
    }

    func testDifferentSaltsProduceDifferentKeys() throws {
        let a = try KeyDerivation.key(fromPasscode: "hunter2", salt: KeyDerivation.randomSalt(), rounds: 1_000)
        let b = try KeyDerivation.key(fromPasscode: "hunter2", salt: KeyDerivation.randomSalt(), rounds: 1_000)
        XCTAssertNotEqual(a, b)
    }

    func testDifferentRoundCountsProduceDifferentKeys() throws {
        let salt = KeyDerivation.randomSalt()
        let a = try KeyDerivation.key(fromPasscode: "hunter2", salt: salt, rounds: 1_000)
        let b = try KeyDerivation.key(fromPasscode: "hunter2", salt: salt, rounds: 2_000)
        XCTAssertNotEqual(a, b)
    }

    func testSaltsAreUnique() {
        let salts = (0 ..< 50).map { _ in KeyDerivation.randomSalt() }
        XCTAssertEqual(Set(salts).count, 50)
        XCTAssertTrue(salts.allSatisfy { $0.count == KeyDerivation.saltByteCount })
    }
}
