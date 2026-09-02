import CryptoKit
import Foundation

/// The digest of an identifier a journey traces — a chat id, order number,
/// document id — standing in for the identifier itself.
///
/// Internal, as is every comparison over it: code outside the framework names
/// objects by its own identifiers, which are hashed here on the way in. The
/// raw value never leaves the device, and the server hashes the digest again
/// before storing it.
struct UserJourneyObjectHash: Hashable, Sendable, CustomStringConvertible {
    /// Lowercase SHA-256 hex, 64 characters.
    let hexDigest: String

    /// Hashes `objectID`, or fails when it is blank once trimmed.
    init?(_ objectID: String) {
        let trimmed = objectID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        hexDigest = SHA256.hash(data: Data(trimmed.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// Adopts a digest computed earlier, or fails when it is not 64-char hex.
    init?(hexDigest: String) {
        let normalized = hexDigest.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.utf8.count == 64,
              normalized.utf8.allSatisfy({ byte in
                  (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
                      || (UInt8(ascii: "a")...UInt8(ascii: "f")).contains(byte)
              })
        else { return nil }
        self.hexDigest = normalized
    }

    var description: String { hexDigest }
}

extension UserJourneyObjectHash: Codable {
    init(from decoder: any Decoder) throws {
        let hexDigest = try decoder.singleValueContainer().decode(String.self)
        guard let decoded = UserJourneyObjectHash(hexDigest: hexDigest) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected a lowercase SHA-256 hex digest"
                )
            )
        }
        self = decoded
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hexDigest)
    }
}
