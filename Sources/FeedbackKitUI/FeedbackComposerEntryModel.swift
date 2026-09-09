import FeedbackKitCore
import Observation

@MainActor @Observable
final class FeedbackComposerEntryModel {
    enum Phase: Equatable {
        case update(FeedbackAppUpdate)
        case composing
    }

    private(set) var phase: Phase

    /// Snapshot the completed check when the entry opens. Late results cannot interrupt typing.
    init(kind: FeedbackKind, availableUpdate: FeedbackAppUpdate?) {
        if kind == .bug, let availableUpdate {
            phase = .update(availableUpdate)
        } else {
            phase = .composing
        }
    }

    func continueFeedback() {
        phase = .composing
    }
}
