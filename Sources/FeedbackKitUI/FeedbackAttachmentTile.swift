import SwiftUI

struct FeedbackAttachmentTile: View {
    static let controlSize: CGFloat = 44
    static let controlRadius = controlSize / 2
    static let layoutWidth = FeedbackStyle.attachmentTileSize + controlRadius
    static let layoutHeight = FeedbackStyle.attachmentTileSize + controlRadius

    let filename: String
    let removeLabel: String
    let style: FeedbackStyle
    let remove: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Text(filename)
                .font(.caption)
                .lineLimit(3)
                .multilineTextAlignment(.center)
                .padding(8)
                .frame(
                    width: FeedbackStyle.attachmentTileSize,
                    height: FeedbackStyle.attachmentTileSize
                )
                .feedbackBorder(style)
                .offset(y: Self.controlRadius)

            FeedbackHitTargetButton(action: remove) {
                Label(removeLabel, systemImage: "xmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.7))
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .offset(x: FeedbackStyle.attachmentTileSize - Self.controlRadius)
        }
        .frame(width: Self.layoutWidth, height: Self.layoutHeight, alignment: .topLeading)
    }
}
