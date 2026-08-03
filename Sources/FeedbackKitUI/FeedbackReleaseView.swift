import FeedbackKitCore
import SwiftUI

struct FeedbackReleaseView: View {
    @State private var model: FeedbackReleaseListModel
    @Environment(\.locale) private var locale

    let style: FeedbackStyle

    private let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""

    init(client: FeedbackClient, initial: [FeedbackRelease], style: FeedbackStyle) {
        _model = State(initialValue: FeedbackReleaseListModel(client: client, initial: initial))
        self.style = style
    }

    var body: some View {
        Group {
            if model.releases.isEmpty, model.isLoading {
                FeedbackSkeletonView(layout: .releases, style: style)
            } else if model.releases.isEmpty, let error = model.error {
                FeedbackErrorView(error: error, retry: retry)
            } else if model.releases.isEmpty {
                ContentUnavailableView(FK.text("feedbackkit.releases.empty"), systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 30) {
                        ForEach(model.releases) { release in
                            FeedbackReleaseTimelineRow(
                                release: release,
                                isCurrent: release.normalizedVersion == normalizedCurrent
                            )
                            .id(release)
                            .accessibilityIdentifier("developerCommunity.release.\(release.normalizedVersion)")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 36)
                    .overlay(alignment: .leading) {
                        FeedbackReleaseRail()
                            .frame(width: 28)
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(style.pagePadding)
                }
                .refreshable { await model.load(locale: locale) }
            }
        }
        .background(FeedbackSystemBackground())
        .navigationTitle(FK.text("feedbackkit.releases.title"))
        .feedbackInlineNavigationTitle()
        .task(id: locale.identifier) { await model.load(locale: locale) }
    }

    private var normalizedCurrent: String {
        currentVersion.lowercased().hasPrefix("v") ? String(currentVersion.dropFirst()) : currentVersion
    }

    private func retry() {
        Task { await model.load(locale: locale) }
    }
}
