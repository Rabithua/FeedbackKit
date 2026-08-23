import FeedbackKitCore
import Observation

@MainActor
@Observable
final class FeedbackOwnedListModel {
    var items: [OwnedFeedbackSummary] = []
    var nextCursor: String?
    var isLoading = false
    var isLoadingMore = false
    var error: Error?
    let client: FeedbackClient

    init(client: FeedbackClient) {
        self.client = client
    }

    func load(refresh _: Bool = false) async {
        guard isLoading == false, isLoadingMore == false else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let page = try await client.ownedFeedback()
            items = page.feedback
            nextCursor = page.nextCursor
        } catch is CancellationError {
        } catch {
            self.error = error
        }
    }

    func more() async {
        guard let nextCursor,
              isLoading == false,
              isLoadingMore == false
        else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await client.ownedFeedback(cursor: nextCursor)
            items.append(contentsOf: page.feedback.filter { next in
                items.contains(where: { $0.id == next.id }) == false
            })
            self.nextCursor = page.nextCursor
        } catch is CancellationError {
        } catch {
            self.error = error
        }
    }
}
