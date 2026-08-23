import FeedbackKitCore
import Foundation
import Observation

@MainActor
@Observable
final class FeedbackDeveloperPostModel {
    var post: FeedbackDeveloperPost?
    var isLoading = false
    var error: Error?
    @ObservationIgnored private var loadGeneration = 0
    let client: FeedbackClient
    let id: String

    init(id: String, client: FeedbackClient) {
        self.id = id
        self.client = client
    }

    func load(locale: Locale) async {
        loadGeneration &+= 1
        let generation = loadGeneration
        isLoading = true
        defer {
            if generation == loadGeneration {
                isLoading = false
            }
        }
        do {
            let loadedPost = try await client.developerPost(id: id, locale: locale)
            guard generation == loadGeneration else { return }
            post = loadedPost
            error = nil
        } catch is CancellationError {
        } catch {
            guard generation == loadGeneration else { return }
            self.error = error
        }
    }
}
