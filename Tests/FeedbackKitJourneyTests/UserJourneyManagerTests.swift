import FeedbackKitCore
@testable import FeedbackKitJourney
import FeedbackKitTestSupport
import Foundation
import Testing

extension UserJourneySessionKind {
    fileprivate static let checkout = UserJourneySessionKind(rawValue: "checkout")
    fileprivate static let onboarding = UserJourneySessionKind(rawValue: "onboarding")
}

private final class FilteringSession: UserJourneySession, @unchecked Sendable {
    override func prepare(_ event: UserJourneyEvent) -> UserJourneyEvent? {
        guard event.name != "cart.polled" else { return nil }
        var payload = event.payload
        payload["source"] = .string(kind.rawValue)
        return event.replacing(payload: payload)
    }
}

private final class ClosingSession: UserJourneySession, @unchecked Sendable {
    override func sessionDidEnd(at date: Date) {
        append(UserJourneyEvent(target: .all, name: "checkout.closed", occurredAt: date))
    }
}

private actor StubCredentialStore: FeedbackVisitorCredentialProviding {
    func credential(for productKey: String) async throws -> String { "visitor-credential" }
    func deleteCredential(for productKey: String) async throws {}
}

private struct StubMetadataProvider: FeedbackAppMetadataProvider {
    func clientContext(locale: Locale) async -> FeedbackClientContext {
        FeedbackClientContext(
            appVersion: "2.4.0",
            buildNumber: "812",
            osVersion: "26.0",
            deviceCategory: "phone",
            locale: "en-US"
        )
    }
}

private func receiptJSON(clientSessionId: UUID, eventCount: Int = 0) -> Data {
    Data(
        #"{"code":"ok","message":"success","data":{"id":"9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d","clientSessionId":"\#(clientSessionId.uuidString.lowercased())","eventCount":\#(eventCount),"receivedAt":"2026-08-30T09:14:42.190Z"}}"#
            .utf8
    )
}

private func makeManager(
    withSessions sessions: [UserJourneySession] = [],
    handler: @escaping FeedbackFixtureTransport.Handler = { _ in (500, [:], Data()) }
) throws -> (manager: UserJourneyManager, transport: FeedbackFixtureTransport) {
    let transport = FeedbackFixtureTransport(handler: handler)
    let client = FeedbackClient(
        configuration: try FeedbackConfiguration(
            productKey: "pk_test",
            keychainService: "test.feedback.journey"
        ),
        transport: transport,
        credentialStore: StubCredentialStore(),
        metadataProvider: StubMetadataProvider()
    )
    let manager = UserJourneyManager(
        client: client,
        metadataProvider: StubMetadataProvider(),
        withSessions: sessions
    )
    return (manager, transport)
}

struct UserJourneyManagerTests {
    @Test func initRegistersTheProvidedSessions() async throws {
        let checkout = UserJourneySession(kind: .checkout)
        let onboarding = UserJourneySession(kind: .onboarding)
        let (manager, _) = try makeManager(withSessions: [checkout, onboarding])

        #expect(await manager.activeSessions.map(\.id) == [checkout.id, onboarding.id])
        #expect(await manager.pendingSessions.isEmpty)
    }

    @Test func initDropsDuplicateAndEndedSessions() async throws {
        let active = UserJourneySession(kind: .checkout)
        let ended = UserJourneySession(kind: .onboarding)
        ended.markEnded(at: .now)

        let (manager, _) = try makeManager(withSessions: [active, active, ended])

        #expect(await manager.activeSessions.map(\.id) == [active.id])
    }

    @Test func withDefaultSessionRegistersASingleDefaultKindSession() async throws {
        let transport = FeedbackFixtureTransport { _ in (500, [:], Data()) }
        let client = FeedbackClient(
            configuration: try FeedbackConfiguration(
                productKey: "pk_test",
                keychainService: "test.feedback.journey"
            ),
            transport: transport,
            credentialStore: StubCredentialStore()
        )
        let manager = UserJourneyManager.withDefaultSession(client: client)

        let sessions = await manager.activeSessions

        #expect(sessions.count == 1)
        #expect(sessions.first?.kind == .default)
    }

    @Test func registeredSessionsReceiveRecordedEvents() async throws {
        let (manager, _) = try makeManager()
        let session = UserJourneySession(kind: .checkout)

        await manager.register(session)
        let recorded = await manager.record(UserJourneyEvent(target: .all, name: "step"))

        #expect(recorded == true)
        #expect(await manager.activeSessions.map(\.id) == [session.id])
        #expect(session.events.map(\.name) == ["step"])
    }

    @Test func registerIsIdempotentAndRejectsEndedSessions() async throws {
        let (manager, _) = try makeManager()
        let session = UserJourneySession(kind: .checkout)

        #expect(await manager.register(session))
        #expect(await manager.register(session) == false)
        await manager.record(UserJourneyEvent(target: .all, name: "step"))
        #expect(session.events.map(\.name) == ["step"])

        #expect(await manager.unregister(session))
        #expect(await manager.register(session) == false)
        #expect(await manager.unregister(session) == false)
        #expect(await manager.pendingSessions.map(\.id) == [session.id])
    }

    @Test func recordDeliversToAllSessionsForTheAllTarget() async throws {
        let checkout = UserJourneySession(kind: .checkout)
        let fallback = UserJourneySession.default()
        let (manager, _) = try makeManager(withSessions: [checkout, fallback])

        await manager.record(UserJourneyEvent(target: .all, name: "app.launched"))

        #expect(checkout.events.map(\.name) == ["app.launched"])
        #expect(fallback.events.map(\.name) == ["app.launched"])
    }

    @Test func recordDeliversOnlyToSessionsWithMatchingKinds() async throws {
        let checkout = UserJourneySession(kind: .checkout)
        let onboarding = UserJourneySession(kind: .onboarding)
        let fallback = UserJourneySession.default()
        let (manager, _) = try makeManager(withSessions: [checkout, onboarding, fallback])

        await manager.record(
            UserJourneyEvent(target: .kinds([.checkout, .onboarding]), name: "profile.opened")
        )

        #expect(checkout.events.map(\.name) == ["profile.opened"])
        #expect(onboarding.events.map(\.name) == ["profile.opened"])
        #expect(fallback.events.isEmpty)
    }

    @Test func recordPreservesEventOrder() async throws {
        let session = UserJourneySession(kind: .checkout)
        let (manager, _) = try makeManager(withSessions: [session])

        await manager.record(UserJourneyEvent(target: .all, name: "first"))
        await manager.record(UserJourneyEvent(target: .kinds([.checkout]), name: "second"))
        await manager.record(UserJourneyEvent(target: .all, name: "third"))

        #expect(session.events.map(\.name) == ["first", "second", "third"])
    }

    @Test func recordRoutesThroughTheSessionsOwnOverrides() async throws {
        let filtered = FilteringSession(kind: .checkout)
        let plain = UserJourneySession(kind: .checkout)
        let (manager, _) = try makeManager(withSessions: [filtered, plain])

        await manager.record(UserJourneyEvent(target: .all, name: "cart.opened"))
        await manager.record(UserJourneyEvent(target: .all, name: "cart.polled"))

        #expect(filtered.events.map(\.name) == ["cart.opened"])
        #expect(filtered.events.first?.payload["source"] == .string("checkout"))
        #expect(plain.events.map(\.name) == ["cart.opened", "cart.polled"])
    }

    @Test func unregisterLetsTheSessionRecordAClosingEvent() async throws {
        let session = ClosingSession(kind: .checkout)
        let (manager, _) = try makeManager(withSessions: [session])

        await manager.record(UserJourneyEvent(target: .all, name: "cart.opened"))
        await manager.unregister(session)

        #expect(session.events.map(\.name) == ["cart.opened", "checkout.closed"])
        #expect(await manager.pendingSessions.map(\.id) == [session.id])
    }

    @Test func recordDropsEventsViolatingTheLimits() async throws {
        let session = UserJourneySession(kind: .checkout)
        let (manager, _) = try makeManager(withSessions: [session])

        let badName = await manager.record(UserJourneyEvent(target: .all, name: "Bad Name"))
        let oversizedString = await manager.record(
            UserJourneyEvent(
                target: .all,
                name: "big.event",
                payload: ["note": .string(String(repeating: "x", count: 501))]
            )
        )
        let tooDeep = await manager.record(
            UserJourneyEvent(
                target: .all,
                name: "deep.event",
                payload: [
                    "a": .dictionary([
                        "b": .dictionary(["c": .dictionary(["d": .dictionary(["e": .int(1)])])]),
                    ]),
                ]
            )
        )
        let valid = await manager.record(UserJourneyEvent(target: .all, name: "ok.event"))

        #expect(badName == false)
        #expect(oversizedString == false)
        #expect(tooDeep == false)
        #expect(valid == true)
        #expect(session.events.map(\.name) == ["ok.event"])
    }

    @Test func unregisterEndsTheSessionAndMovesItToPending() async throws {
        let session = UserJourneySession(kind: .checkout)
        let (manager, _) = try makeManager(withSessions: [session])
        let end = Date(timeIntervalSince1970: 5_000)

        await manager.record(UserJourneyEvent(target: .all, name: "before"))
        await manager.unregister(session, endedAt: end)
        await manager.record(UserJourneyEvent(target: .all, name: "after"))

        #expect(session.endedAt == end)
        #expect(session.events.map(\.name) == ["before"])
        #expect(await manager.activeSessions.isEmpty)
        #expect(await manager.pendingSessions.map(\.id) == [session.id])
    }

    @Test func unregisterLeavesOtherSessionsActive() async throws {
        let ending = UserJourneySession(kind: .checkout)
        let surviving = UserJourneySession(kind: .onboarding)
        let (manager, _) = try makeManager(withSessions: [ending, surviving])

        await manager.unregister(ending)
        await manager.record(UserJourneyEvent(target: .all, name: "step"))

        #expect(await manager.activeSessions.map(\.id) == [surviving.id])
        #expect(surviving.endedAt == nil)
        #expect(surviving.events.map(\.name) == ["step"])
        #expect(ending.events.isEmpty)
    }

    @Test func concurrentRecordingDeliversEveryEvent() async throws {
        let session = UserJourneySession(kind: .checkout)
        let (manager, _) = try makeManager(withSessions: [session])
        let eventCount = 100

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<eventCount {
                group.addTask {
                    await manager.record(UserJourneyEvent(target: .all, name: "event.\(index)"))
                }
            }
        }

        #expect(session.events.count == eventCount)
    }

    @Test func recordRoutesByTracedObjectAcrossSessions() async throws {
        let chat = UserJourneySession(kind: .checkout, objectID: "chat-1138")
        let otherChat = UserJourneySession(kind: .checkout, objectID: "chat-9999")
        let untraced = UserJourneySession(kind: .checkout)
        let (manager, _) = try makeManager(withSessions: [chat, otherChat, untraced])

        await manager.record(
            UserJourneyEvent(target: .objectID("chat-1138"), name: "message.sent")
        )
        await manager.record(
            UserJourneyEvent(
                target: .allOf(.kinds(.checkout), .objectID("chat-9999")),
                name: "cart.opened"
            )
        )

        #expect(chat.events.map(\.name) == ["message.sent"])
        #expect(otherChat.events.map(\.name) == ["cart.opened"])
        #expect(untraced.events.isEmpty)
    }

    @Test func submitRequiresAnEndedSession() async throws {
        let session = UserJourneySession(kind: .checkout)
        let (manager, transport) = try makeManager(withSessions: [session])

        await #expect(throws: UserJourneyError.sessionStillActive) {
            try await manager.submit(session)
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test func submitRejectsAnInvalidKind() async throws {
        let session = UserJourneySession(kind: UserJourneySessionKind(rawValue: "Bad Kind"))
        let (manager, transport) = try makeManager(withSessions: [session])
        await manager.unregister(session)

        await #expect(throws: UserJourneyError.invalidSessionKind) {
            try await manager.submit(session)
        }
        #expect(await transport.requests.isEmpty)
        #expect(await manager.pendingSessions.isEmpty)
        #expect(await manager.rejectedSessions.map(\.id) == [session.id])
    }

    @Test(arguments: [-1.0, UserJourneyLimits.maxSessionDuration + 1])
    func submitRejectsAndIsolatesInvalidSessionWindows(duration: TimeInterval) async throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let session = UserJourneySession(kind: .checkout, startedAt: start)
        let (manager, transport) = try makeManager(withSessions: [session])
        await manager.unregister(session, endedAt: start.addingTimeInterval(duration))

        await #expect(throws: UserJourneyError.invalidSessionWindow) {
            try await manager.submit(session)
        }

        #expect(await transport.requests.isEmpty)
        #expect(await manager.pendingSessions.isEmpty)
        #expect(await manager.rejectedSessions.map(\.id) == [session.id])
        #expect(await manager.discardRejected(session))
        #expect(await manager.rejectedSessions.isEmpty)
    }

    @Test func submitAcceptsTheMaximumSessionDuration() async throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let session = UserJourneySession(kind: .checkout, startedAt: start)
        let (manager, transport) = try makeManager(withSessions: [session]) { _ in
            (201, [:], receiptJSON(clientSessionId: session.id))
        }
        await manager.unregister(
            session,
            endedAt: start.addingTimeInterval(UserJourneyLimits.maxSessionDuration)
        )

        try await manager.submit(session)

        #expect(await transport.requests.count == 1)
        #expect(await manager.pendingSessions.isEmpty)
    }

    @Test func submitSendsTheWireFormatAndClearsPending() async throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let session = UserJourneySession(
            kind: .checkout,
            startedAt: start
        )
        let (manager, transport) = try makeManager(withSessions: [session]) { request in
            #expect(request.url?.absoluteString == "https://api.feedkit.cn/v1/api/client/journey/sessions")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "X-Product-Key") == "pk_test")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer visitor-credential")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

            #expect(
                String(decoding: request.httpBody ?? Data(), as: UTF8.self).contains("message-42")
                    == false
            )

            let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
            #expect(body?["schemaVersion"] as? Int == 1)
            let sessionJSON = body?["session"] as? [String: Any]
            #expect(sessionJSON?["id"] as? String == session.id.uuidString.lowercased())
            #expect(sessionJSON?["kind"] as? String == "checkout")
            #expect(sessionJSON?.keys.contains("objectHash") == false)
            #expect((sessionJSON?["startedAt"] as? String)?.contains(".") == true)
            let context = sessionJSON?["clientContext"] as? [String: Any]
            #expect(context?["appVersion"] as? String == "2.4.0")
            let events = sessionJSON?["events"] as? [[String: Any]]
            #expect(events?.count == 2)
            #expect(events?.first?["sequence"] as? Int == 0)
            #expect(events?.first?.keys.contains("objectHash") == false)
            #expect(events?.last?["objectHash"] as? String == "a0f23dc222845944b403379be712d8f49c0071bf94fa3cfbfe53dfa7bf0d154c")
            #expect(events?.first?["name"] as? String == "cart.opened")
            #expect((events?.first?["payload"] as? [String: Any])?["itemCount"] as? Int == 3)
            let nested = (events?.last?["payload"] as? [String: Any])?["tags"] as? [Any]
            #expect(nested?.first as? String == "new")
            #expect(events?.last?["sequence"] as? Int == 1)

            return (201, [:], receiptJSON(clientSessionId: session.id, eventCount: 2))
        }

        await manager.record(
            UserJourneyEvent(target: .all, name: "cart.opened", payload: ["itemCount": .int(3)])
        )
        await manager.record(
            UserJourneyEvent(
                target: .all,
                name: "payment.selected",
                objectID: "message-42",
                payload: ["tags": .array([.string("new")]), "done": .bool(false)]
            )
        )
        await manager.unregister(session, endedAt: start.addingTimeInterval(1))
        try await manager.submit(session)

        #expect(await transport.requests.count == 1)
        #expect(await manager.pendingSessions.isEmpty)
    }

    @Test func submitSendsOnlyTheDigestOfTheTracedObject() async throws {
        let session = UserJourneySession(kind: .checkout, objectID: "chat-1138")
        let (manager, transport) = try makeManager(withSessions: [session]) { request in
            let payload = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
            #expect(payload.contains("chat-1138") == false)

            let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
            let sessionJSON = body?["session"] as? [String: Any]
            #expect(sessionJSON?["objectHash"] as? String == "8043bb21e963228d16316cf69fbdfc095633085991d0917246166227800e5aa2")
            return (201, [:], receiptJSON(clientSessionId: session.id))
        }

        await manager.unregister(session)
        try await manager.submit(session)

        #expect(await transport.requests.count == 1)
    }

    @Test func replayedSubmissionCountsAsSuccess() async throws {
        let session = UserJourneySession(kind: .checkout)
        let (manager, _) = try makeManager(withSessions: [session]) { _ in
            (200, ["Idempotency-Replayed": "true"], receiptJSON(clientSessionId: session.id))
        }

        await manager.unregister(session)
        try await manager.submit(session)

        #expect(await manager.pendingSessions.isEmpty)
    }

    @Test func failedSubmissionStaysPendingForRetry() async throws {
        let session = UserJourneySession(kind: .checkout)
        let (manager, _) = try makeManager(withSessions: [session]) { _ in
            (500, [:], Data(#"{"code":"internal_error","message":"boom"}"#.utf8))
        }

        await manager.unregister(session)
        await #expect(throws: FeedbackClientError.self) {
            try await manager.submitAll()
        }

        #expect(await manager.pendingSessions.map(\.id) == [session.id])
        #expect(await manager.rejectedSessions.isEmpty)
    }

    @Test func submitAllIsolatesServerValidationFailuresAndContinues() async throws {
        let rejected = UserJourneySession(kind: .checkout)
        let accepted = UserJourneySession(kind: .onboarding)
        let (manager, transport) = try makeManager(withSessions: [rejected, accepted]) { request in
            let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
            let sessionJSON = body?["session"] as? [String: Any]
            let id = try #require(UUID(uuidString: sessionJSON?["id"] as? String ?? ""))
            if id == rejected.id {
                return (
                    422,
                    [:],
                    Data(#"{"code":"validation_failed","message":"invalid session"}"#.utf8)
                )
            }
            return (201, [:], receiptJSON(clientSessionId: id))
        }

        await manager.unregister(rejected)
        await manager.unregister(accepted)
        await #expect(throws: FeedbackClientError.self) {
            try await manager.submitAll()
        }

        #expect(await transport.requests.count == 2)
        #expect(await manager.pendingSessions.isEmpty)
        #expect(await manager.rejectedSessions.map(\.id) == [rejected.id])
    }

    @Test func submitAllIsolatesLocalValidationFailuresAndContinues() async throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let rejected = UserJourneySession(kind: .checkout, startedAt: start)
        let accepted = UserJourneySession(kind: .onboarding, startedAt: start)
        let (manager, transport) = try makeManager(withSessions: [rejected, accepted]) { _ in
            (201, [:], receiptJSON(clientSessionId: accepted.id))
        }

        await manager.unregister(
            rejected,
            endedAt: start.addingTimeInterval(UserJourneyLimits.maxSessionDuration + 1)
        )
        await manager.unregister(accepted, endedAt: start.addingTimeInterval(1))
        await #expect(throws: UserJourneyError.invalidSessionWindow) {
            try await manager.submitAll()
        }

        #expect(await transport.requests.count == 1)
        #expect(await manager.pendingSessions.isEmpty)
        #expect(await manager.rejectedSessions.map(\.id) == [rejected.id])
    }

    @Test func submitAllDrainsEveryPendingSession() async throws {
        let first = UserJourneySession(kind: .checkout)
        let second = UserJourneySession(kind: .onboarding)
        let (manager, transport) = try makeManager(withSessions: [first, second]) { request in
            let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
            let sessionJSON = body?["session"] as? [String: Any]
            let id = try #require(UUID(uuidString: sessionJSON?["id"] as? String ?? ""))
            return (201, [:], receiptJSON(clientSessionId: id))
        }

        await manager.unregister(first)
        await manager.unregister(second)
        try await manager.submitAll()

        #expect(await transport.requests.count == 2)
        #expect(await manager.pendingSessions.isEmpty)
        #expect(await manager.activeSessions.isEmpty)
    }
}
