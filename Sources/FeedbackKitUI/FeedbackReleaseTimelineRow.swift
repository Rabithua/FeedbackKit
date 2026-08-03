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

            if release.body.isEmpty == false {
                Text(release.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            ForEach(release.items) { item in
                VStack(alignment: .leading, spacing: 3) {
                    Text("• \(item.title)")
                    if item.body.isEmpty == false {
                        Text(item.body)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 14)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }

            Text(release.releasedAt.feedbackRelativeText)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
