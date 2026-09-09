import FeedbackKitCore
import SwiftUI

struct FeedbackComposerEntry<Composer: View>: View {
    @State private var model: FeedbackComposerEntryModel
    private let updateSheetLayout: FeedbackAppUpdateSheetLayout?
    private let close: () -> Void
    private let composer: () -> Composer
    @Environment(\.feedbackHaptics) private var haptics

    init(
        kind: FeedbackKind,
        availableUpdate: FeedbackAppUpdate?,
        updateSheetLayout: FeedbackAppUpdateSheetLayout?,
        close: @escaping () -> Void,
        @ViewBuilder composer: @escaping () -> Composer
    ) {
        _model = State(initialValue: FeedbackComposerEntryModel(kind: kind, availableUpdate: availableUpdate))
        self.updateSheetLayout = updateSheetLayout
        self.close = close
        self.composer = composer
    }

    var body: some View {
        Group {
            switch model.phase {
            case let .update(update):
                FeedbackAppUpdateSheet(
                    update: update,
                    haptics: haptics,
                    layout: updateSheetLayout,
                    continueFeedback: model.continueFeedback,
                    close: close
                )
            case .composing:
                composer()
            }
        }
    }
}
