import Foundation

public enum FeedbackKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case bug
    case suggestion
    case praise
    case conversation

    public var id: Self { self }

    /// Kinds accepted by the ordinary feedback submission API.
    public static let submittableCases: [Self] = allCases

    public var isSubmittable: Bool { true }
}

/// The extensible server-side kind of a feedback record.
public struct FeedbackRecordKind: RawRepresentable, Codable, Hashable, Identifiable, Sendable {
    public static let bug = Self(rawValue: "bug")
    public static let suggestion = Self(rawValue: "suggestion")
    public static let praise = Self(rawValue: "praise")
    public static let conversation = Self(rawValue: "conversation")
    /// A private response created by the campaign response API.
    public static let survey = Self(rawValue: "survey")

    public let rawValue: String
    public var id: String { rawValue }

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ feedbackKind: FeedbackKind) {
        rawValue = feedbackKind.rawValue
    }

    /// The matching ordinary submission kind, or `nil` for campaign and future record kinds.
    public var feedbackKind: FeedbackKind? {
        FeedbackKind(rawValue: rawValue)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
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
