@testable import FeedbackKitJourney
import Foundation
import Testing

struct UserJourneyObjectHashTests {
    private static let chatDigest = "8043bb21e963228d16316cf69fbdfc095633085991d0917246166227800e5aa2"

    @Test func hashingAnIdentifierProducesLowercaseHexAndHidesTheIdentifier() throws {
        let hash = try #require(UserJourneyObjectHash("chat-1138"))

        #expect(hash.hexDigest == Self.chatDigest)
        #expect(hash.hexDigest.contains("chat-1138") == false)
        #expect(hash.description == Self.chatDigest)
    }

    @Test func blankIdentifiersProduceNoHash() {
        #expect(UserJourneyObjectHash("") == nil)
        #expect(UserJourneyObjectHash("  \n ") == nil)
    }

    @Test func adoptingADigestAcceptsOnlyHexOfTheRightWidth() throws {
        let adopted = try #require(UserJourneyObjectHash(hexDigest: Self.chatDigest.uppercased()))

        #expect(adopted == UserJourneyObjectHash("chat-1138"))
        #expect(UserJourneyObjectHash(hexDigest: "chat-1138") == nil)
        #expect(UserJourneyObjectHash(hexDigest: String(Self.chatDigest.dropLast())) == nil)
        #expect(UserJourneyObjectHash(hexDigest: String(repeating: "z", count: 64)) == nil)
        #expect(UserJourneyObjectHash(hexDigest: String(repeating: "０", count: 64)) == nil)
        #expect(UserJourneyObjectHash(hexDigest: String(repeating: "ａ", count: 64)) == nil)
    }

    @Test func codesAsItsBareDigest() throws {
        let hash = try #require(UserJourneyObjectHash("chat-1138"))

        let encoded = try JSONEncoder().encode(hash)
        #expect(String(decoding: encoded, as: UTF8.self) == "\"\(Self.chatDigest)\"")
        #expect(try JSONDecoder().decode(UserJourneyObjectHash.self, from: encoded) == hash)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(UserJourneyObjectHash.self, from: Data(#""chat-1138""#.utf8))
        }
    }
}
