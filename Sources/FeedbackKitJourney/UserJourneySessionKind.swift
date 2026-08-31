import Foundation

public struct UserJourneySessionKind: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

extension UserJourneySessionKind {
    /// Framework-reserved sentinel kind. Server-side corresponds to null UUID.
    public static let `default` = UserJourneySessionKind(rawValue: "__default__")
}
