import Foundation

public final class UserJourneySession: Identifiable, Sendable {
    public let id: UUID
    public let kind: UserJourneySessionKind
    public let startedAt: Date

    /// Mutated only while holding ``UserJourneyManager``'s lock.
    public nonisolated(unsafe) private(set) var endedAt: Date?

    /// Mutated only while holding ``UserJourneyManager``'s lock.
    nonisolated(unsafe) var events: [UserJourneyEvent] = []

    public init(kind: UserJourneySessionKind, startedAt: Date = .now) {
        self.id = UUID()
        self.kind = kind
        self.startedAt = startedAt
    }

    /// Returns a new default session (null-UUID sentinel kind).
    public static func `default`() -> UserJourneySession {
        UserJourneySession(kind: .default)
    }

    internal func append(_ event: UserJourneyEvent) {
        events.append(event)
    }

    internal func markEnded(at date: Date) {
        endedAt = date
    }
}
