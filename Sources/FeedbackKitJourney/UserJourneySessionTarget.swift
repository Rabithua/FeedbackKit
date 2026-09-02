import Foundation

/// Which sessions an event belongs to: every session, a set of kinds, a set of
/// traced objects, a predicate, or those combined with ``anyOf(_:)``/``allOf(_:)``
/// — for example `.allOf(.kinds(.checkout), .objectID("chat-1138"))`.
///
/// ``matching(_:)`` predicates run outside the session's lock, so they may read
/// ``UserJourneySession/events`` and ``UserJourneySession/endedAt``.
public struct UserJourneySessionTarget: Sendable {
    /// Internal: one case carries digests, and Swift has no per-case access
    /// control — hence a struct wrapping this rather than a public enum.
    enum Criterion: Sendable {
        case all
        case kinds(Set<UserJourneySessionKind>)
        case objects(Set<UserJourneyObjectHash>)
        case anyOf([UserJourneySessionTarget])
        case allOf([UserJourneySessionTarget])
        case matching(@Sendable (UserJourneySession) -> Bool)
    }

    let criterion: Criterion

    init(_ criterion: Criterion) {
        self.criterion = criterion
    }

    /// Every registered session.
    public static let all = UserJourneySessionTarget(.all)

    /// Sessions whose ``UserJourneySession/kind`` is in the set; none when empty.
    public static func kinds(_ kinds: Set<UserJourneySessionKind>) -> UserJourneySessionTarget {
        UserJourneySessionTarget(.kinds(kinds))
    }

    /// Sessions whose kind is one of `kinds`; none when it is empty.
    public static func kinds(_ kinds: UserJourneySessionKind...) -> UserJourneySessionTarget {
        .kinds(Set(kinds))
    }

    /// Sessions tracing `objectID`, hashed the way a session hashes it.
    ///
    /// A blank identifier targets no session at all, rather than every session.
    public static func objectID(_ objectID: String) -> UserJourneySessionTarget {
        .objectIDs([objectID])
    }

    /// Sessions tracing one of `objectIDs`; none when it is empty. Blank
    /// identifiers are ignored rather than widening the target.
    public static func objectIDs(_ objectIDs: [String]) -> UserJourneySessionTarget {
        UserJourneySessionTarget(.objects(Set(objectIDs.compactMap { UserJourneyObjectHash($0) })))
    }

    /// Sessions tracing one of `objectIDs`; none when it is empty.
    public static func objectIDs(_ objectIDs: String...) -> UserJourneySessionTarget {
        .objectIDs(objectIDs)
    }

    /// Sessions matching at least one of the targets; empty matches nothing.
    public static func anyOf(_ targets: [UserJourneySessionTarget]) -> UserJourneySessionTarget {
        UserJourneySessionTarget(.anyOf(targets))
    }

    /// Sessions matching at least one of the targets.
    public static func anyOf(_ targets: UserJourneySessionTarget...) -> UserJourneySessionTarget {
        .anyOf(targets)
    }

    /// Sessions matching every one of the targets; empty matches everything.
    public static func allOf(_ targets: [UserJourneySessionTarget]) -> UserJourneySessionTarget {
        UserJourneySessionTarget(.allOf(targets))
    }

    /// Sessions matching every one of the targets.
    public static func allOf(_ targets: UserJourneySessionTarget...) -> UserJourneySessionTarget {
        .allOf(targets)
    }

    /// Sessions the predicate accepts.
    public static func matching(
        _ predicate: @escaping @Sendable (UserJourneySession) -> Bool
    ) -> UserJourneySessionTarget {
        UserJourneySessionTarget(.matching(predicate))
    }

    /// Whether `session` is one of the sessions this target names. Internal:
    /// it compares digests. Outside, ask ``UserJourneySession/accepts(_:)``.
    func matches(_ session: UserJourneySession) -> Bool {
        switch criterion {
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
