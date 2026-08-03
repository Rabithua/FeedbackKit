import FeedbackKitCore
import Foundation
import SwiftUI

struct FeedbackReleaseDetailContent: View {
    let release: FeedbackRelease
    let isCurrent: Bool
    let isRefreshing: Bool
    let refreshError: Error?
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("v\(release.normalizedVersion)")
                    .font(.title.weight(.black))
                    .foregroundStyle(.tint)

                if isCurrent {
                    Text(FK.text("feedbackkit.release.current"))
                        .font(.headline)
                        .foregroundStyle(.tint)
                }
            }

            if release.title.isEmpty == false, release.title != release.version {
                Text(release.title)
                    .font(.title3.weight(.semibold))
            }

            if release.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(FK.text("feedbackkit.release.body.empty"))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("developerCommunity.releaseDetail.emptyBody")
            } else {
                Text(release.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("developerCommunity.releaseDetail.body")
            }

            if release.items.isEmpty == false {
                Divider()

                Text(FK.text("feedbackkit.release.items.title"))
                    .font(.headline)

                ForEach(release.items) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("• \(item.title)")
                            .font(.body.weight(.semibold))
                        if item.body.isEmpty == false {
                            Text(item.body)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 14)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text("\(FK.text("feedbackkit.release.released")) \(release.releasedAt.feedbackRelativeText)")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityIdentifier("developerCommunity.releaseDetail.date")

            if isRefreshing {
                ProgressView(FK.text("feedbackkit.loading"))
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
            } else if let refreshError {
                VStack(alignment: .leading, spacing: 8) {
                    Text(refreshError.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(FK.text("feedbackkit.retry"), action: retry)
                        .accessibilityIdentifier("developerCommunity.releaseDetail.retry")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
