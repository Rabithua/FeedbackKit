import FeedbackKitCore
import PhotosUI
import SwiftUI

struct FeedbackSheetHost: View {
    let sheet: FeedbackCenterSheet
    @Bindable var model: FeedbackCenterModel
    let routeHandler: any FeedbackRouteHandler
    let style: FeedbackStyle
    @Environment(\.openURL) private var openURL
    @Environment(\.feedbackHaptics) private var haptics
    @Environment(\.locale) private var locale

    var body: some View {
        Group {
            switch sheet {
            case .kinds:
                FeedbackKindPicker(style: style) { model.sheet = .composer($0) } close: { model.sheet = nil }
            case let .composer(kind):
                if let product = model.bootstrap?.product {
                    FeedbackComposer(
                        kind: kind,
                        product: product,
                        client: model.client,
                        draftStore: FeedbackDraftStore(),
                        style: style,
                        submitted: {
                            model.sheet = nil
                            Task { await model.load(locale: locale, force: true) }
                        },
                        close: { model.sheet = nil }
                    )
                }
            case let .feedback(id):
                FeedbackDetailSheet(
                    id: id,
                    client: model.client,
                    style: style,
                    voteChanged: model.synchronizeVote,
                    viewed: { await model.markFeedbackRead(feedbackID: id) }
                ) { model.sheet = nil }
            case let .developerPost(id):
                FeedbackDeveloperPostSheet(id: id, client: model.client, style: style, activate: activatePost) { model.sheet = nil }
            }
        }
        .presentationDragIndicator(.hidden)
    }

    private func activatePost(_ action: FeedbackDeveloperPostAction) {
        switch action.type {
        case .externalURL:
            guard let url = URL(string: action.target), url.scheme?.lowercased() == "https" else {
                haptics.trigger(.error)
                return
            }
            haptics.trigger(.action)
            openURL(url)
        case .appRoute:
            if model.openPackageRoute(action.target) || routeHandler.openFeedbackAppRoute(action.target) {
                haptics.trigger(.navigation)
            } else {
                haptics.trigger(.error)
            }
        }
    }
}

private struct FeedbackKindPicker: View {
    let style: FeedbackStyle
    let select: (FeedbackKind) -> Void
    let close: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.feedbackHaptics) private var haptics
    @Environment(\.feedbackLocalization) private var localization

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            FeedbackSheetHeader(title: localization.text("feedbackkit.kind.title"), close: close)
            let columns = dynamicTypeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(FeedbackKind.allCases) { kind in
                    Button {
                        haptics.trigger(.selection)
                        select(kind)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(localization.kind(kind)).font(.headline)
                            Text(kindDescription(kind)).font(.subheadline).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
                        .padding(.horizontal, 14)
                        .contentShape(.interaction, FeedbackComponentShape(cornerRadius: style.cardCornerRadius))
                        .feedbackBorder(style)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(localization.kind(kind))
                }
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, style.pagePadding)
        .padding(.top, 14)
        .presentationDetents([.medium])
        .accessibilityIdentifier("developerCommunity.kindPicker")
    }

    private func kindDescription(_ kind: FeedbackKind) -> String {
        switch kind {
        case .bug: localization.text("feedbackkit.kind.bug.description")
        case .suggestion: localization.text("feedbackkit.kind.suggestion.description")
        case .praise: localization.text("feedbackkit.kind.praise.description")
        case .conversation: localization.text("feedbackkit.kind.conversation.description")
        }
    }
}

private struct FeedbackSheetHeader<Trailing: View>: View {
    let title: String
    let trailing: Trailing
    let close: () -> Void

    init(title: String, @ViewBuilder trailing: () -> Trailing, close: @escaping () -> Void) {
        self.title = title; self.trailing = trailing(); self.close = close
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.title3.bold()).lineLimit(1)
            Spacer(minLength: 4)
            trailing
            FeedbackCloseButton(action: close)
        }
        .frame(minHeight: 36)
    }
}

private extension FeedbackSheetHeader where Trailing == EmptyView {
    init(title: String, close: @escaping () -> Void) {
        self.init(title: title, trailing: { EmptyView() }, close: close)
    }
}

private struct FeedbackComposer: View {
    @State private var model: FeedbackComposerModel
    @State private var selections: [PhotosPickerItem] = []
    @State private var confirmClose = false
    @State private var confirmCancelSubmission = false
    @State private var showsDisclosure = false
    @State private var importTask: Task<Void, Never>?
    @State private var submissionTask: Task<Void, Never>?
    @FocusState private var focused: Field?
    let style: FeedbackStyle
    let submitted: () -> Void
    let close: () -> Void
    @Environment(\.locale) private var locale
    @Environment(\.feedbackHaptics) private var haptics
    @Environment(\.feedbackLocalization) private var localization

    private enum Field { case title; case body }

    init(kind: FeedbackKind, product: FeedbackProduct, client: FeedbackClient, draftStore: FeedbackDraftStore, style: FeedbackStyle, submitted: @escaping () -> Void, close: @escaping () -> Void) {
        _model = State(initialValue: FeedbackComposerModel(kind: kind, product: product, client: client, draftStore: draftStore)); self.style = style; self.submitted = submitted; self.close = close
    }

    var body: some View {
        VStack(spacing: 0) {
            FeedbackSheetHeader(title: localization.kind(model.kind)) {
                FeedbackHitTargetButton(action: showDisclosure) {
                    Label(localization.text("feedbackkit.disclosure.title"), systemImage: "info.circle")
                        .labelStyle(.iconOnly)
                }
                .font(.system(size: 18, weight: .bold))
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("developerCommunity.composer.disclosure")
            } close: { requestClose() }
                .padding(.horizontal, style.pagePadding).padding(.top, 14).padding(.bottom, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("", text: $model.title, prompt: Text(localization.text("feedbackkit.composer.title.placeholder")).foregroundStyle(.secondary))
                        .focused($focused, equals: .title).padding(14).feedbackBorder(style)
                        .accessibilityLabel(localization.text("feedbackkit.composer.title.placeholder"))
                    ZStack(alignment: .topLeading) {
                        if model.body.isEmpty { Text(localization.text("feedbackkit.composer.body.placeholder")).foregroundStyle(.secondary).padding(.horizontal, 18).padding(.vertical, 16).allowsHitTesting(false) }
                        TextEditor(text: $model.body).focused($focused, equals: .body).scrollContentBackground(.hidden).frame(minHeight: 170).padding(10)
                            .accessibilityLabel(localization.text("feedbackkit.composer.body.placeholder"))
                    }.feedbackBorder(style)
                    attachmentStrip
                    if model.diagnosticsAvailable {
                        Toggle(isOn: diagnosticsBinding) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(localization.text("feedbackkit.diagnostics.include")).font(.headline)
                                Text(localization.text("feedbackkit.diagnostics.disclosure")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if let message = model.errorMessage { Text(message).font(.footnote).foregroundStyle(.red).accessibilityLabel(message) }
                    Button {
                        submit()
                    } label: {
                        ZStack {
                            if model.isSubmitting {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.primary)
                                    .accessibilityLabel(localization.text("feedbackkit.loading"))
                            } else {
                                Text(model.disclosedVisibility == .public ? localization.text("feedbackkit.send.public") : localization.text("feedbackkit.send"))
                                    .lineLimit(1)
                            }
                        }
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .contentShape(.interaction, FeedbackComponentShape(cornerRadius: style.cardCornerRadius))
                        .feedbackBorder(style)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.canSubmit == false)
                }
                .disabled(model.isSubmitting)
                .padding(.horizontal, style.pagePadding)
                .padding(.bottom, 20)
            }
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled(model.isSubmitting)
        .task { await model.restore() }
        .onChange(of: selections) { _, items in
            guard items.isEmpty == false, importTask == nil else { return }
            importTask = Task {
                let imported = await model.importItems(items, localization: localization)
                let wasCancelled = Task.isCancelled
                selections.removeAll()
                importTask = nil
                guard wasCancelled == false else { return }
                haptics.trigger(imported ? .success : .error)
            }
        }
        .onDisappear {
            importTask?.cancel()
            importTask = nil
            submissionTask?.cancel()
            submissionTask = nil
            Task { await model.saveDraft() }
        }
        .confirmationDialog(
            localization.text("feedbackkit.submission.cancel.title"),
            isPresented: $confirmCancelSubmission
        ) {
            Button(
                localization.text("feedbackkit.submission.cancel"),
                role: .destructive,
                action: cancelSubmission
            )
            Button(localization.text("feedbackkit.cancel"), role: .cancel) {}
        } message: {
            Text(localization.text("feedbackkit.submission.cancel.message"))
        }
        .confirmationDialog(localization.text("feedbackkit.attachment.discard.title"), isPresented: $confirmClose) {
            Button(localization.text("feedbackkit.attachment.discard"), role: .destructive) {
                haptics.trigger(.warning)
                close()
            }
            Button(localization.text("feedbackkit.cancel"), role: .cancel) {}
        } message: { Text(localization.text("feedbackkit.attachment.discard.message")) }
        .alert(localization.text("feedbackkit.diagnostics.upload.failed"), isPresented: $model.diagnosticFailure) {
            Button(localization.text("feedbackkit.diagnostics.retry")) { submit(diagnosticsOverride: true) }
            Button(localization.text("feedbackkit.diagnostics.send.without")) { submit(diagnosticsOverride: false) }
            Button(localization.text("feedbackkit.cancel"), role: .cancel) {}
        }
        .sheet(isPresented: $showsDisclosure) {
            VStack(spacing: 0) {
                FeedbackSheetHeader(
                    title: localization.text("feedbackkit.disclosure.title"),
                    close: { showsDisclosure = false }
                )
                .padding(.horizontal, style.pagePadding)
                .padding(.top, 14)
                .padding(.bottom, 8)
                ScrollView {
                    Text(disclosureText)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, style.pagePadding)
                        .padding(.bottom, 24)
                }
            }
            .presentationDetents([.height(220)])
            .presentationDragIndicator(.hidden)
        }
    }

    private var attachmentStrip: some View {
        let addTitle = model.isImporting ? localization.text("feedbackkit.loading") : localization.text("feedbackkit.attachment.add")
        let isImporting = model.isImporting
        return ScrollView(.horizontal) {
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(model.attachments) { attachment in
                    FeedbackAttachmentTile(
                        filename: attachment.filename,
                        removeLabel: localization.text("feedbackkit.attachment.discard"),
                        style: style,
                        remove: { removeAttachment(id: attachment.id) }
                    )
                }
                PhotosPicker(selection: $selections, maxSelectionCount: max(0, model.product.attachmentLimits.count - model.attachments.count), matching: .any(of: [.images, .videos])) {
                    FeedbackAttachmentAddLabel(title: addTitle, isLoading: isImporting, style: style)
                }
                .buttonStyle(.plain)
                .disabled(model.isImporting || model.attachments.count >= model.product.attachmentLimits.count)
            }.padding(.vertical, 7).padding(.horizontal, 2)
        }.scrollIndicators(.hidden)
    }

    private func requestClose() {
        if submissionTask != nil || model.isSubmitting {
            confirmCancelSubmission = true
        } else if model.attachments.isEmpty {
            close()
        } else {
            confirmClose = true
        }
    }

    private func cancelSubmission() {
        haptics.trigger(.warning)
        submissionTask?.cancel()
        close()
    }

    private func showDisclosure() {
        haptics.trigger(.navigation)
        showsDisclosure = true
    }

    private func removeAttachment(id: UUID) {
        haptics.trigger(.selection)
        model.removeAttachment(id: id)
    }

    private var disclosureText: String {
        model.disclosedVisibility == .public
            ? localization.text("feedbackkit.visibility.public.disclosure")
            : localization.text("feedbackkit.visibility.private.disclosure")
    }

    private var diagnosticsBinding: Binding<Bool> {
        Binding(
            get: { model.includesDiagnostics },
            set: {
                model.includesDiagnostics = $0
                haptics.trigger(.selection)
            }
        )
    }

    private func submit(diagnosticsOverride: Bool? = nil) {
        guard submissionTask == nil else { return }
        focused = nil
        submissionTask = Task {
            let didSubmit = await model.submit(
                locale: locale,
                localization: localization,
                diagnosticsOverride: diagnosticsOverride
            )
            let wasCancelled = Task.isCancelled
            submissionTask = nil
            guard wasCancelled == false else { return }
            haptics.trigger(didSubmit ? .success : .error)
            if didSubmit { submitted() }
        }
    }
}

private struct FeedbackAttachmentAddLabel: View {
    let title: String
    let isLoading: Bool
    let style: FeedbackStyle

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .tint(.secondary)
                    .accessibilityLabel(title)
            } else {
                Label(title, systemImage: "paperclip")
                    .labelStyle(.iconOnly)
                    .font(.title2)
            }
        }
            .foregroundStyle(.secondary)
            .frame(width: FeedbackStyle.attachmentTileSize, height: FeedbackStyle.attachmentTileSize)
            .contentShape(.interaction, FeedbackComponentShape(cornerRadius: style.cardCornerRadius))
            .feedbackBorder(style)
    }
}

private struct FeedbackDetailSheet: View {
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
        _model = State(initialValue: FeedbackDetailModel(id: id, client: client, voteChanged: voteChanged))
        self.style = style
        self.viewed = viewed
        self.close = close
    }
    var body: some View {
        VStack(spacing: 0) {
            FeedbackSheetHeader(title: model.detail.map { "\(localization.kind($0.type))（\(localization.status($0.status))）" } ?? "") {
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
            } close: { close() }
            .padding(.horizontal, style.pagePadding).padding(.top, 14).padding(.bottom, 8)
            Group {
                if let detail = model.detail { content(detail) }
                else if model.isLoading { FeedbackSkeletonView(layout: .feedbackDetail, style: style) }
                else if let error = model.error { FeedbackErrorView(error: error) { Task { await load() } } }
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
                if let title = detail.title, title.isEmpty == false { Text(title).font(.title3) }
                Text(detail.body).textSelection(.enabled)
                if detail.attachments.isEmpty == false { Text(localization.text("feedbackkit.attachments")).font(.headline); ForEach(detail.attachments) { Text($0.filename).foregroundStyle(.secondary) } }
                Text(detail.createdAt.feedbackRelativeText(locale: locale)).font(.caption).foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .trailing)
                ForEach(detail.messages.sorted { $0.createdAt < $1.createdAt }) { message in
                    Divider()
                    Text(message.body).textSelection(.enabled)
                    HStack { Text(message.actor == "visitor" ? localization.text("feedbackkit.visitor.message") : localization.text("feedbackkit.developer.reply")); Spacer(); Text(message.createdAt.feedbackRelativeText(locale: locale)) }.font(.caption).foregroundStyle(.secondary)
                }
                if detail.isOwner, detail.status == .open {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField(
                            "",
                            text: $model.replyBody,
                            prompt: Text(localization.text("feedbackkit.reply.placeholder")).foregroundStyle(.secondary),
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
                        .disabled(model.replyBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isReplying)
                        if let replyError = model.replyError {
                            Text(replyError).font(.footnote).foregroundStyle(.red)
                        }
                    }
                    .padding(.top, 4)
                } else if detail.isOwner {
                    Text(localization.text("feedbackkit.reply.closed"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if detail.diagnosticsIncluded == true { Label(localization.text("feedbackkit.diagnostics.included"), systemImage: "lock.shield").font(.caption).foregroundStyle(.secondary) }
            }.padding(.horizontal, style.pagePadding).padding(.bottom, 24)
        }.refreshable { await load() }
    }
}

private struct FeedbackDeveloperPostSheet: View {
    @State private var model: FeedbackDeveloperPostModel
    let style: FeedbackStyle; let activate: (FeedbackDeveloperPostAction) -> Void; let close: () -> Void
    @Environment(\.locale) private var locale
    @Environment(\.feedbackLocalization) private var localization
    init(id: String, client: FeedbackClient, style: FeedbackStyle, activate: @escaping (FeedbackDeveloperPostAction) -> Void, close: @escaping () -> Void) {
        _model = State(initialValue: FeedbackDeveloperPostModel(id: id, client: client)); self.style = style; self.activate = activate; self.close = close
    }
    var body: some View {
        VStack(spacing: 0) {
            FeedbackSheetHeader(title: localization.text("feedbackkit.developer.post"), close: close)
                .padding(.horizontal, style.pagePadding).padding(.top, 14).padding(.bottom, 8)
            Group {
                if let post = model.post {
                    ScrollView { VStack(alignment: .leading, spacing: 16) {
                        Text(post.title).font(.title2.bold()); Text(post.body).textSelection(.enabled)
                        if let action = post.action {
                            Button { activate(action) } label: {
                                HStack { Text(action.label ?? localization.text("feedbackkit.open.link")); Spacer(); Image(systemName: "arrow.up.right").font(.system(size: 25, weight: .bold)) }
                                    .frame(maxWidth: .infinity, minHeight: 52)
                                    .padding(.horizontal, 14)
                                    .contentShape(.interaction, FeedbackComponentShape(cornerRadius: style.cardCornerRadius))
                                    .feedbackBorder(style)
                            }.buttonStyle(.plain)
                        }
                        if let published = post.publishedAt { Text(published.feedbackRelativeText(locale: locale)).font(.caption).foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .trailing) }
                    }.padding(.horizontal, style.pagePadding).padding(.bottom, 24) }
                } else if model.isLoading { FeedbackSkeletonView(layout: .developerPostDetail, style: style) }
                else if let error = model.error { FeedbackErrorView(error: error) { Task { await model.load(locale: locale) } } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }.presentationDetents([.medium]).task { await model.load(locale: locale) }
    }
}

struct FeedbackIdentityView: View {
    @State private var model: FeedbackIdentityModel
    let visitor: FeedbackVisitor?
    let deleted: () -> Void
    @State private var confirm = false
    @State private var finalConfirm = false
    @Environment(\.feedbackHaptics) private var haptics
    @Environment(\.feedbackLocalization) private var localization

    init(
        client: FeedbackClient,
        visitor: FeedbackVisitor?,
        productSlug: String?,
        deleted: @escaping () -> Void
    ) {
        _model = State(initialValue: FeedbackIdentityModel(
            client: client,
            productSlug: productSlug
        ))
        self.visitor = visitor
        self.deleted = deleted
    }

    var body: some View {
        Form {
            Section(localization.text("feedbackkit.identity.yours")) { LabeledContent(localization.text("feedbackkit.identity.code"), value: visitor?.displayCode ?? "—"); Text(localization.text("feedbackkit.identity.independent")).foregroundStyle(.secondary) }
            Section(localization.text("feedbackkit.identity.data")) {
                Text(localization.text("feedbackkit.identity.delete.explanation"))
                Button(localization.text("feedbackkit.identity.delete"), role: .destructive) {
                    haptics.trigger(.warning)
                    confirm = true
                }
                .disabled(model.isDeleting)
            }
            if let error = model.error {
                Text(localization.errorMessage(for: error)).foregroundStyle(.red)
            }
        }
        .navigationTitle(localization.text("feedbackkit.identity.title")).feedbackInlineNavigationTitle()
        .alert(localization.text("feedbackkit.identity.delete"), isPresented: $confirm) { Button(localization.text("feedbackkit.continue"), role: .destructive) { finalConfirm = true }; Button(localization.text("feedbackkit.cancel"), role: .cancel) {} }
        .alert(localization.text("feedbackkit.identity.delete.final"), isPresented: $finalConfirm) { Button(localization.text("feedbackkit.identity.delete"), role: .destructive) { Task { await remove() } }; Button(localization.text("feedbackkit.cancel"), role: .cancel) {} }
    }
    private func remove() async {
        if await model.remove() {
            haptics.trigger(.success)
            deleted()
        } else if Task.isCancelled == false {
            haptics.trigger(.error)
        }
    }
}
