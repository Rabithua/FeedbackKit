import PhotosUI
import SwiftUI

struct FeedbackAttachmentStrip: View {
    let model: FeedbackComposerModel
    @Binding var selections: [PhotosPickerItem]
    let style: FeedbackStyle
    let remove: (UUID) -> Void
    @Environment(\.feedbackLocalization) private var localization

    var body: some View {
        let addTitle = model.isImporting
            ? localization.text("feedbackkit.loading")
            : localization.text("feedbackkit.attachment.add")
        let isImporting = model.isImporting

        ScrollView(.horizontal) {
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(model.attachments) { attachment in
                    FeedbackAttachmentTile(
                        filename: attachment.filename,
                        removeLabel: localization.text("feedbackkit.attachment.discard"),
                        style: style,
                        remove: { remove(attachment.id) }
                    )
                }
                PhotosPicker(
                    selection: $selections,
                    maxSelectionCount: max(
                        0,
                        model.product.attachmentLimits.count - model.attachments.count
                    ),
                    matching: .any(of: [.images, .videos])
                ) {
                    FeedbackAttachmentAddLabel(
                        title: addTitle,
                        isLoading: isImporting,
                        style: style
                    )
                }
                .buttonStyle(.plain)
                .disabled(
                    model.isImporting
                        || model.attachments.count >= model.product.attachmentLimits.count
                )
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 2)
        }
        .scrollIndicators(.hidden)
    }
}
