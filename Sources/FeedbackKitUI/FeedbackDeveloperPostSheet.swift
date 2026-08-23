import FeedbackKitCore
import SwiftUI

struct FeedbackDeveloperPostSheet: View {
    @State private var model: FeedbackDeveloperPostModel
    let style: FeedbackStyle
    let activate: (FeedbackDeveloperPostAction) -> Void
    let close: () -> Void
    @Environment(\.locale) private var locale
    @Environment(\.feedbackLocalization) private var localization

    init(
        id: String,
        client: FeedbackClient,
        style: FeedbackStyle,
        activate: @escaping (FeedbackDeveloperPostAction) -> Void,
        close: @escaping () -> Void
    ) {
        _model = State(initialValue: FeedbackDeveloperPostModel(id: id, client: client))
        self.style = style
        self.activate = activate
        self.close = close
    }

    var body: some View {
        VStack(spacing: 0) {
            FeedbackSheetHeader(
                title: localization.text("feedbackkit.developer.post"),
                close: close
            )
            .padding(.horizontal, style.pagePadding)
            .padding(.top, 14)
            .padding(.bottom, 8)

            Group {
                if let post = model.post {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(post.title)
                                .font(.title2.bold())
                            Text(post.body)
                                .textSelection(.enabled)

                            if let action = post.action {
                                Button {
                                    activate(action)
                                } label: {
                                    HStack {
                                        Text(action.label ?? localization.text("feedbackkit.open.link"))
                                        Spacer()
                                        Image(systemName: "arrow.up.right")
                                            .font(.system(size: 25, weight: .bold))
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 52)
                                    .padding(.horizontal, 14)
                                    .contentShape(
                                        .interaction,
                                        FeedbackComponentShape(cornerRadius: style.cardCornerRadius)
                                    )
                                    .feedbackBorder(style)
                                }
                                .buttonStyle(.plain)
                            }

                            if let published = post.publishedAt {
                                Text(published.feedbackRelativeText(locale: locale))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                        }
                        .padding(.horizontal, style.pagePadding)
                        .padding(.bottom, 24)
                    }
                } else if model.isLoading {
                    FeedbackSkeletonView(layout: .developerPostDetail, style: style)
                } else if let error = model.error {
                    FeedbackErrorView(error: error) {
                        Task { await model.load(locale: locale) }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .presentationDetents([.medium])
        .task(id: locale.identifier) {
            await model.load(locale: locale)
        }
    }
}
