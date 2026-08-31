import Foundation

public struct UserJourneyEvent: Sendable {
    public let target: UserJourneySessionTarget
    public let name: String

    /// The object this one step traces, hashed, or `nil` when it traces nothing
    /// narrower than its session does.
    public let objectHash: UserJourneyObjectHash?

    public let payload: [String: UserJourneyPayloadValue]
    public let occurredAt: Date

    public init(
        target: UserJourneySessionTarget,
        name: String,
        objectHash: UserJourneyObjectHash?,
        payload: [String: UserJourneyPayloadValue] = [:],
        occurredAt: Date = .now
    ) {
        self.target = target
        self.name = name
        self.objectHash = objectHash
        self.payload = payload
        self.occurredAt = occurredAt
    }

    /// Creates an event tracing `objectID`, hashing it on the way in.
    public init(
        target: UserJourneySessionTarget,
        name: String,
        objectID: String? = nil,
        payload: [String: UserJourneyPayloadValue] = [:],
        occurredAt: Date = .now
    ) {
        self.init(
            target: target,
            name: name,
            objectHash: objectID.flatMap { UserJourneyObjectHash($0) },
            payload: payload,
            occurredAt: occurredAt
        )
    }
}
