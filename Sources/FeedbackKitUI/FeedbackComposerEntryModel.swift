import FeedbackKitCore
import Observation

@MainActor @Observable
final class FeedbackComposerEntryModel {
    enum Phase: Equatable {
        case checking
        case update(FeedbackAppUpdate)
        case composing
    }

    private(set) var phase: Phase
    private let updateChecker: (any FeedbackAppUpdateChecking)?

    init(kind: FeedbackKind, updateChecker: (any FeedbackAppUpdateChecking)?) {
        self.updateChecker = updateChecker
        phase = kind == .bug && updateChecker != nil ? .checking : .composing
    }

    func checkForUpdate() async {
        guard phase == .checking, let updateChecker else { return }
        do {
            let update = try await updateChecker.availableUpdate()
            guard !Task.isCancelled, phase == .checking else { return }
            phase = update.map(Phase.update) ?? .composing
        } catch {
            guard !Task.isCancelled, phase == .checking else { return }
            phase = .composing
        }
    }

    func continueFeedback() {
        phase = .composing
    }
}
