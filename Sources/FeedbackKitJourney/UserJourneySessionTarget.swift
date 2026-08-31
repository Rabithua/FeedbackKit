import Foundation

/// Which sessions an event belongs to.
///
/// The simple cases name a criterion — every session, a set of kinds, a set of
/// traced objects — and ``anyOf(_:)``/``allOf(_:)`` combine them, so an event
/// can be aimed at, say, the checkout sessions that trace one chat:
///
/// ```swift
/// manager.record(
///     UserJourneyEvent(
///         target: .allOf(.kinds(.checkout), .objectID("chat-1138")),
///         name: "payment.selected"
///     )
/// )
/// ```
///
/// When a criterion cannot be spelled out ahead of time, ``matching(_:)``
/// carries a predicate over the session itself. It runs outside the session's
/// lock, so it may read ``UserJourneySession/events`` and
/// ``UserJourneySession/endedAt`` as well as the immutable fields.
public enum UserJourneySessionTarget: Sendable {
    /// Every registered session.
    case all
    /// Sessions whose ``UserJourneySession/kind`` is in the set.
    case kinds(Set<UserJourneySessionKind>)
    /// Sessions whose ``UserJourneySession/objectHash`` is in the set.
    case objects(Set<UserJourneyObjectHash>)
    /// Sessions matching at least one of the targets; empty matches nothing.
    case anyOf([UserJourneySessionTarget])
    /// Sessions matching every one of the targets; empty matches everything.
    case allOf([UserJourneySessionTarget])

    /// Sessions whose kind is one of `kinds`; none when it is empty.
    public static func kinds(_ kinds: UserJourneySessionKind...) -> UserJourneySessionTarget {
        .kinds(Set(kinds))
    }

    /// Sessions tracing one of `objectHashes`; none when it is empty.
    public static func objects(
        _ objectHashes: UserJourneyObjectHash...
    ) -> UserJourneySessionTarget {
        .objects(Set(objectHashes))
    }

    /// Sessions matching at least one of the targets.
    public static func anyOf(_ targets: UserJourneySessionTarget...) -> UserJourneySessionTarget {
        .anyOf(targets)
    }

    /// Sessions matching every one of the targets.
    public static func allOf(_ targets: UserJourneySessionTarget...) -> UserJourneySessionTarget {
        .allOf(targets)
    }
    /// Sessions the predicate accepts.
    case matching(@Sendable (UserJourneySession) -> Bool)

    /// Sessions tracing `objectID`, hashed the way a session hashes it.
    ///
    /// A blank identifier targets no session at all, rather than every session.
    public static func objectID(_ objectID: String) -> UserJourneySessionTarget {
        .objects(UserJourneyObjectHash(objectID).map { [$0] } ?? [])
    }

    /// Sessions tracing `objectHash`.
    public static func object(_ objectHash: UserJourneyObjectHash) -> UserJourneySessionTarget {
        .objects([objectHash])
    }

    /// Whether `session` is one of the sessions this target names.
    public func matches(_ session: UserJourneySession) -> Bool {
        switch self {
        case .all:
            true
        case .kinds(let kinds):
            kinds.contains(session.kind)
        case .objects(let objects):
            session.objectHash.map(objects.contains) ?? false
        case .anyOf(let targets):
            targets.contains { $0.matches(session) }
        case .allOf(let targets):
            targets.allSatisfy { $0.matches(session) }
        case .matching(let predicate):
            predicate(session)
        }
    }
}
