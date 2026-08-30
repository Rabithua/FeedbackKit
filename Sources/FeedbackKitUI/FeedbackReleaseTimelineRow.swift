import FeedbackKitCore
import SwiftUI

struct FeedbackReleaseTimelineRow: View {
    let release: FeedbackRelease
    let isCurrent: Bool
    @Environment(\.locale) private var locale
    @Environment(\.feedbackLocalization) private var localization

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("v\(release.normalizedVersion)")
                    .font(.title2.weight(.black))
                    .foregroundStyle(.tint)

                if isCurrent {
                    Text(localization.text("feedbackkit.release.current"))
                        .font(.headline)
                        .foregroundStyle(.tint)
                }
            }

            if release.body.isEmpty == false {
                FeedbackSelectableText(release.body, style: .secondaryBody)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
            }

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

            Text(release.releasedAt.feedbackRelativeText(locale: locale))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(
            children: FeedbackTextLinkDetector.links(in: release.body).isEmpty
                ? .combine
                : .contain
        )
    }
}
