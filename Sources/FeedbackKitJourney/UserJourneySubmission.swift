import FeedbackKitCore
import Foundation

public struct UserJourneySubmissionReceipt: Decodable, Equatable, Sendable {
    public let id: UUID
    public let clientSessionId: UUID
    public let eventCount: Int
    public let receivedAt: Date
}

struct UserJourneySubmissionBody: Encodable {
    struct Session: Encodable {
        let id: String
        let kind: String
        /// Omitted from the payload when the session traces no object.
        let objectHash: UserJourneyObjectHash?
        let startedAt: String
        let endedAt: String
        let clientContext: FeedbackClientContext
        let events: [Event]
    }

    struct Event: Encodable {
        let sequence: Int
        let name: String
        /// Omitted from the payload when the event traces no object of its own.
        let objectHash: UserJourneyObjectHash?
        let occurredAt: String
        let payload: [String: UserJourneyPayloadValue]
    }

    let schemaVersion: Int
    let session: Session

    init(
        session: UserJourneySession,
        endedAt: Date,
        events: [UserJourneyEvent],
        clientContext: FeedbackClientContext
    ) {
        schemaVersion = 1
        self.session = Session(
            id: session.id.uuidString.lowercased(),
            kind: session.kind.rawValue,
            objectHash: session.objectHash,
            startedAt: Self.timestamp(session.startedAt),
            endedAt: Self.timestamp(endedAt),
            clientContext: clientContext,
            events: events.enumerated().map { index, event in
                Event(
                    sequence: index,
                    name: event.name,
                    objectHash: event.objectHash,
                    occurredAt: Self.timestamp(event.occurredAt),
                    payload: event.payload
                )
            }
        )
    }

    /// ISO-8601 with fractional seconds; millisecond order matters for analytics.
    static func timestamp(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }
}
