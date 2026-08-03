import FeedbackKitCore
import Foundation
import Observation

@MainActor
@Observable
final class FeedbackReleaseListModel {
    private(set) var releases: [FeedbackRelease]
    private(set) var isLoading = false
    private(set) var error: Error?
    private(set) var generation = 0

    private let client: FeedbackClient
    private var loadingDetailRequests: Set<String> = []
    private var loadedDetailIDs: Set<String> = []

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
            generation += 1
            loadingDetailRequests.removeAll()
            loadedDetailIDs.removeAll()
        } catch is CancellationError {
        } catch {
            self.error = error
        }
    }

    func loadDetailsIfNeeded(for id: String, locale: Locale, generation: Int) async {
        let requestKey = "\(generation)|\(id)"
        guard generation == self.generation,
              loadedDetailIDs.contains(id) == false,
              loadingDetailRequests.contains(requestKey) == false,
              let release = releases.first(where: { $0.id == id }),
              release.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }

        loadingDetailRequests.insert(requestKey)
        defer { loadingDetailRequests.remove(requestKey) }

        do {
            let detail = try await client.release(id: id, locale: locale)
            guard generation == self.generation,
                  let index = releases.firstIndex(where: { $0.id == id })
            else { return }
            releases[index] = detail
            loadedDetailIDs.insert(id)
        } catch is CancellationError {
        } catch {
            // The existing list item remains visible; pull-to-refresh retries hydration.
        }
    }
}
