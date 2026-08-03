import SwiftUI

struct FeedbackSkeletonRows: View {
    let style: FeedbackStyle
    let count: Int

    var body: some View {
        LazyVStack(spacing: 10) {
            ForEach(0 ..< count, id: \.self) { index in
                VStack(alignment: .leading, spacing: 6) {
                    Text(index.isMultiple(of: 2) ? "Category | Feedback title" : "Category | A longer feedback title")
                        .font(.headline)
                        .lineLimit(1)
                    Text("Feedback summary placeholder that can occupy more than one line.")
                        .font(.subheadline)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .feedbackBorder(style)
            }
        }
    }
}
