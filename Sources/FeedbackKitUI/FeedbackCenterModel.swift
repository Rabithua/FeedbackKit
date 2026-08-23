import FeedbackKitCore
import Observation
import SwiftUI

@MainActor
@Observable
final class FeedbackCenterModel {
    private(set) var bootstrap: FeedbackBootstrap?
    private(set) var isLoading = false
    private(set) var error: Error?
    private(set) var votingFeedbackIDs: Set<String> = []
    var path: [FeedbackCenterPage] = []
    var sheet: FeedbackCenterSheet?

    let client: FeedbackClient

    init(client: FeedbackClient) {
        self.client = client
    }

    func load(locale: Locale, force: Bool = false) async {
        if isLoading
            || votingFeedbackIDs.isEmpty == false
            || (!force && bootstrap != nil)
        {
            return
        }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            bootstrap = try await client.bootstrap(locale: locale)
        } catch is CancellationError {
        } catch {
            self.error = error
        }
    }

    func markFeedbackRead(feedbackID: String) async {
        guard let current = bootstrap,
              let cursor = current.inbox.events
                .filter({ $0.feedbackId == feedbackID && $0.sequence > current.inbox.acknowledgedCursor })
                .map(\.sequence)
                .max()
        else { return }

        guard let acknowledgedCursor = try? await client.acknowledgeInbox(cursor: cursor),
              let latest = bootstrap
        else { return }

        bootstrap = FeedbackBootstrap(
            product: latest.product,
            activity: latest.activity,
            roadmap: latest.roadmap,
            changelog: latest.changelog,
            visitor: latest.visitor,
            inbox: latest.inbox.acknowledging(through: acknowledgedCursor)
        )
    }

    func updateVote(feedbackID: String, target: Bool) async -> Bool {
        guard isLoading == false,
              votingFeedbackIDs.contains(feedbackID) == false,
              let vote = bootstrap?.activity.entries.first(where: { $0.id == feedbackID })?.vote,
              vote.hasVoted != target
        else { return false }
        let original = FeedbackVoteResult(
            feedbackId: feedbackID,
            hasVoted: vote.hasVoted,
            voteCount: vote.count
        )
        let optimistic = FeedbackVoteResult(
            feedbackId: feedbackID,
            hasVoted: target,
            voteCount: max(0, vote.count + (target ? 1 : -1))
        )

        votingFeedbackIDs.insert(feedbackID)
        defer { votingFeedbackIDs.remove(feedbackID) }
        synchronizeVote(optimistic)
        do {
            let result = try await client.setVote(feedbackID: feedbackID, voted: target)
            synchronizeVote(result)
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

    func synchronizeVote(_ result: FeedbackVoteResult) {
        guard let current = bootstrap else { return }
        bootstrap = FeedbackBootstrap(
            product: current.product,
            activity: FeedbackActivityPage(
                entries: current.activity.entries.map { $0.id == result.feedbackId ? $0.updatingVote(result) : $0 },
                nextCursor: current.activity.nextCursor
            ),
            roadmap: current.roadmap,
            changelog: current.changelog,
            visitor: current.visitor,
            inbox: current.inbox
        )
    }

    private func rollbackVote(
        _ original: FeedbackVoteResult,
        optimistic: FeedbackVoteResult
    ) {
        guard let currentVote = bootstrap?.activity.entries
                  .first(where: { $0.id == original.feedbackId })?.vote,
              currentVote.hasVoted == optimistic.hasVoted,
              currentVote.count == optimistic.voteCount
        else { return }
        synchronizeVote(original)
    }

    @discardableResult
    func openPackageRoute(_ route: String) -> Bool {
        switch route {
        case "/": path.removeAll()
        case "/activity": path.append(.activity)
        case "/feedback/new": sheet = .kinds
        case "/feedback/mine": path.append(.mine)
        case "/roadmap": path.append(.roadmap)
        case "/releases": path.append(.releases)
        default:
            guard let components = URLComponents(string: route) else { return false }
            if components.path == "/feedback/new",
               components.queryItems?.count == 1,
               let item = components.queryItems?.first,
               item.name == "type",
               let value = item.value,
               let kind = FeedbackKind(rawValue: value)
            {
                sheet = .composer(kind)
            } else if let id = routeUUID(components.path, prefix: "/feedback/") {
                sheet = .feedback(id)
            } else if let id = routeUUID(components.path, prefix: "/developer-posts/") {
                sheet = .developerPost(id)
            } else if routeUUID(components.path, prefix: "/items/") != nil {
                path.append(.roadmap)
            } else if routeUUID(components.path, prefix: "/releases/") != nil {
                path.append(.releases)
            } else {
                return false
            }
        }
        return true
    }

    private func routeUUID(_ route: String, prefix: String) -> String? {
        guard route.hasPrefix(prefix) else { return nil }
        let value = String(route.dropFirst(prefix.count))
        return UUID(uuidString: value) == nil ? nil : value
    }
}
