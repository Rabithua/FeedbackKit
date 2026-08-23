import FeedbackKitCore
import SwiftUI

struct FeedbackActivityListView: View {
    @State private var model: FeedbackActivityListModel
    let style: FeedbackStyle
    let open: (FeedbackCenterSheet) -> Void
    let activatePost: (FeedbackDeveloperPostAction) -> Void
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL
    @Environment(\.feedbackHaptics) private var haptics
    @Environment(\.feedbackLocalization) private var localization

    init(client: FeedbackClient, style: FeedbackStyle, open: @escaping (FeedbackCenterSheet) -> Void, activatePost: @escaping (FeedbackDeveloperPostAction) -> Void) {
        _model = State(initialValue: FeedbackActivityListModel(client: client)); self.style = style; self.open = open; self.activatePost = activatePost
    }

    var body: some View {
        Group {
            if model.entries.isEmpty, model.isLoading { FeedbackSkeletonView(layout: .list, style: style) }
            else if model.entries.isEmpty, let error = model.error { FeedbackErrorView(error: error) { Task { await model.load(locale: locale, refresh: true) } } }
            else if model.entries.isEmpty { ContentUnavailableView(localization.text("feedbackkit.activity.empty"), systemImage: "text.bubble") }
            else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(model.entries) { entry in
                            FeedbackActivityRow(
                                entry: entry,
                                style: style,
                                open: { open(entry.sheet) },
                                vote: { id, target in
                                    haptics.trigger(.selection)
                                    Task {
                                        if await model.optimisticVote(id: id, target: target) == false {
                                            haptics.trigger(.error)
                                        }
                                    }
                                },
                                isVoting: model.isVoting(feedbackID: entry.id),
                                activatePost: activatePost
                            )
                            .task {
                                if entry.id == model.entries.last?.id {
                                    await model.more(locale: locale)
                                }
                            }
                        }
                        if model.isLoadingMore { ProgressView().padding() }
                    }.padding(style.pagePadding)
                }.refreshable { await model.load(locale: locale, refresh: true) }
            }
        }
        .background(FeedbackSystemBackground())
        .navigationTitle(localization.text("feedbackkit.activity.title"))
        .feedbackInlineNavigationTitle()
        .task { if model.entries.isEmpty { await model.load(locale: locale) } }
    }

}

private extension FeedbackActivityEntry {
    var sheet: FeedbackCenterSheet {
        switch self {
        case .feedback: .feedback(id)
        case .developerPost: .developerPost(id)
        }
    }
}

@MainActor @Observable
private final class MyFeedbackModel {
    var items: [OwnedFeedbackSummary] = []
    var nextCursor: String?
    var isLoading = false
    var isLoadingMore = false
    var error: Error?
    let client: FeedbackClient
    init(client: FeedbackClient) { self.client = client }

    func load(refresh _: Bool = false) async {
        guard isLoading == false, isLoadingMore == false else { return }
        isLoading = true; error = nil; defer { isLoading = false }
        do { let page = try await client.ownedFeedback(); items = page.feedback; nextCursor = page.nextCursor }
        catch is CancellationError {} catch { self.error = error }
    }

    func more() async {
        guard let nextCursor,
              isLoading == false,
              isLoadingMore == false
        else { return }
        isLoadingMore = true; defer { isLoadingMore = false }
        do {
            let page = try await client.ownedFeedback(cursor: nextCursor)
            items.append(contentsOf: page.feedback.filter { next in items.contains(where: { $0.id == next.id }) == false })
            self.nextCursor = page.nextCursor
        } catch is CancellationError {
        } catch {
            self.error = error
        }
    }
}

struct MyFeedbackView: View {
    @State private var model: MyFeedbackModel
    let style: FeedbackStyle
    let open: (String) -> Void
    @Environment(\.locale) private var locale
    @Environment(\.feedbackLocalization) private var localization

    init(client: FeedbackClient, style: FeedbackStyle, open: @escaping (String) -> Void) {
        _model = State(initialValue: MyFeedbackModel(client: client)); self.style = style; self.open = open
    }

    var body: some View {
        Group {
            if model.items.isEmpty, model.isLoading { FeedbackSkeletonView(layout: .list, style: style) }
            else if model.items.isEmpty, let error = model.error { FeedbackErrorView(error: error) { Task { await model.load(refresh: true) } } }
            else if model.items.isEmpty { ContentUnavailableView(localization.text("feedbackkit.mine.empty"), systemImage: "bubble.left") }
            else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(model.items) { feedback in
                            Button { open(feedback.id) } label: {
                                HStack(alignment: .center, spacing: 10) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 7) {
                                            Text(localization.kind(feedback.type))
                                                .font(.headline)
                                                .lineLimit(1)
                                                .truncationMode(.tail)
                                            Text("|").foregroundStyle(.secondary)
                                            Text(feedback.displayTitle).font(.headline).lineLimit(1)
                                        }
                                        Text(feedback.body).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                    Spacer(minLength: 4)
                                    VStack(alignment: .trailing, spacing: 3) {
                                        Text(localization.status(feedback.status)).font(.caption)
                                        Text(feedback.lastActivityAt.feedbackRelativeText(locale: locale)).font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .contentShape(.interaction, FeedbackComponentShape(cornerRadius: style.cardCornerRadius))
                                .feedbackBorder(style)
                            }
                            .buttonStyle(.plain)
                            .task {
                                if feedback.id == model.items.last?.id {
                                    await model.more()
                                }
                            }
                        }
                        if model.isLoadingMore { ProgressView().padding() }
                    }.padding(style.pagePadding)
                }.refreshable { await model.load(refresh: true) }
            }
        }
        .background(FeedbackSystemBackground())
        .navigationTitle(localization.text("feedbackkit.mine.title"))
        .feedbackInlineNavigationTitle()
        .task { if model.items.isEmpty { await model.load() } }
    }
}

struct FeedbackSystemBackground: View {
    var body: some View {
        #if os(iOS)
        Color(uiColor: .systemBackground).ignoresSafeArea()
        #else
        Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
        #endif
    }
}
