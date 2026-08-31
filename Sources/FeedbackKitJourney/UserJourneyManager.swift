import Foundation
import FeedbackKitCore

public actor UserJourneyManager: Sendable {
    private let client: FeedbackClient
    private let metadataProvider: any FeedbackAppMetadataProvider
    private var sessions: [UserJourneySession]
    private var pendingSubmission: [UserJourneySession] = []
    private var rejectedSubmission: [UserJourneySession] = []

    // MARK: - Init

    public init(
        client: FeedbackClient,
        metadataProvider: any FeedbackAppMetadataProvider = DefaultFeedbackAppMetadataProvider(),
        withSessions sessions: [UserJourneySession] = []
    ) {
        self.client = client
        self.metadataProvider = metadataProvider

        var seen = Set<UUID>()
        self.sessions = sessions.filter { session in
            session.isActive && seen.insert(session.id).inserted
        }
    }

    /// Convenience factory: creates a manager pre-registered with a default session.
    public static func withDefaultSession(client: FeedbackClient) -> UserJourneyManager {
        UserJourneyManager(client: client, withSessions: [.default()])
    }

    // MARK: - Session management

    /// Snapshot of the sessions currently receiving events.
    internal var activeSessions: [UserJourneySession] { sessions }

    /// Snapshot of the ended sessions waiting for submission.
    internal var pendingSessions: [UserJourneySession] { pendingSubmission }

    /// Sessions isolated after a permanent local or server-side validation failure.
    ///
    /// They no longer block ``submitAll()``. The submit call that isolated one
    /// still throws its original error so the application can report the loss.
    public var rejectedSessions: [UserJourneySession] { rejectedSubmission }

    /// Registers an active session once. Returns `false` for duplicate or ended sessions.
    @discardableResult
    public func register(_ session: UserJourneySession) -> Bool {
        guard session.isActive,
              sessions.contains(where: { $0.id == session.id }) == false
        else { return false }
        sessions.append(session)
        return true
    }

    /// Ends a registered session and moves it to the pending-submission queue.
    @discardableResult
    public func unregister(_ session: UserJourneySession, endedAt: Date = .now) -> Bool {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else {
            return false
        }
        sessions.remove(at: index)

        // The session may run subclass code while ending. This is synchronous,
        // so the closing event is included before the pending snapshot is exposed.
        session.markEnded(at: endedAt)
        if pendingSubmission.contains(where: { $0.id == session.id }) == false {
            pendingSubmission.append(session)
        }
        return true
    }

    /// Removes a permanently rejected session after the application has inspected it.
    @discardableResult
    public func discardRejected(_ session: UserJourneySession) -> Bool {
        let originalCount = rejectedSubmission.count
        rejectedSubmission.removeAll { $0.id == session.id }
        return rejectedSubmission.count != originalCount
    }

    // MARK: - Event recording

    /// Offers the event to every active session; each one decides whether it
    /// belongs and how to store it (see ``UserJourneySession/append(_:)``).
    /// Returns `false` when the event violates ``UserJourneyLimits`` and was dropped.
    @discardableResult
    public func record(_ event: UserJourneyEvent) -> Bool {
        guard UserJourneyEventValidation.isSubmittable(event) else { return false }
        for session in sessions {
            session.append(event)
        }
        return true
    }

    // MARK: - Submit

    /// Submits one ended session to `POST /v1/api/client/journey/sessions`.
    /// Replays are safe: the server dedupes on the session's client-generated UUID.
    /// Permanent validation failures are moved out of the pending queue.
    public func submit(_ session: UserJourneySession) async throws {
        let snapshot = session.snapshot()

        let endedAt: Date
        do {
            endedAt = try validate(session: session, snapshot: snapshot)
        } catch {
            if Self.isPermanentSubmissionError(error) {
                isolate(session)
            }
            throw error
        }

        let body = UserJourneySubmissionBody(
            session: session,
            endedAt: endedAt,
            events: snapshot.events,
            clientContext: await metadataProvider.clientContext(locale: .current)
        )

        do {
            _ = try await client.postClientJSON(
                UserJourneySubmissionReceipt.self,
                operation: .journeySubmit,
                path: "journey/sessions",
                body: body
            )
        } catch {
            if Self.isPermanentSubmissionError(error) {
                isolate(session)
            }
            throw error
        }

        pendingSubmission.removeAll { $0.id == session.id }
        rejectedSubmission.removeAll { $0.id == session.id }
    }

    /// Drains the pending queue in order.
    ///
    /// Permanent validation failures are isolated and draining continues; the
    /// first such error is thrown after later valid sessions have been sent.
    /// Transient failures stop immediately and remain pending for retry.
    public func submitAll() async throws {
        let pending = pendingSubmission
        var firstPermanentError: (any Error)?

        for session in pending {
            do {
                try await submit(session)
            } catch {
                guard Self.isPermanentSubmissionError(error) else { throw error }
                if firstPermanentError == nil {
                    firstPermanentError = error
                }
            }
        }

        if let firstPermanentError {
            throw firstPermanentError
        }
    }

    private func validate(
        session: UserJourneySession,
        snapshot: (events: [UserJourneyEvent], endedAt: Date?)
    ) throws -> Date {
        guard let endedAt = snapshot.endedAt else {
            throw UserJourneyError.sessionStillActive
        }
        let duration = endedAt.timeIntervalSince(session.startedAt)
        guard duration >= 0, duration <= UserJourneyLimits.maxSessionDuration else {
            throw UserJourneyError.invalidSessionWindow
        }
        let kind = session.kind.rawValue
        guard kind == UserJourneyTaxonomy.defaultKindKey
            || UserJourneyTaxonomy.isValidKey(kind, maxLength: UserJourneyLimits.maxKindLength)
        else { throw UserJourneyError.invalidSessionKind }
        guard snapshot.events.count <= UserJourneyLimits.maxEventsPerSession else {
            throw UserJourneyError.payloadTooLarge
        }
        return endedAt
    }

    private func isolate(_ session: UserJourneySession) {
        pendingSubmission.removeAll { $0.id == session.id }
        if rejectedSubmission.contains(where: { $0.id == session.id }) == false {
            rejectedSubmission.append(session)
        }
    }

    private static func isPermanentSubmissionError(_ error: any Error) -> Bool {
        if let journeyError = error as? UserJourneyError {
            switch journeyError {
            case .invalidSessionKind, .invalidSessionWindow, .payloadTooLarge:
                return true
            case .sessionStillActive:
                return false
            }
        }
        if let clientError = error as? FeedbackClientError {
            return clientError.kind == .validation || clientError.kind == .payloadTooLarge
        }
        return false
    }
}
