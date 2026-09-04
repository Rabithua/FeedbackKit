@testable import FeedbackKitCore
import Foundation
import Testing

struct FeedbackModelBehaviorTests {
    @Test("Acknowledging inbox events advances monotonically and reduces unread count")
    func inboxAcknowledgementIsMonotonic() {
        let page = FeedbackInboxPage(
            events: [inboxEvent(sequence: 11), inboxEvent(sequence: 12), inboxEvent(sequence: 14)],
            nextCursor: 14,
            acknowledgedCursor: 10,
            unreadCount: 3,
            hasMore: false
        )

        let acknowledged = page.acknowledging(through: 12)
        let attemptedRegression = acknowledged.acknowledging(through: 9)

        #expect(acknowledged.acknowledgedCursor == 12)
        #expect(acknowledged.unreadCount == 1)
        #expect(attemptedRegression.acknowledgedCursor == 12)
        #expect(attemptedRegression.unreadCount == 1)
    }

    @Test("Release ordering compares numeric versions before date and ID")
    func releaseOrderingUsesStableTieBreakers() {
        let oldest = release(id: "a", version: "v2.9", releasedAt: Date(timeIntervalSince1970: 1))
        let newerVersion = release(id: "b", version: "2.10", releasedAt: Date(timeIntervalSince1970: 0))
        let sameVersionNewerDate = release(
            id: "c",
            version: "2.10",
            releasedAt: Date(timeIntervalSince1970: 2)
        )
        let sameVersionDateHigherID = release(
            id: "d",
            version: "v2.10",
            releasedAt: Date(timeIntervalSince1970: 2)
        )

        let sorted = [oldest, newerVersion, sameVersionNewerDate, sameVersionDateHigherID]
            .sorted(by: FeedbackRelease.versionDescending)

        #expect(sorted.map(\.id) == ["d", "c", "b", "a"])
        #expect(oldest.normalizedVersion == "2.9")
    }

    @Test("Updating an activity vote preserves its feedback content")
    func activityVoteUpdatePreservesContent() throws {
        let createdAt = Date(timeIntervalSince1970: 1)
        let entry = FeedbackActivityEntry.feedback(
            .init(id: "feedback-id", pinnedAt: nil, activityAt: createdAt),
            FeedbackPublicSummary(
                type: .suggestion,
                status: .open,
                title: "Title",
                displayTitle: "Display title",
                body: "Body",
                authorDisplayCode: "ABC-123",
                voteCount: 3,
                hasVoted: false,
                createdAt: createdAt
            )
        )

        let updated = entry.updatingVote(
            FeedbackVoteResult(feedbackId: "feedback-id", hasVoted: true, voteCount: 4)
        )
        let vote = try #require(updated.vote)

        #expect(updated.id == entry.id)
        #expect(vote.count == 4)
        #expect(vote.hasVoted == true)
        guard case let .feedback(_, summary) = updated else {
            Issue.record("Expected a feedback activity entry")
            return
        }
        #expect(summary.title == "Title")
        #expect(summary.body == "Body")
    }

    @Test("Feedback visibility respects explicit publication and ownership")
    func detailVisibilityRules() {
        #expect(detail(visibility: .public, isOwner: true, publishedAt: nil).isPublic)
        #expect(
            detail(
                visibility: nil,
                isOwner: false,
                publishedAt: Date(timeIntervalSince1970: 1)
            ).isPublic
        )
        #expect(detail(visibility: .private, isOwner: true, publishedAt: nil).isPublic == false)
    }

    private func inboxEvent(sequence: Int) -> FeedbackInboxEvent {
        FeedbackInboxEvent(
            sequence: sequence,
            feedbackId: "feedback-\(sequence)",
            type: .adminReply,
            createdAt: Date(timeIntervalSince1970: TimeInterval(sequence))
        )
    }

    private func release(id: String, version: String, releasedAt: Date) -> FeedbackRelease {
        FeedbackRelease(
            id: id,
            version: version,
            releasedAt: releasedAt,
            body: "Body",
            locale: "en",
            items: []
        )
    }

    private func detail(
        visibility: FeedbackVisibility?,
        isOwner: Bool,
        publishedAt: Date?
    ) -> FeedbackDetail {
        FeedbackDetail(
            id: "feedback-id",
            recordKind: .bug,
            title: nil,
            displayTitle: "Feedback",
            body: "Body",
            status: .open,
            visibility: visibility,
            publishedAt: publishedAt,
            pinnedAt: nil,
            lastActivityAt: nil,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: nil,
            authorDisplayCode: "ABC-123",
            isOwner: isOwner,
            voteCount: 0,
            hasVoted: false,
            messages: [],
            attachments: [],
            diagnosticsIncluded: nil
        )
    }
}
