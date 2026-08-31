import Foundation

open class UserJourneySession: Identifiable, @unchecked Sendable {
    public let id: UUID
    public let kind: UserJourneySessionKind

    /// The object this session traces, hashed, or `nil` when it traces nothing.
    ///
    /// Tag the session when the whole journey belongs to one object; tag single
    /// events (``UserJourneyEvent/objectHash``) when only those steps do.
    public let objectHash: UserJourneyObjectHash?

    public let startedAt: Date

    private let lock = NSLock()
    private var _events: [UserJourneyEvent] = []
    private var _endedAt: Date?

    /// The events stored so far, in the order they were recorded.
    public var events: [UserJourneyEvent] { lock.withLock { _events } }

    /// When the session ended, or `nil` while it is still recording.
    public var endedAt: Date? { lock.withLock { _endedAt } }

    public required init(
        kind: UserJourneySessionKind,
        objectHash: UserJourneyObjectHash?,
        startedAt: Date = .now
    ) {
        self.id = UUID()
        self.kind = kind
        self.objectHash = objectHash
        self.startedAt = startedAt
    }

    /// Creates a session tracing `objectID`, hashing it on the way in.
    public convenience init(
        kind: UserJourneySessionKind,
        objectID: String? = nil,
        startedAt: Date = .now
    ) {
        self.init(
            kind: kind,
            objectHash: objectID.flatMap { UserJourneyObjectHash($0) },
            startedAt: startedAt
        )
    }

    /// Returns a new session of the receiving type with the sentinel default kind.
    public static func `default`(objectID: String? = nil) -> Self {
        Self(kind: .default, objectHash: objectID.flatMap { UserJourneyObjectHash($0) })
    }

    // MARK: - Extension points

    /// Whether an event aimed at `target` belongs in this session.
    ///
    /// The default asks the target (``UserJourneySessionTarget/matches(_:)``),
    /// which routes by kind, by traced object, by a combination of those, or by
    /// a predicate the caller supplied. Override to widen or narrow routing —
    /// for example to stop accepting events after a step is reached, or to
    /// mirror a related kind into this session.
    open func accepts(_ target: UserJourneySessionTarget) -> Bool {
        target.matches(self)
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
