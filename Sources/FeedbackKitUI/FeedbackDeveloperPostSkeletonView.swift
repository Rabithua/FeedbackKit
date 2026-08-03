import SwiftUI

struct FeedbackDeveloperPostSkeletonView: View {
    let style: FeedbackStyle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Developer post title placeholder")
                    .font(.title2.bold())

                VStack(alignment: .leading, spacing: 6) {
                    Text("Developer post content placeholder that fills the available width.")
                    Text("Another line of developer post content.")
                    Text("Final content placeholder.")
                }

                Color.clear
                    .feedbackBorder(style)
                    .frame(maxWidth: .infinity, minHeight: 52)

                Text("Published recently")
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, style.pagePadding)
            .padding(.bottom, 24)
        }
    }
}
