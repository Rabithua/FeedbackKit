import FeedbackKitCore
import Foundation
import Observation

@MainActor
@Observable
final class FeedbackActivityListModel {
    var entries: [FeedbackActivityEntry] = []
    var nextCursor: String?
    var isLoading = false
    var isLoadingMore = false
    var error: Error?
    private(set) var votingFeedbackIDs: Set<String> = []
    let client: FeedbackClient

    init(client: FeedbackClient) {
        self.client = client
    }

    func load(locale: Locale, refresh _: Bool = false) async {
        if isLoading || isLoadingMore || votingFeedbackIDs.isEmpty == false { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let page = try await client.activity(locale: locale)
            entries = page.entries
            nextCursor = page.nextCursor
        } catch is CancellationError {
        } catch {
            self.error = error
        }
    }

    func more(locale: Locale) async {
        guard let nextCursor,
              isLoading == false,
              isLoadingMore == false
        else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await client.activity(locale: locale, cursor: nextCursor)
            entries.append(
                contentsOf: page.entries.filter { next in
                    entries.contains(where: { $0.id == next.id }) == false
                }
            )
            self.nextCursor = page.nextCursor
        } catch is CancellationError {
        } catch {
            self.error = error
        }
    }

    func optimisticVote(id: String, target: Bool) async -> Bool {
        guard isLoading == false,
              votingFeedbackIDs.contains(id) == false
        else { return false }
        guard let index = entries.firstIndex(where: { $0.id == id }),
              let vote = entries[index].vote,
              vote.hasVoted != target
        else { return false }
        let original = FeedbackVoteResult(
            feedbackId: id,
            hasVoted: vote.hasVoted,
            voteCount: vote.count
        )
        let optimistic = FeedbackVoteResult(
            feedbackId: id,
            hasVoted: target,
            voteCount: max(0, vote.count + (target ? 1 : -1))
        )

        votingFeedbackIDs.insert(id)
        defer { votingFeedbackIDs.remove(id) }
        entries[index] = entries[index].updatingVote(optimistic)
        do {
            let result = try await client.setVote(feedbackID: id, voted: target)
            updateVote(result, feedbackID: id)
            return true
        } catch is CancellationError {
            rollbackVote(
                original,
                optimistic: optimistic
            )
            return false
        } catch {
            rollbackVote(
                original,
                optimistic: optimistic
            )
            return false
        }
    }

    func isVoting(feedbackID: String) -> Bool {
        isLoading || votingFeedbackIDs.contains(feedbackID)
    }

    private func updateVote(_ result: FeedbackVoteResult, feedbackID: String) {
        guard let currentIndex = entries.firstIndex(where: { $0.id == feedbackID }) else {
            return
        }
        entries[currentIndex] = entries[currentIndex].updatingVote(result)
    }

    private func rollbackVote(
        _ original: FeedbackVoteResult,
        optimistic: FeedbackVoteResult
    ) {
        guard let currentIndex = entries.firstIndex(where: { $0.id == original.feedbackId }),
              let currentVote = entries[currentIndex].vote,
              currentVote.hasVoted == optimistic.hasVoted,
              currentVote.count == optimistic.voteCount
        else { return }
        entries[currentIndex] = entries[currentIndex].updatingVote(original)
    }
}
