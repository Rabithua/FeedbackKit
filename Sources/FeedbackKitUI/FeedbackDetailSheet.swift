import FeedbackKitCore
import SwiftUI

struct FeedbackDetailSheet: View {
    @State private var model: FeedbackDetailModel
    let style: FeedbackStyle
    let viewed: () async -> Void
    let close: () -> Void
    @Environment(\.feedbackHaptics) private var haptics
    @Environment(\.locale) private var locale
    @Environment(\.feedbackLocalization) private var localization

    init(
        id: String,
        client: FeedbackClient,
        style: FeedbackStyle,
        voteChanged: @escaping (FeedbackVoteResult) -> Void,
        viewed: @escaping () async -> Void,
        close: @escaping () -> Void
    ) {
        _model = State(initialValue: FeedbackDetailModel(
            id: id,
            client: client,
            voteChanged: voteChanged
        ))
        self.style = style
        self.viewed = viewed
        self.close = close
    }

    var body: some View {
        VStack(spacing: 0) {
            FeedbackSheetHeader(
                title: model.detail.map {
                    "\(localization.kind($0.type))（\(localization.status($0.status))）"
                } ?? ""
            ) {
                if let detail = model.detail, detail.isPublic {
                    FeedbackHitTargetButton {
                        haptics.trigger(.selection)
                        Task {
                            if await model.vote() == false {
                                haptics.trigger(.error)
                            }
                        }
                    } label: {
                        Text("+\(detail.voteCount)")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundStyle(detail.hasVoted ? Color.accentColor : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isVoting || model.isLoading)
                }
            } close: {
                close()
            }
            .padding(.horizontal, style.pagePadding)
            .padding(.top, 14)
            .padding(.bottom, 8)

            Group {
                if let detail = model.detail {
                    content(detail)
                } else if model.isLoading {
                    FeedbackSkeletonView(layout: .feedbackDetail, style: style)
                } else if let error = model.error {
                    FeedbackErrorView(error: error) {
                        Task { await load() }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .presentationDetents([.medium])
        .task { await load() }
        .accessibilityIdentifier("developerCommunity.feedbackDetail")
    }

    private func load() async {
        if await model.load() {
            await viewed()
        }
    }

    private func content(_ detail: FeedbackDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let title = detail.title, title.isEmpty == false {
                    Text(title)
                        .font(.title3)
                }

                FeedbackSelectableText(detail.body)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if detail.attachments.isEmpty == false {
                    Text(localization.text("feedbackkit.attachments"))
                        .font(.headline)
                    ForEach(detail.attachments) {
                        Text($0.filename)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(detail.createdAt.feedbackRelativeText(locale: locale))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                ForEach(detail.messages.sorted { $0.createdAt < $1.createdAt }) { message in
                    Divider()
                    FeedbackSelectableText(message.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack {
                        Text(
                            message.actor == "visitor"
                                ? localization.text("feedbackkit.visitor.message")
                                : localization.text("feedbackkit.developer.reply")
                        )
                        Spacer()
                        Text(message.createdAt.feedbackRelativeText(locale: locale))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if detail.isOwner, detail.status == .open {
                    replyComposer
                } else if detail.isOwner {
                    Text(localization.text("feedbackkit.reply.closed"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if detail.diagnosticsIncluded == true {
                    Label(
                        localization.text("feedbackkit.diagnostics.included"),
                        systemImage: "lock.shield"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, style.pagePadding)
            .padding(.bottom, 24)
        }
        .refreshable { await load() }
    }

    private var replyComposer: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(
                "",
                text: $model.replyBody,
                prompt: Text(localization.text("feedbackkit.reply.placeholder"))
                    .foregroundStyle(.secondary),
                axis: .vertical
            )
            .lineLimit(2...6)
            .padding(14)
            .feedbackBorder(style)
            .accessibilityLabel(localization.text("feedbackkit.reply.placeholder"))

            Button {
                Task {
                    let didReply = await model.reply(localization: localization)
                    haptics.trigger(didReply ? .success : .error)
                }
            } label: {
                Text(localization.text("feedbackkit.reply.send"))
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .contentShape(.interaction, FeedbackComponentShape(cornerRadius: style.cardCornerRadius))
                    .feedbackBorder(style)
            }
            .buttonStyle(.plain)
            .disabled(
                model.replyBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || model.isReplying
            )

            if let replyError = model.replyError {
                Text(replyError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(.top, 4)
    }
}
