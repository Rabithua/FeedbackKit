import Foundation

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
    public let unreadCount: Int
    public let hasMore: Bool

    public init(
        events: [FeedbackInboxEvent],
        nextCursor: Int,
        acknowledgedCursor: Int,
        unreadCount: Int,
        hasMore: Bool
    ) {
        self.events = events
        self.nextCursor = nextCursor
        self.acknowledgedCursor = acknowledgedCursor
        self.unreadCount = max(0, unreadCount)
        self.hasMore = hasMore
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let events = try container.decode([FeedbackInboxEvent].self, forKey: .events)
        let acknowledgedCursor = try container.decode(Int.self, forKey: .acknowledgedCursor)

        self.events = events
        self.nextCursor = try container.decode(Int.self, forKey: .nextCursor)
        self.acknowledgedCursor = acknowledgedCursor
        self.unreadCount = max(
            0,
            try container.decodeIfPresent(Int.self, forKey: .unreadCount)
                ?? events.count(where: { $0.sequence > acknowledgedCursor })
        )
        self.hasMore = try container.decode(Bool.self, forKey: .hasMore)
    }

    public func acknowledging(through cursor: Int) -> Self {
        let updatedCursor = max(acknowledgedCursor, cursor)
        let newlyAcknowledged = events.count {
            $0.sequence > acknowledgedCursor && $0.sequence <= updatedCursor
        }
        return Self(
            events: events,
            nextCursor: nextCursor,
            acknowledgedCursor: updatedCursor,
            unreadCount: unreadCount - newlyAcknowledged,
            hasMore: hasMore
        )
    }
}
