import Foundation

public enum FeedbackKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case bug
    case suggestion
    case praise
    case conversation

    public var id: Self { self }
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

public enum RoadmapStage: String, Codable, CaseIterable, Identifiable, Sendable {
    case urgent
    case later
    case undecided

    public var id: Self { self }
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

public struct FeedbackVisitor: Codable, Equatable, Sendable {
    public let displayCode: String
    public let lastReadCursor: Int
}

public enum FeedbackInboxEventKind: String, Codable, Sendable {
    case adminReply = "admin.reply"
    case feedbackStatusChanged = "feedback.status_changed"
    case linkedItemArchived = "linked_item.archived"
}

public struct FeedbackInboxEvent: Codable, Hashable, Identifiable, Sendable {
    public var id: Int { sequence }
    public let sequence: Int
    public let feedbackId: String
    public let type: FeedbackInboxEventKind
    public let createdAt: Date
}

public struct FeedbackInboxPage: Codable, Sendable {
    public let events: [FeedbackInboxEvent]
    public let nextCursor: Int
    public let acknowledgedCursor: Int
    public let hasMore: Bool
}

public struct FeedbackRoadmapItem: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let type: String
    public let roadmapStage: RoadmapStage
    public let rank: Int
    public let archivedAt: Date?
    public let title: String
    public let body: String
    public let locale: String?
    public let createdAt: Date
    public let updatedAt: Date
}

public struct FeedbackRelease: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let version: String
    public let releasedAt: Date
    public let title: String
    public let body: String
    public let locale: String?
    public let items: [FeedbackRoadmapItem]

    public static func versionDescending(_ lhs: Self, _ rhs: Self) -> Bool {
        let comparison = lhs.normalizedVersion.compare(
            rhs.normalizedVersion,
            options: [.caseInsensitive, .numeric]
        )
        if comparison != .orderedSame { return comparison == .orderedDescending }
        if lhs.releasedAt != rhs.releasedAt { return lhs.releasedAt > rhs.releasedAt }
        return lhs.id > rhs.id
    }

    public var normalizedVersion: String {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.lowercased().hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed
    }
}

public struct FeedbackDeveloperPostAction: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case externalURL = "external_url"
        case appRoute = "app_route"
    }

    public let type: Kind
    public let target: String
    public let label: String?
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

    private enum CodingKeys: String, CodingKey { case kind, id, pinnedAt, activityAt, data }
    private enum Kind: String, Codable { case feedback; case developerPost = "developer_post" }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let metadata = Metadata(
            id: try container.decode(String.self, forKey: .id),
            pinnedAt: try container.decodeIfPresent(Date.self, forKey: .pinnedAt),
            activityAt: try container.decode(Date.self, forKey: .activityAt)
        )
        switch try container.decode(Kind.self, forKey: .kind) {
        case .feedback:
            self = .feedback(metadata, try container.decode(FeedbackPublicSummary.self, forKey: .data))
        case .developerPost:
            self = .developerPost(metadata, try container.decode(DeveloperPostData.self, forKey: .data))
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

public struct FeedbackBootstrap: Codable, Sendable {
    public let product: FeedbackProduct
    public let activity: FeedbackActivityPage
    public let roadmap: [FeedbackRoadmapItem]
    public let changelog: [FeedbackRelease]
    public let visitor: FeedbackVisitor
    public let inbox: FeedbackInboxPage

    public init(product: FeedbackProduct, activity: FeedbackActivityPage, roadmap: [FeedbackRoadmapItem], changelog: [FeedbackRelease], visitor: FeedbackVisitor, inbox: FeedbackInboxPage) {
        self.product = product
        self.activity = activity
        self.roadmap = roadmap
        self.changelog = changelog
        self.visitor = visitor
        self.inbox = inbox
    }
}

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
    public let type: FeedbackKind
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
}

public struct OwnedFeedbackPage: Codable, Sendable {
    public let feedback: [OwnedFeedbackSummary]
    public let nextCursor: String?
}

public struct FeedbackDetail: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let type: FeedbackKind
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

    public var isPublic: Bool { visibility == .public || (!isOwner && publishedAt != nil) }
}

public struct FeedbackClientContext: Codable, Equatable, Sendable {
    public let appVersion: String
    public let buildNumber: String
    public let osVersion: String
    public let deviceCategory: String
    public let locale: String

    public init(appVersion: String, buildNumber: String, osVersion: String, deviceCategory: String, locale: String) {
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.osVersion = osVersion
        self.deviceCategory = deviceCategory
        self.locale = locale
    }
}

public struct FeedbackCreateRequest: Codable, Equatable, Sendable {
    public let type: FeedbackKind
    public let title: String?
    public let body: String
    public let clientContext: FeedbackClientContext
    public let attachmentIds: [String]
    public let diagnosticArtifactId: String?

    public init(type: FeedbackKind, title: String?, body: String, clientContext: FeedbackClientContext, attachmentIds: [String], diagnosticArtifactId: String? = nil) {
        self.type = type
        self.title = title
        self.body = body
        self.clientContext = clientContext
        self.attachmentIds = attachmentIds
        self.diagnosticArtifactId = diagnosticArtifactId
    }
}

public struct FeedbackVoteResult: Codable, Equatable, Sendable {
    public let feedbackId: String
    public let hasVoted: Bool
    public let voteCount: Int

    public init(feedbackId: String, hasVoted: Bool, voteCount: Int) {
        self.feedbackId = feedbackId
        self.hasVoted = hasVoted
        self.voteCount = voteCount
    }
}

public struct FeedbackSignedAttachmentURL: Codable, Equatable, Sendable {
    public let url: URL
    public let expiresIn: Int
    public let posterUrl: URL?
}

public struct FeedbackAttachmentSource: Identifiable, Sendable {
    public let id: UUID
    public let filename: String
    public let contentType: String
    public let data: Data
    public let width: Int?
    public let height: Int?
    public let durationMs: Int?

    public init(id: UUID = UUID(), filename: String, contentType: String, data: Data, width: Int? = nil, height: Int? = nil, durationMs: Int? = nil) {
        self.id = id
        self.filename = filename
        self.contentType = contentType
        self.data = data
        self.width = width
        self.height = height
        self.durationMs = durationMs
    }
}

public struct FeedbackDiagnosticSnapshot: Sendable {
    public let data: Data
    public let schemaVersion: Int
    public let sha256: String

    public init(data: Data, schemaVersion: Int, sha256: String) {
        self.data = data
        self.schemaVersion = schemaVersion
        self.sha256 = sha256
    }
}

public protocol FeedbackDiagnosticSnapshotProviding: Sendable {
    func makeDiagnosticSnapshot() async throws -> FeedbackDiagnosticSnapshot
}

public protocol FeedbackDiagnosticsProviding: FeedbackDiagnosticSnapshotProviding {
    func recordNetwork(method: String, host: String, path: String, statusCode: Int?, duration: TimeInterval, errorCategory: String?) async
}
