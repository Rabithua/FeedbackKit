import FeedbackKitCore
import Foundation
import Observation

@MainActor
@Observable
final class FeedbackDeveloperPostModel {
    var post: FeedbackDeveloperPost?
    var isLoading = false
    var error: Error?
    let client: FeedbackClient
    let id: String

    init(id: String, client: FeedbackClient) {
        self.id = id
        self.client = client
    }

    func load(locale: Locale) async {
        guard isLoading == false else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            post = try await client.developerPost(id: id, locale: locale)
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error
        }
    }
}
