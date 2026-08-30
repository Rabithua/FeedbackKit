import Foundation

public enum UserJourneySessionTarget: Sendable {
    case kinds(Set<UserJourneySessionKind>)
    case all
}

public struct UserJourneyEvent: Sendable {
    public let target: UserJourneySessionTarget
    public let name: String
    public let payload: [String: UserJourneyPayloadValue]
    public let occurredAt: Date

    public init(
        target: UserJourneySessionTarget,
        name: String,
        payload: [String: UserJourneyPayloadValue] = [:],
        occurredAt: Date = .now
    ) {
        self.target = target
        self.name = name
        self.payload = payload
        self.occurredAt = occurredAt
    }
}
