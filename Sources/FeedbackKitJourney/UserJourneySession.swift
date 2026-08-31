import CryptoKit
import Foundation

open class UserJourneySession: Identifiable, @unchecked Sendable {
    public let id: UUID
    public let kind: UserJourneySessionKind

    public let objectHash: String?

    public let startedAt: Date

    private let lock = NSLock()
    private var _events: [UserJourneyEvent] = []
    private var _endedAt: Date?

    /// The events stored so far, in the order they were recorded.
    public var events: [UserJourneyEvent] { lock.withLock { _events } }

    /// When the session ended, or `nil` while it is still recording.
    public var endedAt: Date? { lock.withLock { _endedAt } }

    /// Creates a session tracing `objectID`, which is hashed on the way in.
    public required init(
        kind: UserJourneySessionKind,
        objectID: String? = nil,
        startedAt: Date = .now
    ) {
        self.id = UUID()
        self.kind = kind
        self.objectHash = UserJourneySession.objectHash(for: objectID)
        self.startedAt = startedAt
    }

    /// Returns a new session of the receiving type with the sentinel default kind.
    public static func `default`(objectID: String? = nil) -> Self {
        Self(kind: .default, objectID: objectID)
    }

    /// The digest a session records for `objectID`, or `nil` when it is absent
    /// or blank.
    ///
    /// Hand this to the journey CSV export's `objectHash` filter to pull back
    /// every session recorded against that identifier; the raw value never has
    /// to leave the device.
    public static func objectHash(for objectID: String?) -> String? {
        guard let trimmed = objectID?.trimmingCharacters(in: .whitespacesAndNewlines),
              trimmed.isEmpty == false
        else { return nil }
        return SHA256.hash(data: Data(trimmed.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    // MARK: - Extension points

    /// Whether an event aimed at `target` belongs in this session.
    ///
    /// The default routes by ``kind``: `.all` matches every session, `.kinds`
    /// matches when the set contains this session's kind. Override to widen or
    /// narrow routing — for example to stop accepting events after a step is
    /// reached, or to mirror a related kind into this session.
    open func accepts(_ target: UserJourneySessionTarget) -> Bool {
        switch target {
        case .all:
            true
        case .kinds(let kinds):
            kinds.contains(kind)
        }
    }

    /// Preprocesses an accepted event immediately before it is stored.
    ///
    /// Return a replacement to rewrite the event, the event itself to store it
    /// unchanged, or `nil` to drop it. The default stores it unchanged.
    ///
    /// A replacement is re-validated against ``UserJourneyLimits``; one that
    /// breaks those bounds is dropped rather than failing the whole session at
    /// submit time.
    open func prepare(_ event: UserJourneyEvent) -> UserJourneyEvent? {
        event
    }

    /// Called once, right after the session has been marked ended.
    ///
    /// Override to append a closing event via ``append(_:)``, flush derived
    /// state, or tear down observers. The default does nothing.
    open func sessionDidEnd(at date: Date) {}

    // MARK: - Recording

    /// Routes `event` through ``accepts(_:)`` and ``prepare(_:)`` and stores the result.
    ///
    /// Returns `false` when the session ignored the event: it was not accepted,
    /// ``prepare(_:)`` dropped it, the prepared event violates
    /// ``UserJourneyLimits``, or the session is already holding
    /// ``UserJourneyLimits/maxEventsPerSession`` events.
    ///
    /// ``UserJourneyManager`` serializes its calls to this method; call it
    /// directly only from a context that is itself serialized.
    @discardableResult
    public func append(_ event: UserJourneyEvent) -> Bool {
        guard accepts(event.target),
              let prepared = prepare(event),
              UserJourneyEventValidation.isSubmittable(prepared)
        else { return false }
        return lock.withLock {
            guard _events.count < UserJourneyLimits.maxEventsPerSession else { return false }
            _events.append(prepared)
            return true
        }
    }

    /// Ends the session, notifying ``sessionDidEnd(at:)`` on the first call only.
    internal func markEnded(at date: Date) {
        let didEnd = lock.withLock {
            guard _endedAt == nil else { return false }
            _endedAt = date
            return true
        }
        guard didEnd else { return }
        sessionDidEnd(at: date)
    }

    /// Consistent snapshot of the events and the end date, for submission.
    internal func snapshot() -> (events: [UserJourneyEvent], endedAt: Date?) {
        lock.withLock { (_events, _endedAt) }
    }
}
