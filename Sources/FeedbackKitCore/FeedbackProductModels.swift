import Foundation

public enum FeedbackKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case bug
    case suggestion
    case praise
    case conversation
    /// A private response created by the campaign response API.
    case survey

    public var id: Self { self }

    /// Kinds accepted by the ordinary feedback submission API.
    public static let submittableCases: [Self] = [.bug, .suggestion, .praise, .conversation]

    public var isSubmittable: Bool { self != .survey }
}

public enum FeedbackStatus: String, Codable, Sendable {
    case open
    case resolved
    case closed
}

public enum FeedbackVisibility: String, Codable, Sendable {
    case `private`
    case `public`
}

public struct FeedbackAttachmentLimits: Codable, Equatable, Sendable {
    public let count: Int
    public let imageBytes: Int
    public let videoBytes: Int
}

public struct FeedbackDiagnosticsCapability: Codable, Equatable, Sendable {
    public let enabled: Bool
    public let maxBytes: Int
    public let schemaVersions: [Int]

    public var supportsSchemaOne: Bool { enabled && schemaVersions.contains(1) }
}

public struct FeedbackProduct: Codable, Equatable, Sendable {
    public let slug: String
    public let name: String
    public let defaultLocale: String
    public let defaultFeedbackVisibility: FeedbackVisibility
    public let iconUrl: URL?
    public let attachmentLimits: FeedbackAttachmentLimits
    public let diagnostics: FeedbackDiagnosticsCapability?
}
