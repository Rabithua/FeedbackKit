import FeedbackKitCore
import Foundation
import Observation

@MainActor
@Observable
final class FeedbackReleaseListModel {
    private(set) var releases: [FeedbackRelease]
    private(set) var isLoading = false
    private(set) var error: Error?

    private let client: FeedbackClient

    init(client: FeedbackClient, initial: [FeedbackRelease]) {
        self.client = client
        releases = initial.sorted(by: FeedbackRelease.versionDescending)
    }

    func load(locale: Locale) async {
        guard isLoading == false else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            releases = try await client.releases(locale: locale).sorted(by: FeedbackRelease.versionDescending)
        } catch is CancellationError {
        } catch {
            self.error = error
        }
    }
}
