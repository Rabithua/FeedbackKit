import FeedbackKitCore
import SwiftUI

struct FeedbackHubView: View {
    let bootstrap: FeedbackBootstrap
    let style: FeedbackStyle
    let openPage: (FeedbackCenterPage) -> Void
    let openSheet: (FeedbackCenterSheet) -> Void
    let vote: (String, Bool) -> Void
    let refresh: () async -> Void
    let dismiss: () -> Void
    let activatePost: (FeedbackDeveloperPostAction) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                LazyVStack(alignment: .leading, spacing: style.sectionSpacing) {
                    cards
                    activity
                    Button(FK.text("feedbackkit.speak")) { openSheet(.kinds) }
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .feedbackBorder(style)
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("developerCommunity.newFeedback")
                }
                .padding(.horizontal, style.pagePadding)
                .padding(.bottom, 20)
            }
            .refreshable { await refresh() }
        }
        .accessibilityIdentifier("developerCommunity.hub")
    }

    private var header: some View {
        HStack(spacing: 4) {
            Menu {
                Button(FK.text("feedbackkit.identity.title")) { openPage(.identity) }
                Button(FK.text("feedbackkit.diagnostics.title")) { openPage(.diagnostics) }
            } label: {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.title3.weight(.semibold))
                    .frame(width: 34, height: 36)
            }
            .buttonStyle(.plain)
            Text(FK.text("feedbackkit.center.title"))
                .font(.title2.bold())
            Spacer(minLength: 8)
            FeedbackCloseButton(action: dismiss)
        }
        .padding(.horizontal, style.pagePadding)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private var cards: some View {
        HStack(spacing: 12) {
            hubButton(FK.text("feedbackkit.mine.title"), identifier: "developerCommunity.hubCard.mine", badge: unreadCount) { openPage(.mine) }
                .aspectRatio(1, contentMode: .fit)
            VStack(spacing: 12) {
                hubButton(FK.text("feedbackkit.roadmap.title"), identifier: "developerCommunity.hubCard.roadmap") { openPage(.roadmap) }
                hubButton(FK.text("feedbackkit.releases.title"), identifier: "developerCommunity.hubCard.releases") { openPage(.releases) }
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
                }
            }
            .frame(minHeight: 72)
            .feedbackBorder(style)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private var activity: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(FK.text("feedbackkit.activity.title")).font(.headline)
                Spacer()
                Button(FK.text("feedbackkit.all")) { openPage(.activity) }.font(.subheadline)
            }
            if bootstrap.activity.entries.isEmpty {
                Text(FK.text("feedbackkit.activity.empty")).foregroundStyle(.secondary)
            } else {
                ForEach(bootstrap.activity.entries.prefix(5)) { entry in
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
                }
            }
        }
    }

    private var unreadCount: Int {
        max(0, bootstrap.inbox.nextCursor - bootstrap.inbox.acknowledgedCursor)
    }
}

struct FeedbackActivityRow: View {
    let entry: FeedbackActivityEntry
    let style: FeedbackStyle
    let open: () -> Void
    let vote: (String, Bool) -> Void
    let activatePost: (FeedbackDeveloperPostAction) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(category).font(.headline)
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
                }
                .buttonStyle(.plain)
                .accessibilityLabel(FK.text(voteState.hasVoted ? "feedbackkit.vote.remove" : "feedbackkit.vote"))
            } else if case let .developerPost(_, data) = entry, let action = data.action {
                Button { activatePost(action) } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 25, weight: .bold))
                        .frame(minWidth: 48, minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
            }
        }
        .overlay(alignment: .topTrailing) {
            if entry.metadata.pinnedAt != nil {
                Text(FK.text("feedbackkit.pinned"))
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
        case let .feedback(_, data): FK.kind(data.type)
        case .developerPost: FK.text("feedbackkit.developer.post")
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
