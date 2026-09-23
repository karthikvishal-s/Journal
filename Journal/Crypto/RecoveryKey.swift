import Foundation
import Security

/// The one-time recovery key shown during setup.
///
/// 160 bits of system randomness, rendered in Crockford Base32 as eight groups
/// of four:
///
///     H8K2-M4PQ-RT9W-XYZ3-BCDF-6GHJ-K1LM-NPQ7
///
/// 160 bits is chosen so the encoding divides exactly: 160 / 5 = 32 characters,
/// no padding and no truncation, so what the user writes down is *precisely*
/// the secret and the round trip through paper is lossless. (An earlier draft
/// printed a prefix of a 256-bit secret; the leftover bits made `parse` unable
/// to reconstruct the original, which would have meant a recovery key that
/// looked fine and never worked.) The 160 bits are stretched to a 256-bit key
/// by HKDF in `KeyDerivation`.
///
/// Crockford's alphabet omits I, L, O and U, which kills the usual
/// transcription mistakes. `parse` also folds the lookalikes back, so a
/// hand-copied `I` still reads as `1`, and case, spaces and dashes are ignored
/// — the user is reading this off a piece of paper, possibly months later, and
/// the parser should meet them where they are.
enum RecoveryKey {

    static let secretByteCount = 20          // 160 bits
    private static let groupSize = 4
    private static let groupCount = 8        // 32 characters total
    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    private static var characterCount: Int { groupSize * groupCount }

    /// A freshly generated key: the raw secret plus the string the user writes down.
    struct Generated {
        let secret: Data
        let formatted: String
    }

    static func generate() -> Generated {
        var bytes = [UInt8](repeating: 0, count: secretByteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "System RNG unavailable")
        let secret = Data(bytes)
        return Generated(secret: secret, formatted: format(secret))
    }

    static func format(_ secret: Data) -> String {
        let chars = base32Characters(from: secret)
        let groups = stride(from: 0, to: chars.count, by: groupSize).map {
            String(chars[$0 ..< min($0 + groupSize, chars.count)])
        }
        return groups.joined(separator: "-")
    }

    /// Accepts what the user types; returns the secret, or nil if the key is the
    /// wrong length or contains characters outside the alphabet.
    static func parse(_ input: String) -> Data? {
        let normalised = normalise(input)
        guard normalised.count == characterCount else { return nil }

        var bits: [UInt8] = []
        bits.reserveCapacity(normalised.count * 5)

        for character in normalised {
            guard let value = alphabet.firstIndex(of: character) else { return nil }
            for shift in stride(from: 4, through: 0, by: -1) {
                bits.append(UInt8((value >> shift) & 1))
            }
        }

        // 160 bits divides evenly into 20 bytes, so nothing is discarded here.
        var bytes: [UInt8] = []
        bytes.reserveCapacity(secretByteCount)
        for chunk in stride(from: 0, to: bits.count, by: 8) {
            var byte: UInt8 = 0
            for offset in 0 ..< 8 {
                byte = (byte << 1) | bits[chunk + offset]
            }
            bytes.append(byte)
        }
        return Data(bytes)
    }

    /// True if `input` is the right shape to be a recovery key. Lets the unlock
    /// screen route the input without making the user declare which kind of
    /// secret they're entering.
    static func looksLikeRecoveryKey(_ input: String) -> Bool {
        normalise(input).count == characterCount
    }

    // MARK: - Internals

    /// Uppercases, drops anything that isn't alphanumeric, and folds the
    /// characters Crockford treats as aliases.
    private static func normalise(_ input: String) -> String {
        String(input.uppercased().compactMap { character -> Character? in
            switch character {
            case "I", "L": return "1"
            case "O":      return "0"
            case "U":      return "V"
            default:       return character.isLetter || character.isNumber ? character : nil
            }
        })
    }

    private static func base32Characters(from data: Data) -> [Character] {
        var bits: [UInt8] = []
        bits.reserveCapacity(data.count * 8)
        for byte in data {
            for shift in stride(from: 7, through: 0, by: -1) {
                bits.append((byte >> UInt8(shift)) & 1)
            }
        }

        var characters: [Character] = []
        characters.reserveCapacity(bits.count / 5)
        for index in stride(from: 0, to: bits.count, by: 5) {
            var value = 0
            for offset in 0 ..< 5 {
                value = (value << 1) | Int(bits[index + offset])
            }
            characters.append(alphabet[value])
        }
        return characters
    }
}
