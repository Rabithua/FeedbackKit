import Foundation
import FeedbackKitCore

public actor UserJourneyManager: Sendable {
    private let client: FeedbackClient
    private let metadataProvider: any FeedbackAppMetadataProvider
    private let lock = NSLock()
    private nonisolated(unsafe) var _sessions: [UserJourneySession]
    private nonisolated(unsafe) var _pendingSubmission: [UserJourneySession] = []

    // MARK: - Init

    public init(
        client: FeedbackClient,
        metadataProvider: any FeedbackAppMetadataProvider = DefaultFeedbackAppMetadataProvider(),
        withSessions sessions: [UserJourneySession] = []
    ) {
        self.client = client
        self.metadataProvider = metadataProvider
        self._sessions = sessions
    }

    /// Convenience factory: creates a manager pre-registered with a default session.
    public static func withDefaultSession(client: FeedbackClient) -> UserJourneyManager {
        UserJourneyManager(client: client, withSessions: [.default()])
    }

    // MARK: - Session management

    /// Snapshot of the sessions currently receiving events.
    internal var activeSessions: [UserJourneySession] {
        lock.withLock { _sessions }
    }

    /// Snapshot of the ended sessions waiting for submission.
    internal var pendingSessions: [UserJourneySession] {
        lock.withLock { _pendingSubmission }
    }

    public func register(_ session: UserJourneySession) {
        lock.withLock { _sessions.append(session) }
    }

    /// Ends the session and moves it to the pending-submission queue.
    public func unregister(_ session: UserJourneySession, endedAt: Date = .now) {
        lock.withLock {
            session.markEnded(at: endedAt)
            _sessions.removeAll { $0.id == session.id }
            if _pendingSubmission.contains(where: { $0.id == session.id }) == false {
                _pendingSubmission.append(session)
            }
        }
    }

    // MARK: - Event recording

    /// Fans the event into every matching active session.
    /// Returns `false` when the event violates ``UserJourneyLimits`` and was dropped.
    @discardableResult
    public func record(_ event: UserJourneyEvent) -> Bool {
        guard UserJourneyEventValidation.isSubmittable(event) else { return false }
        lock.withLock {
            for session in _sessions {
                guard session.events.count < UserJourneyLimits.maxEventsPerSession else { continue }
                switch event.target {
                case .all:
                    session.append(event)
                case .kinds(let kinds):
                    if kinds.contains(session.kind) {
                        session.append(event)
                    }
                }
            }
        }
        return true
    }

    // MARK: - Submit

    /// Submits one ended session to `POST /v1/api/client/journey/sessions`.
    /// Replays are safe: the server dedupes on the session's client-generated UUID.
    public func submit(_ session: UserJourneySession) async throws {
        let snapshot = lock.withLock { (events: session.events, endedAt: session.endedAt) }
        guard let endedAt = snapshot.endedAt else { throw UserJourneyError.sessionStillActive }
        let kind = session.kind.rawValue
        guard kind == UserJourneyTaxonomy.defaultKindKey
            || UserJourneyTaxonomy.isValidKey(kind, maxLength: UserJourneyLimits.maxKindLength)
        else { throw UserJourneyError.invalidSessionKind }
        guard snapshot.events.count <= UserJourneyLimits.maxEventsPerSession else {
            throw UserJourneyError.payloadTooLarge
        }

        let body = UserJourneySubmissionBody(
            session: session,
            endedAt: endedAt,
            events: snapshot.events,
            clientContext: await metadataProvider.clientContext(locale: .current)
        )
        _ = try await client.postClientJSON(
            UserJourneySubmissionReceipt.self,
            operation: .journeySubmit,
            path: "journey/sessions",
            body: body
        )
        lock.withLock { _pendingSubmission.removeAll { $0.id == session.id } }
    }

    /// Drains the pending queue in order; a failed session stays pending for retry.
    public func submitAll() async throws {
        let pending = lock.withLock { _pendingSubmission }
        for session in pending {
            try await submit(session)
        }
    }
}
