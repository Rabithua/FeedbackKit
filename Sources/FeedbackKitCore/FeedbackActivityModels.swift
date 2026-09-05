import Foundation

public struct FeedbackDeveloperPostAction: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case externalURL = "external_url"
        case appRoute = "app_route"
        case campaign
    }

    public let type: Kind
    public let target: String
    public let label: String?

    /// The Campaign identifier for a Campaign action; nil for URL and app-route actions.
    public var campaignID: String? { type == .campaign ? target : nil }

    public init(type: Kind, target: String, label: String? = nil) {
        self.type = type
        self.target = target
        self.label = label
    }

    public init(campaignID: String, label: String? = nil) {
        type = .campaign
        target = campaignID
        self.label = label
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case target
        case campaignID = "campaignId"
        case label
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(Kind.self, forKey: .type)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        switch type {
        case .externalURL, .appRoute:
            target = try container.decode(String.self, forKey: .target)
        case .campaign:
            target = try container.decode(String.self, forKey: .campaignID)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(label, forKey: .label)
        switch type {
        case .externalURL, .appRoute:
            try container.encode(target, forKey: .target)
        case .campaign:
            try container.encode(target, forKey: .campaignID)
        }
    }
}

public struct FeedbackDeveloperPost: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let body: String
    public let locale: String?
    public let action: FeedbackDeveloperPostAction?
    public let publishedAt: Date?
    public let pinnedAt: Date?
    public let updatedAt: Date
}

public struct FeedbackPublicSummary: Codable, Hashable, Sendable {
    public let type: FeedbackKind
    public let status: FeedbackStatus
    public let title: String?
    public let displayTitle: String
    public let body: String
    public let authorDisplayCode: String
    public let voteCount: Int
    public let hasVoted: Bool
    public let createdAt: Date
}

public struct FeedbackActivityPage: Codable, Sendable {
    public let entries: [FeedbackActivityEntry]
    public let nextCursor: String?

    public init(entries: [FeedbackActivityEntry], nextCursor: String?) {
        self.entries = entries
        self.nextCursor = nextCursor
    }
}

public enum FeedbackActivityEntry: Codable, Hashable, Identifiable, Sendable {
    public struct Metadata: Codable, Hashable, Sendable {
        public let id: String
        public let pinnedAt: Date?
        public let activityAt: Date
    }

    public struct DeveloperPostData: Codable, Hashable, Sendable {
        public let title: String
        public let body: String
        public let locale: String?
        public let action: FeedbackDeveloperPostAction?
        public let publishedAt: Date?
        public let updatedAt: Date
    }

    case feedback(Metadata, FeedbackPublicSummary)
    case developerPost(Metadata, DeveloperPostData)

    public var id: String { metadata.id }

    public var metadata: Metadata {
        switch self {
        case let .feedback(metadata, _), let .developerPost(metadata, _): metadata
        }
    }

    public var vote: (count: Int, hasVoted: Bool)? {
        guard case let .feedback(_, data) = self else { return nil }
        return (data.voteCount, data.hasVoted)
    }

    public func updatingVote(_ result: FeedbackVoteResult) -> Self {
        guard case let .feedback(metadata, data) = self else { return self }
        return .feedback(
            metadata,
            FeedbackPublicSummary(
                type: data.type,
                status: data.status,
                title: data.title,
                displayTitle: data.displayTitle,
                body: data.body,
                authorDisplayCode: data.authorDisplayCode,
                voteCount: result.voteCount,
                hasVoted: result.hasVoted,
                createdAt: data.createdAt
            )
        )
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case id
        case pinnedAt
        case activityAt
        case data
    }

    private enum Kind: String, Codable {
        case feedback
        case developerPost = "developer_post"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let metadata = Metadata(
            id: try container.decode(String.self, forKey: .id),
            pinnedAt: try container.decodeIfPresent(Date.self, forKey: .pinnedAt),
            activityAt: try container.decode(Date.self, forKey: .activityAt)
        )
        switch try container.decode(Kind.self, forKey: .kind) {
        case .feedback:
            self = .feedback(
                metadata,
                try container.decode(FeedbackPublicSummary.self, forKey: .data)
            )
        case .developerPost:
            self = .developerPost(
                metadata,
                try container.decode(DeveloperPostData.self, forKey: .data)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(metadata.pinnedAt, forKey: .pinnedAt)
        try container.encode(metadata.activityAt, forKey: .activityAt)
        switch self {
        case let .feedback(_, data):
            try container.encode(Kind.feedback, forKey: .kind)
            try container.encode(data, forKey: .data)
        case let .developerPost(_, data):
            try container.encode(Kind.developerPost, forKey: .kind)
            try container.encode(data, forKey: .data)
        }
    }
}
