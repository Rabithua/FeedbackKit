import Foundation

public struct UserJourneyEvent: Sendable {
    public let target: UserJourneySessionTarget

    public typealias Payload = [String: UserJourneyPayloadValue]

    /// Rewritten only by ``replacing(name:payload:)``.
    public private(set) var name: String

    /// The object this step traces, hashed, or `nil` when it traces nothing
    /// narrower than its session does.
    let objectHash: UserJourneyObjectHash?

    public private(set) var payload: Payload

    public let occurredAt: Date

    /// Creates an event, optionally tracing `objectID`, hashed on the way in.
    public init(
        target: UserJourneySessionTarget,
        name: String,
        objectID: String? = nil,
        payload: Payload = [:],
        occurredAt: Date = .now
    ) {
        self.target = target
        self.name = name
        self.objectHash = objectID.flatMap { UserJourneyObjectHash($0) }
        self.payload = payload
        self.occurredAt = occurredAt
    }

    /// Returns a copy with a new name, payload, or both. The copy starts as the
    /// whole event, so a rewrite keeps what it did not mention — including the
    /// traced object, which the caller cannot see or restate.
    public func replacing(
        name: String? = nil,
        payload: Payload? = nil
    ) -> UserJourneyEvent {
        var copy = self
        if let name { copy.name = name }
        if let payload { copy.payload = payload }
        return copy
    }
}
