@testable import FeedbackKitJourney
import Foundation
import Testing

extension UserJourneySessionKind {
    fileprivate static let checkout = UserJourneySessionKind(rawValue: "checkout")
    fileprivate static let onboarding = UserJourneySessionKind(rawValue: "onboarding")
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

    @Test func appendReportsWhetherTheEventWasStored() {
        let session = UserJourneySession(kind: .checkout)

        #expect(session.append(UserJourneyEvent(target: .all, name: "stored")) == true)
        #expect(session.append(UserJourneyEvent(target: .kinds([.onboarding]), name: "other")) == false)
        #expect(session.events.map(\.name) == ["stored"])
    }

    @Test func appendStopsAtTheEventCap() {
        let session = UserJourneySession(kind: .checkout)

        for index in 0..<UserJourneyLimits.maxEventsPerSession {
            #expect(session.append(UserJourneyEvent(target: .all, name: "event.\(index)")) == true)
        }

        #expect(session.append(UserJourneyEvent(target: .all, name: "overflow")) == false)
        #expect(session.events.count == UserJourneyLimits.maxEventsPerSession)
    }
}

// MARK: - Subclassing

/// Exercises every extension point: narrowed routing, event rewriting and
/// dropping, and a closing event written from the end hook.
private final class CheckoutSession: UserJourneySession, @unchecked Sendable {
    private let counterLock = NSLock()
    private nonisolated(unsafe) var _endCount = 0

    var endCount: Int { counterLock.withLock { _endCount } }

    override func accepts(_ target: UserJourneySessionTarget) -> Bool {
        guard case .all = target else { return super.accepts(target) }
        return false
    }

    override func prepare(_ event: UserJourneyEvent) -> UserJourneyEvent? {
        guard event.name != "cart.polled" else { return nil }
        var payload = event.payload
        payload["step"] = .int(events.count)
        return UserJourneyEvent(
            target: event.target,
            name: event.name,
            payload: payload,
            occurredAt: event.occurredAt
        )
    }

    override func sessionDidEnd(at date: Date) {
        counterLock.withLock { _endCount += 1 }
        append(UserJourneyEvent(target: .kinds([kind]), name: "checkout.closed", occurredAt: date))
    }
}

private final class OversizingSession: UserJourneySession, @unchecked Sendable {
    override func prepare(_ event: UserJourneyEvent) -> UserJourneyEvent? {
        UserJourneyEvent(
            target: event.target,
            name: event.name,
            payload: ["note": .string(String(repeating: "x", count: UserJourneyLimits.maxStringLength + 1))],
            occurredAt: event.occurredAt
        )
    }
}

struct UserJourneySessionSubclassTests {
    @Test func acceptsCanNarrowRouting() {
        let session = CheckoutSession(kind: .checkout)

        session.append(UserJourneyEvent(target: .all, name: "app.launched"))
        session.append(UserJourneyEvent(target: .kinds([.checkout]), name: "cart.opened"))

        #expect(session.events.map(\.name) == ["cart.opened"])
    }

    @Test func prepareRewritesAndDropsEvents() {
        let session = CheckoutSession(kind: .checkout)

        session.append(UserJourneyEvent(target: .kinds([.checkout]), name: "cart.opened"))
        session.append(UserJourneyEvent(target: .kinds([.checkout]), name: "cart.polled"))
        session.append(
            UserJourneyEvent(
                target: .kinds([.checkout]),
                name: "payment.selected",
                payload: ["method": .string("card")]
            )
        )

        #expect(session.events.map(\.name) == ["cart.opened", "payment.selected"])
        #expect(session.events.map(\.payload["step"]) == [.int(0), .int(1)])
        #expect(session.events.last?.payload["method"] == .string("card"))
    }

    @Test func preparedEventsAreRevalidatedAgainstTheLimits() {
        let session = OversizingSession(kind: .checkout)

        #expect(session.append(UserJourneyEvent(target: .all, name: "cart.opened")) == false)
        #expect(session.events.isEmpty)
    }

    @Test func sessionDidEndRunsOnceAndCanRecordAClosingEvent() {
        let session = CheckoutSession(kind: .checkout)
        let end = Date(timeIntervalSince1970: 2_000)

        session.markEnded(at: end)
        session.markEnded(at: Date(timeIntervalSince1970: 3_000))

        #expect(session.endCount == 1)
        #expect(session.endedAt == end)
        #expect(session.events.map(\.name) == ["checkout.closed"])
    }

    @Test func defaultFactoryPreservesTheSubclassType() {
        let session = CheckoutSession.default()

        #expect(session.kind == .default)
        #expect(type(of: session) == CheckoutSession.self)
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
