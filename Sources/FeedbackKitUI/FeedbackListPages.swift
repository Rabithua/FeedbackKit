import FeedbackKitCore
import Observation
import SwiftUI

@MainActor @Observable
private final class ActivityListModel {
    var entries: [FeedbackActivityEntry] = []
    var nextCursor: String?
    var isLoading = false
    var isLoadingMore = false
    var error: Error?
    let client: FeedbackClient

    init(client: FeedbackClient) { self.client = client }

    func load(locale: Locale, refresh: Bool = false) async {
        if isLoading { return }
        isLoading = true; error = nil
        defer { isLoading = false }
        do {
            let page = try await client.activity(locale: locale, cursor: refresh ? nil : nil)
            entries = page.entries; nextCursor = page.nextCursor
        } catch is CancellationError {} catch { self.error = error }
    }

    func more(locale: Locale) async {
        guard let nextCursor, isLoadingMore == false else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await client.activity(locale: locale, cursor: nextCursor)
            entries.append(contentsOf: page.entries.filter { next in entries.contains(where: { $0.id == next.id }) == false })
            self.nextCursor = page.nextCursor
        } catch { self.error = error }
    }

    func optimisticVote(id: String, target: Bool) async {
        guard let index = entries.firstIndex(where: { $0.id == id }), let vote = entries[index].vote else { return }
        entries[index] = entries[index].updatingVote(.init(feedbackId: id, hasVoted: target, voteCount: max(0, vote.count + (target ? 1 : -1))))
        do { entries[index] = entries[index].updatingVote(try await client.setVote(feedbackID: id, voted: target)) }
        catch { entries[index] = entries[index].updatingVote(.init(feedbackId: id, hasVoted: !target, voteCount: vote.count)) }
    }
}

struct FeedbackActivityListView: View {
    @State private var model: ActivityListModel
    let style: FeedbackStyle
    let open: (FeedbackCenterSheet) -> Void
    let activatePost: (FeedbackDeveloperPostAction) -> Void
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL

    init(client: FeedbackClient, style: FeedbackStyle, open: @escaping (FeedbackCenterSheet) -> Void, activatePost: @escaping (FeedbackDeveloperPostAction) -> Void) {
        _model = State(initialValue: ActivityListModel(client: client)); self.style = style; self.open = open; self.activatePost = activatePost
    }

    var body: some View {
        Group {
            if model.entries.isEmpty, model.isLoading { FeedbackSkeletonView(layout: .list, style: style) }
            else if model.entries.isEmpty, let error = model.error { FeedbackErrorView(error: error) { Task { await model.load(locale: locale, refresh: true) } } }
            else if model.entries.isEmpty { ContentUnavailableView(FK.text("feedbackkit.activity.empty"), systemImage: "text.bubble") }
            else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(model.entries) { entry in
                            FeedbackActivityRow(
                                entry: entry,
                                style: style,
                                open: { open(entry.sheet) },
                                vote: { id, target in Task { await model.optimisticVote(id: id, target: target) } },
                                activatePost: activatePost
                            )
                            .onAppear { if entry.id == model.entries.last?.id { Task { await model.more(locale: locale) } } }
                        }
                        if model.isLoadingMore { ProgressView().padding() }
                    }.padding(style.pagePadding)
                }.refreshable { await model.load(locale: locale, refresh: true) }
            }
        }
        .background(FeedbackSystemBackground())
        .navigationTitle(FK.text("feedbackkit.activity.title"))
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

    func load(refresh: Bool = false) async {
        guard isLoading == false else { return }
        isLoading = true; error = nil; defer { isLoading = false }
        do { let page = try await client.ownedFeedback(); items = page.feedback; nextCursor = page.nextCursor }
        catch is CancellationError {} catch { self.error = error }
    }

    func more() async {
        guard let nextCursor, isLoadingMore == false else { return }
        isLoadingMore = true; defer { isLoadingMore = false }
        do {
            let page = try await client.ownedFeedback(cursor: nextCursor)
            items.append(contentsOf: page.feedback.filter { next in items.contains(where: { $0.id == next.id }) == false })
            self.nextCursor = page.nextCursor
        } catch { self.error = error }
    }
}

struct MyFeedbackView: View {
    @State private var model: MyFeedbackModel
    let style: FeedbackStyle
    let open: (String) -> Void

    init(client: FeedbackClient, style: FeedbackStyle, open: @escaping (String) -> Void) {
        _model = State(initialValue: MyFeedbackModel(client: client)); self.style = style; self.open = open
    }

    var body: some View {
        Group {
            if model.items.isEmpty, model.isLoading { FeedbackSkeletonView(layout: .list, style: style) }
            else if model.items.isEmpty, let error = model.error { FeedbackErrorView(error: error) { Task { await model.load(refresh: true) } } }
            else if model.items.isEmpty { ContentUnavailableView(FK.text("feedbackkit.mine.empty"), systemImage: "bubble.left") }
            else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(model.items) { feedback in
                            Button { open(feedback.id) } label: {
                                HStack(alignment: .center, spacing: 10) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 7) {
                                            Text(FK.kind(feedback.type)).font(.headline)
                                            Text("|").foregroundStyle(.secondary)
                                            Text(feedback.displayTitle).font(.headline).lineLimit(1)
                                        }
                                        Text(feedback.body).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                    Spacer(minLength: 4)
                                    VStack(alignment: .trailing, spacing: 3) {
                                        Text(FK.status(feedback.status)).font(.caption)
                                        Text(feedback.lastActivityAt.feedbackRelativeText).font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 14).padding(.vertical, 10).feedbackBorder(style)
                            }
                            .buttonStyle(.plain)
                            .onAppear { if feedback.id == model.items.last?.id { Task { await model.more() } } }
                        }
                        if model.isLoadingMore { ProgressView().padding() }
                    }.padding(style.pagePadding)
                }.refreshable { await model.load(refresh: true) }
            }
        }
        .background(FeedbackSystemBackground())
        .navigationTitle(FK.text("feedbackkit.mine.title"))
        .feedbackInlineNavigationTitle()
        .task { if model.items.isEmpty { await model.load() } }
    }
}

struct FeedbackRoadmapView: View {
    let items: [FeedbackRoadmapItem]
    let style: FeedbackStyle

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                ForEach(RoadmapStage.allCases) { stage in
                    HStack(alignment: .top, spacing: 14) {
                        Text(FK.stage(stage))
                            .font(stage == .undecided ? .system(size: 18, weight: .black) : .system(size: 30, weight: .black))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .frame(width: 82, height: 82)
                            .background(stage.feedbackColor)
                        VStack(alignment: .leading, spacing: 12) {
                            let staged = items.filter { $0.roadmapStage == stage && $0.archivedAt == nil }
                            if staged.isEmpty { Text(FK.text("feedbackkit.roadmap.empty.stage")).foregroundStyle(.secondary) }
                            else {
                                ForEach(staged) { item in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.title)
                                            .font(.headline)
                                        if item.body.isEmpty == false {
                                            Text(item.body)
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }.padding(style.pagePadding)
        }
        .background(FeedbackSystemBackground())
        .navigationTitle(FK.text("feedbackkit.roadmap.title"))
        .feedbackInlineNavigationTitle()
    }
}

@MainActor @Observable
private final class ReleaseModel {
    var releases: [FeedbackRelease]
    var isLoading = false
    var error: Error?
    let client: FeedbackClient
    init(client: FeedbackClient, initial: [FeedbackRelease]) { self.client = client; releases = initial.sorted(by: FeedbackRelease.versionDescending) }
    func load(locale: Locale) async {
        isLoading = true; defer { isLoading = false }
        do { releases = try await client.releases(locale: locale).sorted(by: FeedbackRelease.versionDescending); error = nil }
        catch { self.error = error }
    }
}

struct FeedbackReleaseView: View {
    @State private var model: ReleaseModel
    let style: FeedbackStyle
    @Environment(\.locale) private var locale
    private let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""

    init(client: FeedbackClient, initial: [FeedbackRelease], style: FeedbackStyle) {
        _model = State(initialValue: ReleaseModel(client: client, initial: initial)); self.style = style
    }

    var body: some View {
        Group {
            if model.releases.isEmpty, model.isLoading { FeedbackSkeletonView(layout: .releases, style: style) }
            else if model.releases.isEmpty, let error = model.error { FeedbackErrorView(error: error) { Task { await model.load(locale: locale) } } }
            else {
                ScrollView {
                    HStack(alignment: .top, spacing: 8) {
                        FeedbackReleaseRail().frame(width: 28)
                        LazyVStack(alignment: .leading, spacing: 30) {
                            ForEach(model.releases) { release in
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                                        Text("v\(release.normalizedVersion)").font(.title2.weight(.black)).foregroundStyle(.tint)
                                        if release.normalizedVersion == normalizedCurrent { Text(FK.text("feedbackkit.release.current")).font(.headline).foregroundStyle(.tint) }
                                    }
                                    if release.title.isEmpty == false, release.title != release.version { Text(release.title).font(.headline) }
                                    if release.body.isEmpty == false {
                                        Text(release.body)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .textSelection(.enabled)
                                    }
                                    if release.items.isEmpty == false {
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
                                    }
                                    Text(release.releasedAt.feedbackRelativeText).font(.caption).foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .trailing)
                                }
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(style.pagePadding)
                }.refreshable { await model.load(locale: locale) }
            }
        }
        .background(FeedbackSystemBackground())
        .navigationTitle(FK.text("feedbackkit.releases.title"))
        .feedbackInlineNavigationTitle()
        .task { await model.load(locale: locale) }
    }

    private var normalizedCurrent: String { currentVersion.lowercased().hasPrefix("v") ? String(currentVersion.dropFirst()) : currentVersion }
}

private extension RoadmapStage {
    var feedbackColor: Color {
        switch self {
        case .urgent: .red
        case .later: .accentColor
        case .undecided: .gray
        }
    }
}

private struct FeedbackReleaseRail: View {
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let center = proxy.size.width / 2
                path.move(to: CGPoint(x: center - 10, y: 17)); path.addLine(to: CGPoint(x: center, y: 5)); path.addLine(to: CGPoint(x: center + 10, y: 17))
                path.move(to: CGPoint(x: center, y: 5))
                var y: CGFloat = 5; var direction: CGFloat = 1
                while y < proxy.size.height {
                    y += 15; path.addLine(to: CGPoint(x: center + direction * 3, y: min(y, proxy.size.height))); direction *= -1
                }
            }
            .stroke(Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
        }
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
