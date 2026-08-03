import FeedbackKitCore
import Observation
import SwiftUI

@MainActor
@Observable
final class FeedbackCenterModel {
    private(set) var bootstrap: FeedbackBootstrap?
    private(set) var isLoading = false
    private(set) var error: Error?
    var path: [FeedbackCenterPage] = []
    var sheet: FeedbackCenterSheet?

    let client: FeedbackClient

    init(client: FeedbackClient) {
        self.client = client
    }

    func load(locale: Locale, force: Bool = false) async {
        if isLoading || (!force && bootstrap != nil) { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let loaded = try await client.bootstrap(locale: locale)
            bootstrap = loaded
            if loaded.inbox.nextCursor > loaded.inbox.acknowledgedCursor {
                if let acknowledgedCursor = try? await client.acknowledgeInbox(cursor: loaded.inbox.nextCursor),
                   let current = bootstrap
                {
                    bootstrap = FeedbackBootstrap(
                        product: current.product,
                        activity: current.activity,
                        roadmap: current.roadmap,
                        changelog: current.changelog,
                        visitor: current.visitor,
                        inbox: current.inbox.acknowledging(through: acknowledgedCursor)
                    )
                }
            }
        } catch is CancellationError {
        } catch {
            self.error = error
        }
    }

    func updateVote(feedbackID: String, target: Bool) async -> Bool {
        guard var current = bootstrap else { return false }
        current = FeedbackBootstrap(
            product: current.product,
            activity: FeedbackActivityPage(
                entries: current.activity.entries.map { entry in
                    guard entry.id == feedbackID, let vote = entry.vote else { return entry }
                    return entry.updatingVote(
                        FeedbackVoteResult(
                            feedbackId: feedbackID,
                            hasVoted: target,
                            voteCount: max(0, vote.count + (target ? 1 : -1))
                        )
                    )
                },
                nextCursor: current.activity.nextCursor
            ),
            roadmap: current.roadmap,
            changelog: current.changelog,
            visitor: current.visitor,
            inbox: current.inbox
        )
        bootstrap = current
        do {
            let result = try await client.setVote(feedbackID: feedbackID, voted: target)
            synchronizeVote(result)
            return true
        } catch {
            if let vote = bootstrap?.activity.entries.first(where: { $0.id == feedbackID })?.vote {
                synchronizeVote(
                    FeedbackVoteResult(
                        feedbackId: feedbackID,
                        hasVoted: !target,
                        voteCount: max(0, vote.count + (target ? -1 : 1))
                    )
                )
            }
            return false
        }
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
