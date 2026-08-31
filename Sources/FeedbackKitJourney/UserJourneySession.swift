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
    private var state: State = .active

    private enum State {
        case active
        case ending(at: Date, on: ObjectIdentifier)
        case ended(at: Date)
    }

    /// The events stored so far, in the order they were recorded.
    public var events: [UserJourneyEvent] { lock.withLock { _events } }

    /// When the session ended, or `nil` while it is still recording.
    public var endedAt: Date? {
        lock.withLock {
            switch state {
            case .active: nil
            case .ending(let date, _), .ended(let date): date
            }
        }
    }

    /// Whether the session can still be registered to receive events.
    internal var isActive: Bool {
        lock.withLock {
            guard case .active = state else { return false }
            return true
        }
    }

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
    /// ``UserJourneyLimits``, the session has ended, or the session is already holding
    /// ``UserJourneyLimits/maxEventsPerSession`` events.
    ///
    /// ``UserJourneyManager`` serializes its calls to this method; call it
    /// directly only from a context that is itself serialized.
    @discardableResult
    public func append(_ event: UserJourneyEvent) -> Bool {
        let currentThread = ObjectIdentifier(Thread.current)
        guard lock.withLock({ canAppend(from: currentThread) }),
              accepts(event.target),
              let prepared = prepare(event),
              UserJourneyEventValidation.isSubmittable(prepared)
        else { return false }
        return lock.withLock {
            guard canAppend(from: currentThread),
                  _events.count < UserJourneyLimits.maxEventsPerSession
            else { return false }
            _events.append(prepared)
            return true
        }
    }

    /// Ends the session, notifying ``sessionDidEnd(at:)`` on the first call only.
    internal func markEnded(at date: Date) {
        let currentThread = ObjectIdentifier(Thread.current)
        let didEnd = lock.withLock {
            guard case .active = state else { return false }
            state = .ending(at: date, on: currentThread)
            return true
        }
        guard didEnd else { return }
        sessionDidEnd(at: date)
        lock.withLock {
            guard case .ending(let endingDate, let thread) = state,
                  thread == currentThread
            else { return }
            state = .ended(at: endingDate)
        }
    }

    /// Consistent snapshot of the events and the end date, for submission.
    internal func snapshot() -> (events: [UserJourneyEvent], endedAt: Date?) {
        lock.withLock {
            let endedAt: Date?
            switch state {
            case .active: endedAt = nil
            case .ending(let date, _), .ended(let date): endedAt = date
            }
            return (_events, endedAt)
        }
    }

    /// Closing events are accepted only from the synchronous end hook.
    private func canAppend(from currentThread: ObjectIdentifier) -> Bool {
        switch state {
        case .active:
            true
        case .ending(_, let endingThread):
            endingThread == currentThread
        case .ended:
            false
        }
    }
}
