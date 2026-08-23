import SwiftUI

struct FeedbackAttachmentAddLabel: View {
    let title: String
    let isLoading: Bool
    let style: FeedbackStyle

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .tint(.secondary)
                    .accessibilityLabel(title)
            } else {
                Label(title, systemImage: "paperclip")
                    .labelStyle(.iconOnly)
                    .font(.title2)
            }
        }
        .foregroundStyle(.secondary)
        .frame(width: FeedbackStyle.attachmentTileSize, height: FeedbackStyle.attachmentTileSize)
        .contentShape(.interaction, FeedbackComponentShape(cornerRadius: style.cardCornerRadius))
        .feedbackBorder(style)
    }
}
