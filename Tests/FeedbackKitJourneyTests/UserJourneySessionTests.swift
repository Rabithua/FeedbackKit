@testable import FeedbackKitJourney
import Foundation
import Testing

extension UserJourneySessionKind {
    fileprivate static let checkout = UserJourneySessionKind(rawValue: "checkout")
}

struct UserJourneySessionTests {
    @Test func initStoresKindAndStartDateAndBeginsEmpty() {
        let start = Date(timeIntervalSince1970: 1_000)

        let session = UserJourneySession(kind: .checkout, startedAt: start)

        #expect(session.kind == .checkout)
        #expect(session.startedAt == start)
        #expect(session.endedAt == nil)
        #expect(session.events.isEmpty)
    }

    @Test func sessionsWithTheSameKindHaveDistinctIdentifiers() {
        let first = UserJourneySession(kind: .checkout)
        let second = UserJourneySession(kind: .checkout)

        #expect(first.id != second.id)
    }

    @Test func defaultFactoryReturnsFreshSessionsWithTheSentinelKind() {
        let first = UserJourneySession.default()
        let second = UserJourneySession.default()

        #expect(first.kind == .default)
        #expect(second.kind == .default)
        #expect(first.id != second.id)
    }

    @Test func appendStoresEventsInOrder() {
        let session = UserJourneySession(kind: .checkout)

        session.append(UserJourneyEvent(target: .all, name: "first"))
        session.append(UserJourneyEvent(target: .all, name: "second"))

        #expect(session.events.map(\.name) == ["first", "second"])
    }

    @Test func markEndedSetsTheEndDate() {
        let session = UserJourneySession(kind: .checkout)
        let end = Date(timeIntervalSince1970: 2_000)

        session.markEnded(at: end)

        #expect(session.endedAt == end)
    }
}

struct UserJourneySessionKindTests {
    @Test func defaultKindUsesTheReservedRawValue() {
        #expect(UserJourneySessionKind.default.rawValue == "__default__")
    }

    @Test func kindsWithTheSameRawValueAreInterchangeable() {
        #expect(UserJourneySessionKind(rawValue: "checkout") == .checkout)

        let kinds: Set<UserJourneySessionKind> = [
            UserJourneySessionKind(rawValue: "checkout"),
            .checkout,
            UserJourneySessionKind(rawValue: "onboarding"),
        ]
        #expect(kinds.count == 2)
    }

    @Test func kindEncodesAsItsBareRawValue() throws {
        let encoded = try JSONEncoder().encode(UserJourneySessionKind.checkout)

        #expect(String(decoding: encoded, as: UTF8.self) == "\"checkout\"")

        let decoded = try JSONDecoder().decode(UserJourneySessionKind.self, from: encoded)
        #expect(decoded == .checkout)
    }
}
