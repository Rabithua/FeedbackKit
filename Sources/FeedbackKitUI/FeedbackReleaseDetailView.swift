import FeedbackKitCore
import SwiftUI

struct FeedbackReleaseDetailView: View {
    @State private var model: FeedbackReleaseDetailModel
    @Environment(\.locale) private var locale

    let style: FeedbackStyle

    private let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""

    init(client: FeedbackClient, id: String, initial: FeedbackRelease?, style: FeedbackStyle) {
        _model = State(initialValue: FeedbackReleaseDetailModel(client: client, id: id, initial: initial))
        self.style = style
    }

    var body: some View {
        Group {
            if let release = model.release {
                ScrollView {
                    FeedbackReleaseDetailContent(
                        release: release,
                        isCurrent: release.normalizedVersion == normalizedCurrent,
                        isRefreshing: model.isLoading,
                        refreshError: model.error,
                        retry: retry
                    )
                    .padding(style.pagePadding)
                }
                .refreshable { await model.load(locale: locale) }
            } else if model.isLoading {
                FeedbackSkeletonView(layout: .releases, style: style)
            } else if let error = model.error {
                FeedbackErrorView(error: error, retry: retry)
            }
        }
        .background(FeedbackSystemBackground())
        .navigationTitle(navigationTitle)
        .feedbackInlineNavigationTitle()
        .accessibilityIdentifier("developerCommunity.releaseDetail")
        .task(id: locale.identifier) { await model.load(locale: locale) }
    }

    private var normalizedCurrent: String {
        currentVersion.lowercased().hasPrefix("v") ? String(currentVersion.dropFirst()) : currentVersion
    }

    private var navigationTitle: String {
        guard let release = model.release else { return FK.text("feedbackkit.release.detail.title") }
        return "v\(release.normalizedVersion)"
    }

    private func retry() {
        Task { await model.load(locale: locale) }
    }
}
