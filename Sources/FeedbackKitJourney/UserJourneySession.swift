import Foundation

open class UserJourneySession: Identifiable, @unchecked Sendable {
    public let id: UUID
    public let kind: UserJourneySessionKind

    /// The object this session traces, hashed, or `nil` when it traces nothing.
    let objectHash: UserJourneyObjectHash?

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

    /// Creates a session, optionally tracing `objectID`, hashed on the way in.
    public init(
        kind: UserJourneySessionKind,
        objectID: String? = nil,
        startedAt: Date = .now
    ) {
        self.id = UUID()
        self.kind = kind
        self.objectHash = objectID.flatMap { UserJourneyObjectHash($0) }
        self.startedAt = startedAt
    }

    /// Returns a new session with the sentinel default kind.
    public static func `default`(objectID: String? = nil) -> UserJourneySession {
        UserJourneySession(kind: .default, objectID: objectID)
    }

    // MARK: - Extension points

    /// Whether an event aimed at `target` belongs in this session.
    /// Override to widen or narrow routing; call `super` to keep the default.
    open func accepts(_ target: UserJourneySessionTarget) -> Bool {
        target.matches(self)
    }

    /// Preprocesses an accepted event before it is stored. Return a replacement
    /// (see ``UserJourneyEvent/replacing(name:payload:)``) or `nil` to drop it.
    open func prepare(_ event: UserJourneyEvent) -> UserJourneyEvent? {
        event
    }

    /// Called once, right after the session has been marked ended.
    open func sessionDidEnd(at date: Date) {}

    // MARK: - Recording

    /// Routes `event` through ``accepts(_:)`` and ``prepare(_:)`` and stores it.
    /// Returns `false` when the session ignored it, it broke
    /// ``UserJourneyLimits``, or the session is full.
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
