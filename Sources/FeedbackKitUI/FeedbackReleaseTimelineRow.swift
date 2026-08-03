import FeedbackKitCore
import SwiftUI

struct FeedbackReleaseTimelineRow: View {
    let release: FeedbackRelease
    let isCurrent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("v\(release.normalizedVersion)")
                    .font(.title2.weight(.black))
                    .foregroundStyle(.tint)

                if isCurrent {
                    Text(FK.text("feedbackkit.release.current"))
                        .font(.headline)
                        .foregroundStyle(.tint)
                }
            }

            if release.title.isEmpty == false, release.title != release.version {
                Text(release.title)
                    .font(.headline)
            }

            FeedbackReleaseBodyText(text: release.body)

            ForEach(release.items) { item in
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: "• \(item.title)")
                    if item.body.isEmpty == false {
                        Text(verbatim: item.body)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 14)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(release.releasedAt.feedbackRelativeText)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
