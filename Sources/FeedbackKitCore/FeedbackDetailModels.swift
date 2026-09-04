import Foundation

public struct FeedbackAttachment: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let filename: String
    public let contentType: String
    public let sizeBytes: Int
    public let width: Int?
    public let height: Int?
    public let durationMs: Int?

    public var isVideo: Bool { contentType.hasPrefix("video/") }
}

public struct FeedbackMessage: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let actor: String?
    public let body: String
    public let createdAt: Date
}

public struct OwnedFeedbackSummary: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    /// The exact server-side record kind, including campaign responses.
    public let recordKind: FeedbackRecordKind
    /// Compatibility projection for integrations built around ordinary feedback kinds.
    public var type: FeedbackKind { recordKind.feedbackKind ?? .conversation }
    public let title: String?
    public let displayTitle: String
    public let body: String
    public let status: FeedbackStatus
    public let visibility: FeedbackVisibility
    public let publishedAt: Date?
    public let pinnedAt: Date?
    public let lastActivityAt: Date
    public let createdAt: Date
    public let updatedAt: Date
    public let diagnosticsIncluded: Bool?

    private enum CodingKeys: String, CodingKey {
        case id
        case recordKind = "type"
        case title
        case displayTitle
        case body
        case status
        case visibility
        case publishedAt
        case pinnedAt
        case lastActivityAt
        case createdAt
        case updatedAt
        case diagnosticsIncluded
    }
}

public struct OwnedFeedbackPage: Codable, Sendable {
    public let feedback: [OwnedFeedbackSummary]
    public let nextCursor: String?
}

public struct FeedbackDetail: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    /// The exact server-side record kind, including campaign responses.
    public let recordKind: FeedbackRecordKind
    /// Compatibility projection for integrations built around ordinary feedback kinds.
    public var type: FeedbackKind { recordKind.feedbackKind ?? .conversation }
    public let title: String?
    public let displayTitle: String
    public let body: String
    public let status: FeedbackStatus
    public let visibility: FeedbackVisibility?
    public let publishedAt: Date?
    public let pinnedAt: Date?
    public let lastActivityAt: Date?
    public let createdAt: Date
    public let updatedAt: Date?
    public let authorDisplayCode: String
    public let isOwner: Bool
    public var voteCount: Int
    public var hasVoted: Bool
    public let messages: [FeedbackMessage]
    public let attachments: [FeedbackAttachment]
    public let diagnosticsIncluded: Bool?

    public var isPublic: Bool {
        visibility == .public || (isOwner == false && publishedAt != nil)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case recordKind = "type"
        case title
        case displayTitle
        case body
        case status
        case visibility
        case publishedAt
        case pinnedAt
        case lastActivityAt
        case createdAt
        case updatedAt
        case authorDisplayCode
        case isOwner
        case voteCount
        case hasVoted
        case messages
        case attachments
        case diagnosticsIncluded
    }
}
