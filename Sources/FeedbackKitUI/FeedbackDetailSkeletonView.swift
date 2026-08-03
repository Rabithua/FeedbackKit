import SwiftUI

struct FeedbackDetailSkeletonView: View {
    let style: FeedbackStyle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Feedback title placeholder")
                    .font(.title3)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Feedback body placeholder that fills almost the whole available width.")
                    Text("Additional context placeholder for the submitted feedback content.")
                    Text("One more line of feedback context.")
                }

                Color.clear
                    .feedbackBorder(style)
                    .frame(width: 86, height: 70)

                Text("Submitted recently")
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Developer response placeholder that follows the feedback.")
                    Text("A second line of response content.")
                }
                HStack {
                    Text("Developer reply")
                    Spacer()
                    Text("Recently")
                }
                .font(.caption)

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Visitor follow-up placeholder in the conversation timeline.")
                    Text("Additional follow-up content.")
                }
                HStack {
                    Text("Your message")
                    Spacer()
                    Text("Recently")
                }
                .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, style.pagePadding)
            .padding(.bottom, 24)
        }
    }
}
