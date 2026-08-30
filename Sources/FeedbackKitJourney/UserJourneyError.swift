import Foundation

public enum UserJourneyError: Error, Sendable {
    /// The session has not ended yet; end it (``UserJourneyManager/unregister(_:endedAt:)``) before submitting.
    case sessionStillActive
    /// The session kind is not a valid lowercase taxonomy key.
    case invalidSessionKind
    case payloadTooLarge
}
