import Foundation

public struct FeedbackClientContext: Codable, Equatable, Sendable {
    public let appVersion: String
    public let buildNumber: String
    public let osVersion: String
    public let deviceCategory: String
    public let locale: String

    public init(
        appVersion: String,
        buildNumber: String,
        osVersion: String,
        deviceCategory: String,
        locale: String
    ) {
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

    public init(
        type: FeedbackKind,
        title: String?,
        body: String,
        clientContext: FeedbackClientContext,
        attachmentIds: [String],
        diagnosticArtifactId: String? = nil
    ) {
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
