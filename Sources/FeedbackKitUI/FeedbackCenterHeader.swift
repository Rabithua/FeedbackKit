import SwiftUI

struct FeedbackCenterHeader: View {
    let showsMenu: Bool
    let style: FeedbackStyle
    let openPage: (FeedbackCenterPage) -> Void
    let dismiss: () -> Void

    @Environment(\.feedbackLocalization) private var localization

    var body: some View {
        HStack(spacing: 4) {
            if showsMenu {
                Menu {
                    Button(localization.text("feedbackkit.identity.title")) { openPage(.identity) }
                    Button(localization.text("feedbackkit.diagnostics.title")) { openPage(.diagnostics) }
                } label: {
                    Label(
                        localization.text("feedbackkit.center.title"),
                        systemImage: "bubble.left.and.bubble.right"
                    )
                    .labelStyle(.iconOnly)
                    .font(.title3.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
            }

            Text(localization.text("feedbackkit.center.title"))
                .font(.title2.bold())
            Spacer(minLength: 8)
            FeedbackCloseButton(action: dismiss)
        }
        .padding(.horizontal, style.pagePadding)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }
}
