import FeedbackKitCore
import SwiftUI

struct FeedbackKindPicker: View {
    let style: FeedbackStyle
    let select: (FeedbackKind) -> Void
    let close: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.feedbackHaptics) private var haptics
    @Environment(\.feedbackLocalization) private var localization

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            FeedbackSheetHeader(title: localization.text("feedbackkit.kind.title"), close: close)
            let columns = dynamicTypeSize.isAccessibilitySize
                ? [GridItem(.flexible())]
                : [GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(FeedbackKind.submittableCases) { kind in
                    Button {
                        haptics.trigger(.selection)
                        select(kind)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(localization.kind(kind))
                                .font(.headline)
                            Text(kindDescription(kind))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
                        .padding(.horizontal, 14)
                        .contentShape(.interaction, FeedbackComponentShape(cornerRadius: style.cardCornerRadius))
                        .feedbackBorder(style)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(localization.kind(kind))
                    .accessibilityHint(kindDescription(kind))
                }
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, style.pagePadding)
        .padding(.top, 14)
        .presentationDetents([.medium])
        .accessibilityIdentifier("developerCommunity.kindPicker")
    }

    private func kindDescription(_ kind: FeedbackKind) -> String {
        switch kind {
        case .bug: localization.text("feedbackkit.kind.bug.description")
        case .suggestion: localization.text("feedbackkit.kind.suggestion.description")
        case .praise: localization.text("feedbackkit.kind.praise.description")
        case .conversation: localization.text("feedbackkit.kind.conversation.description")
        }
    }
}
