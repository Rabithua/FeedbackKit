import FeedbackKitCore
import Foundation
import Observation

@MainActor
@Observable
final class FeedbackDetailModel {
    var detail: FeedbackDetail? {
        didSet { detailRevision &+= 1 }
    }
    var isLoading = false
    private(set) var isVoting = false
    var replyBody = ""
    var isReplying = false
    var replyError: String?
    var error: Error?
    private var pendingReply: (body: String, key: String)?
    let client: FeedbackClient
    let id: String
    let voteChanged: (FeedbackVoteResult) -> Void
    @ObservationIgnored private var detailRevision = 0

    init(
        id: String,
        client: FeedbackClient,
        voteChanged: @escaping (FeedbackVoteResult) -> Void
    ) {
        self.id = id
        self.client = client
        self.voteChanged = voteChanged
    }

    func load() async -> Bool {
        guard isLoading == false, isVoting == false else { return false }
        isLoading = true
        defer { isLoading = false }
        do {
            detail = try await client.feedback(id: id)
            error = nil
            return true
        } catch is CancellationError {
            return false
        } catch {
            self.error = error
            return false
        }
    }

    func vote() async -> Bool {
        guard isLoading == false,
              isVoting == false,
              var current = detail,
              current.isPublic
        else { return false }
        let original = FeedbackVoteResult(
            feedbackId: id,
            hasVoted: current.hasVoted,
            voteCount: current.voteCount
        )
        let target = current.hasVoted == false
        let optimistic = FeedbackVoteResult(
            feedbackId: id,
            hasVoted: target,
            voteCount: max(0, current.voteCount + (target ? 1 : -1))
        )

        isVoting = true
        defer { isVoting = false }
        current.hasVoted = optimistic.hasVoted
        current.voteCount = optimistic.voteCount
        detail = current
        let optimisticRevision = detailRevision
        do {
            let result = try await client.setVote(feedbackID: id, voted: target)
            if var latest = detail {
                latest.hasVoted = result.hasVoted
                latest.voteCount = result.voteCount
                detail = latest
            }
            voteChanged(result)
            return true
        } catch is CancellationError {
            rollbackVote(
                original,
                optimistic: optimistic,
                optimisticRevision: optimisticRevision
            )
            return false
        } catch {
            rollbackVote(
                original,
                optimistic: optimistic,
                optimisticRevision: optimisticRevision
            )
            return false
        }
    }

    private func rollbackVote(
        _ original: FeedbackVoteResult,
        optimistic: FeedbackVoteResult,
        optimisticRevision: Int
    ) {
        guard detailRevision == optimisticRevision,
              var latest = detail,
              latest.hasVoted == optimistic.hasVoted,
              latest.voteCount == optimistic.voteCount
        else { return }
        latest.hasVoted = original.hasVoted
        latest.voteCount = original.voteCount
        detail = latest
    }

    func reply(localization: FeedbackLocalization) async -> Bool {
        let body = replyBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard body.isEmpty == false,
              body.count <= 20_000,
              detail?.isOwner == true,
              detail?.status == .open
        else { return false }
        isReplying = true
        replyError = nil
        defer { isReplying = false }
        let attempt: (body: String, key: String)
        if let pendingReply, pendingReply.body == body {
            attempt = pendingReply
        } else {
            attempt = (body, UUID().uuidString)
            pendingReply = attempt
        }
        do {
            _ = try await client.addVisitorMessage(
                feedbackID: id,
                body: body,
                idempotencyKey: attempt.key
            )
            replyBody = ""
            pendingReply = nil
            detail = try await client.feedback(id: id)
            return true
        } catch {
            replyError = localization.errorMessage(for: error)
            return false
        }
    }
}
