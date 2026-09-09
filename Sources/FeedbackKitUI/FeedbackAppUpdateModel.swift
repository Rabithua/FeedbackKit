import Observation

/// One background check per center presentation. Hosts own cross-presentation caching.
@MainActor @Observable
final class FeedbackAppUpdateModel {
    private(set) var update: FeedbackAppUpdate?
    private let checker: (any FeedbackAppUpdateChecking)?
    private var started = false

    init(checker: (any FeedbackAppUpdateChecking)?) {
        self.checker = checker
    }

    func prefetch() async {
        guard !started, let checker else { return }
        started = true
        do {
            let result = try await checker.availableUpdate()
            guard !Task.isCancelled else { started = false; return }
            update = result
        } catch {
            // An unavailable check never blocks feedback or presents an error.
            if Task.isCancelled { started = false }
        }
    }
}
