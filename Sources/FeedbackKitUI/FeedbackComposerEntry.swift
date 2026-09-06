import FeedbackKitCore
import SwiftUI

struct FeedbackComposerEntry<Composer: View>: View {
    @State private var model: FeedbackComposerEntryModel
    private let style: FeedbackStyle
    private let close: () -> Void
    private let composer: () -> Composer
    @Environment(\.feedbackHaptics) private var haptics
    @Environment(\.feedbackLocalization) private var localization

    init(
        kind: FeedbackKind,
        updateChecker: (any FeedbackAppUpdateChecking)?,
        style: FeedbackStyle,
        close: @escaping () -> Void,
        @ViewBuilder composer: @escaping () -> Composer
    ) {
        _model = State(initialValue: FeedbackComposerEntryModel(kind: kind, updateChecker: updateChecker))
        self.style = style
        self.close = close
        self.composer = composer
    }

    var body: some View {
        Group {
            switch model.phase {
            case .checking:
                VStack(spacing: 24) {
                    FeedbackSheetHeader(title: localization.kind(FeedbackKind.bug), close: close)
                    ProgressView(localization.text("feedbackkit.update.checking"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Button(localization.text("feedbackkit.update.continue")) {
                        haptics.trigger(.action)
                        model.continueFeedback()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding(.horizontal, style.pagePadding)
                .padding(.vertical, 24)
                .presentationDetents([.medium, .large])
            case let .update(update):
                FeedbackAppUpdateSheet(
                    update: update,
                    haptics: haptics,
                    continueFeedback: model.continueFeedback,
                    close: close
                )
            case .composing:
                composer()
            }
        }
        .task { await model.checkForUpdate() }
    }
}
