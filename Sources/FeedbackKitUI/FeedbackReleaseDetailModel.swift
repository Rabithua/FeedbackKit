import FeedbackKitCore
import Foundation
import Observation

@MainActor
@Observable
final class FeedbackReleaseDetailModel {
    private(set) var release: FeedbackRelease?
    private(set) var isLoading = false
    private(set) var error: Error?

    let id: String
    private let client: FeedbackClient

    init(client: FeedbackClient, id: String, initial: FeedbackRelease?) {
        self.client = client
        self.id = id
        release = initial
    }

    func load(locale: Locale) async {
        guard isLoading == false else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            release = try await client.release(id: id, locale: locale)
        } catch is CancellationError {
        } catch {
            self.error = error
        }
    }
}
