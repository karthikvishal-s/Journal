import CryptoKit
import Foundation

/// AES-GCM sealing and opening. Every byte this app writes to disk goes through
/// here — there is no other write path.
///
/// The on-disk representation is CryptoKit's "combined" form:
///
///     [ 12-byte nonce | ciphertext | 16-byte tag ]
///
/// Callers pass `context`, which becomes additionally-authenticated data. It is
/// not encrypted, but the tag covers it, so a sealed box cannot be moved to a
/// different slot and still open. That is what stops an attacker with write
/// access to the data folder from swapping one day's entry file for another's,
/// or replaying an old wrapped key into the recovery slot.
enum CryptoBox {

    static func seal(_ plaintext: Data, key: SymmetricKey, context: String) throws -> Data {
        let sealed = try AES.GCM.seal(
            plaintext,
            using: key,
            authenticating: Data(context.utf8)
        )
        guard let combined = sealed.combined else {
            // Only nil for non-default nonce sizes, which we never use.
            throw CryptoError.sealFailed
        }
        return combined
    }

    static func open(_ box: Data, key: SymmetricKey, context: String) throws -> Data {
        let sealed: AES.GCM.SealedBox
        do {
            sealed = try AES.GCM.SealedBox(combined: box)
        } catch {
            throw CryptoError.malformedBox
        }

        do {
            return try AES.GCM.open(sealed, using: key, authenticating: Data(context.utf8))
        } catch {
            // CryptoKit does not distinguish "wrong key" from "tampered data",
            // and neither should we — both mean the same thing to the caller.
            throw CryptoError.authenticationFailed
        }
    }

    // MARK: - Codable convenience

    static func seal<T: Encodable>(_ value: T, key: SymmetricKey, context: String) throws -> Data {
        try seal(try JSONCoding.encoder.encode(value), key: key, context: context)
    }

    static func open<T: Decodable>(
        _ box: Data,
        as type: T.Type,
        key: SymmetricKey,
        context: String
    ) throws -> T {
        let plaintext = try open(box, key: key, context: context)
        do {
            return try JSONCoding.decoder.decode(type, from: plaintext)
        } catch {
            throw CryptoError.corruptPayload
        }
    }
}

enum CryptoError: LocalizedError, Equatable {
    case sealFailed
    case malformedBox
    case authenticationFailed
    case corruptPayload

    var errorDescription: String? {
        switch self {
        case .sealFailed:
            return "Could not encrypt the data."
        case .malformedBox:
            return "This file isn't in the expected format."
        case .authenticationFailed:
            return "Could not decrypt: wrong key, or the file has been altered."
        case .corruptPayload:
            return "The data decrypted, but its contents are damaged."
        }
    }
}

/// Shared JSON configuration. Dates go out as ISO-8601 so a decrypted export or
/// a backup written by one version stays readable by the next.
enum JSONCoding {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
