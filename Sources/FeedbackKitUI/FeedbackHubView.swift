import FeedbackKitCore
import SwiftUI

struct FeedbackHubView: View {
    let bootstrap: FeedbackBootstrap
    let style: FeedbackStyle
    let openPage: (FeedbackCenterPage) -> Void
    let openSheet: (FeedbackCenterSheet) -> Void
    let vote: (String, Bool) -> Void
    let refresh: () async -> Void
    let activatePost: (FeedbackDeveloperPostAction) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.feedbackLocalization) private var localization
    @State private var isContentVisible = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: style.sectionSpacing) {
                cards
                activity
            }
            .padding(.horizontal, style.pagePadding)
            .padding(.bottom, 20)
        }
        .refreshable { await refresh() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(action: { openSheet(.kinds) }) {
                Text(localization.text("feedbackkit.speak"))
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .contentShape(Rectangle())
                    .feedbackBorder(style)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("developerCommunity.newFeedback")
            .padding(.horizontal, style.pagePadding)
            .padding(.vertical, 8)
            .background(FeedbackSystemBackground())
            .feedbackEntrance(isVisible: isContentVisible, order: 10, reduceMotion: reduceMotion)
        }
        .accessibilityIdentifier("developerCommunity.hub")
        .task { await revealContent() }
    }

    private var cards: some View {
        HStack(spacing: 12) {
            hubButton(localization.text("feedbackkit.mine.title"), identifier: "developerCommunity.hubCard.mine", badge: unreadCount) { openPage(.mine) }
                .aspectRatio(1, contentMode: .fit)
                .feedbackEntrance(isVisible: isContentVisible, order: 1, reduceMotion: reduceMotion)
            VStack(spacing: 12) {
                hubButton(localization.text("feedbackkit.roadmap.title"), identifier: "developerCommunity.hubCard.roadmap") { openPage(.roadmap) }
                    .feedbackEntrance(isVisible: isContentVisible, order: 2, reduceMotion: reduceMotion)
                hubButton(localization.text("feedbackkit.releases.title"), identifier: "developerCommunity.hubCard.releases") { openPage(.releases) }
                    .feedbackEntrance(isVisible: isContentVisible, order: 3, reduceMotion: reduceMotion)
            }
        }
    }

    private func hubButton(_ title: String, identifier: String, badge: Int = 0, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Text(title)
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if badge > 0 {
                    Text("\(badge)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(.tint, in: Circle())
                        .padding(8)
                        .accessibilityIdentifier("developerCommunity.hubCard.mine.badge")
                }
            }
            .frame(minHeight: 72)
            .contentShape(.interaction, FeedbackComponentShape(cornerRadius: style.cardCornerRadius))
            .feedbackBorder(style)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private var activity: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(localization.text("feedbackkit.activity.title")).font(.headline)
                Spacer()
                Button(localization.text("feedbackkit.all")) { openPage(.activity) }.font(.subheadline)
            }
            .feedbackEntrance(isVisible: isContentVisible, order: 4, reduceMotion: reduceMotion)
            if bootstrap.activity.entries.isEmpty {
                Text(localization.text("feedbackkit.activity.empty"))
                    .foregroundStyle(.secondary)
                    .feedbackEntrance(isVisible: isContentVisible, order: 5, reduceMotion: reduceMotion)
            } else {
                ForEach(Array(bootstrap.activity.entries.prefix(5).enumerated()), id: \.element.id) { index, entry in
                    FeedbackActivityRow(
                        entry: entry,
                        style: style,
                        open: {
                            switch entry {
                            case .feedback: openSheet(.feedback(entry.id))
                            case .developerPost: openSheet(.developerPost(entry.id))
                            }
                        },
                        vote: vote,
                        activatePost: activatePost
                    )
                    .feedbackEntrance(isVisible: isContentVisible, order: 5 + index, reduceMotion: reduceMotion)
                }
            }
        }
    }

    private func revealContent() async {
        guard !isContentVisible else { return }
        await Task.yield()
        guard !Task.isCancelled else { return }
        isContentVisible = true
    }

    private var unreadCount: Int {
        bootstrap.inbox.unreadCount
    }
}

struct FeedbackActivityRow: View {
    let entry: FeedbackActivityEntry
    let style: FeedbackStyle
    let open: () -> Void
    let vote: (String, Bool) -> Void
    let activatePost: (FeedbackDeveloperPostAction) -> Void
    @Environment(\.feedbackLocalization) private var localization

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(category)
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text("|").foregroundStyle(.secondary)
                        Text(title).font(.headline).lineLimit(1)
                    }
                    Text(summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let voteState = entry.vote {
                Button { vote(entry.id, !voteState.hasVoted) } label: {
                    Text("+\(voteState.count)")
                        .font(.system(size: 25, weight: .black, design: .rounded))
                        .foregroundStyle(voteState.hasVoted ? Color.accentColor : Color.primary)
                        .frame(minWidth: 48, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(localization.text(voteState.hasVoted ? "feedbackkit.vote.remove" : "feedbackkit.vote"))
            } else if case let .developerPost(_, data) = entry, let action = data.action {
                Button { activatePost(action) } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 25, weight: .bold))
                        .frame(minWidth: 48, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
            }
        }
        .overlay(alignment: .topTrailing) {
            if entry.metadata.pinnedAt != nil {
                Text(localization.text("feedbackkit.pinned"))
                    .font(.caption2.bold())
                    .offset(y: -8)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .feedbackBorder(style)
    }

    private var category: String {
        switch entry {
        case let .feedback(_, data): localization.kind(data.type)
        case .developerPost: localization.text("feedbackkit.developer.post")
        }
    }
    private var title: String {
        switch entry {
        case let .feedback(_, data): data.displayTitle
        case let .developerPost(_, data): data.title
        }
    }
    private var summary: String {
        switch entry {
        case let .feedback(_, data): data.body
        case let .developerPost(_, data): data.body
        }
    }
}
