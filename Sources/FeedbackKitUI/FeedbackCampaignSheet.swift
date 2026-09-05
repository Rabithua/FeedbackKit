import FeedbackKitCore
import SwiftUI

/// A host-presented, ready-made sheet for one FeedbackServer campaign.
///
/// The host remains responsible for discovering and choosing a campaign, then presenting this
/// view with `.sheet(item:)` or another presentation API. FeedbackKit never presents a Campaign
/// invitation automatically; Feedback Center only opens one from an explicit Campaign action.
public struct FeedbackCampaignSheet: View {
    @State private var model: FeedbackCampaignSheetModel
    private let style: FeedbackStyle
    private let haptics: FeedbackHaptics
    private let languagePolicy: FeedbackLanguagePolicy
    private let onSubmitted: @MainActor @Sendable (OwnedFeedbackSummary) -> Void

    @Environment(\.locale) private var hostLocale

    public init(
        campaign: FeedbackCampaign,
        client: FeedbackClient,
        style: FeedbackStyle = .default,
        haptics: FeedbackHaptics = .none,
        languagePolicy: FeedbackLanguagePolicy = .followHost,
        onSubmitted: @escaping @MainActor @Sendable (OwnedFeedbackSummary) -> Void = { _ in }
    ) {
        _model = State(initialValue: FeedbackCampaignSheetModel(campaign: campaign, client: client))
        self.style = style
        self.haptics = haptics
        self.languagePolicy = languagePolicy
        self.onSubmitted = onSubmitted
    }

    public init(
        campaignID: String,
        client: FeedbackClient,
        style: FeedbackStyle = .default,
        haptics: FeedbackHaptics = .none,
        languagePolicy: FeedbackLanguagePolicy = .followHost,
        onSubmitted: @escaping @MainActor @Sendable (OwnedFeedbackSummary) -> Void = { _ in }
    ) {
        _model = State(
            initialValue: FeedbackCampaignSheetModel(campaignID: campaignID, client: client)
        )
        self.style = style
        self.haptics = haptics
        self.languagePolicy = languagePolicy
        self.onSubmitted = onSubmitted
    }

    public var body: some View {
        FeedbackCampaignSheetContent(
            model: model,
            style: style,
            onSubmitted: onSubmitted
        )
        .environment(\.feedbackHaptics, haptics)
        .environment(\.locale, locale)
        .environment(\.feedbackLocalization, FeedbackLocalization(locale: locale))
        .tint(.accentColor)
    }

    private var locale: Locale {
        languagePolicy.resolve(hostLocale: hostLocale)
    }
}

private struct FeedbackCampaignSheetContent: View {
    @Bindable var model: FeedbackCampaignSheetModel
    let style: FeedbackStyle
    let onSubmitted: @MainActor @Sendable (OwnedFeedbackSummary) -> Void

    @State private var confirmCancelSubmission = false
    @State private var confirmDiscard = false
    @State private var submissionTask: Task<Void, Never>?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.feedbackHaptics) private var haptics
    @Environment(\.feedbackLocalization) private var localization

    var body: some View {
        VStack(spacing: 0) {
            FeedbackSheetHeader(title: headerTitle) {
                if let form = model.form, form.pages.count > 1 {
                    Text(
                        localization.formattedText(
                            "feedbackkit.campaign.page",
                            (model.currentPageIndex + 1).formatted(
                                .number.locale(locale)
                            ),
                            form.pages.count.formatted(.number.locale(locale))
                        )
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("developerCommunity.campaign.progress")
                }
            } close: {
                requestClose()
            }
            .padding(.horizontal, style.pagePadding)
            .padding(.top, 14)
            .padding(.bottom, 8)

            Group {
                if model.isUnavailable {
                    campaignTerminalState(
                        titleKey: "feedbackkit.campaign.ended.title",
                        descriptionKey: "feedbackkit.campaign.ended.message",
                        systemImage: "clock.badge.xmark"
                    )
                } else if model.campaign?.hasResponded == true {
                    campaignTerminalState(
                        titleKey: "feedbackkit.campaign.completed.title",
                        descriptionKey: "feedbackkit.campaign.completed.message",
                        systemImage: "checkmark.circle"
                    )
                } else if let form = model.form, let page = model.currentPage {
                    campaignForm(form: form, page: page)
                } else if model.isLoading {
                    ProgressView(localization.text("feedbackkit.loading"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = model.loadError {
                    FeedbackErrorView(error: error) {
                        Task { await model.retry(locale: locale) }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(FeedbackSystemBackground())
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(model.isSubmitting || model.hasInput)
        .task(id: locale.identifier) {
            await model.load(locale: locale)
        }
        .task(id: model.campaign?.id) {
            await model.markReadIfNeeded()
        }
        .onDisappear {
            submissionTask?.cancel()
            submissionTask = nil
        }
        .confirmationDialog(
            localization.text("feedbackkit.campaign.submission.cancel.title"),
            isPresented: $confirmCancelSubmission
        ) {
            Button(
                localization.text("feedbackkit.campaign.submission.cancel"),
                role: .destructive,
                action: cancelSubmission
            )
            Button(localization.text("feedbackkit.cancel"), role: .cancel) {}
        } message: {
            Text(localization.text("feedbackkit.campaign.submission.cancel.message"))
        }
        .confirmationDialog(
            localization.text("feedbackkit.campaign.discard.title"),
            isPresented: $confirmDiscard
        ) {
            Button(localization.text("feedbackkit.campaign.discard"), role: .destructive) {
                haptics.trigger(.warning)
                dismiss()
            }
            Button(localization.text("feedbackkit.cancel"), role: .cancel) {}
        } message: {
            Text(localization.text("feedbackkit.campaign.discard.message"))
        }
        .alert(
            localization.text("feedbackkit.diagnostics.upload.failed"),
            isPresented: $model.diagnosticFailure
        ) {
            Button(localization.text("feedbackkit.diagnostics.retry")) {
                submit(diagnosticsOverride: true)
            }
            Button(localization.text("feedbackkit.diagnostics.send.without")) {
                submit(diagnosticsOverride: false)
            }
            Button(localization.text("feedbackkit.cancel"), role: .cancel) {}
        }
    }

    private func campaignTerminalState(
        titleKey: String,
        descriptionKey: String,
        systemImage: String
    ) -> some View {
        ContentUnavailableView {
            Label(localization.text(titleKey), systemImage: systemImage)
        } description: {
            Text(localization.text(descriptionKey))
        }
    }

    private func campaignForm(
        form: FeedbackCampaignForm,
        page: FeedbackCampaignFormPage
    ) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                FeedbackCampaignPageView(
                    model: model,
                    form: form,
                    page: page,
                    style: style
                )
                .padding(.horizontal, style.pagePadding)
                .padding(.bottom, 18)
            }
            .id(page.id)
            .disabled(model.isSubmitting)

            FeedbackCampaignNavigationBar(
                isFirstPage: model.currentPageIndex == 0,
                isLastPage: model.isLastPage,
                isSubmitting: model.isSubmitting,
                style: style,
                back: goBack,
                primary: primaryAction
            )
            .padding(.horizontal, style.pagePadding)
            .padding(.top, 10)
            .padding(.bottom, 14)
            .background(.bar)
        }
    }

    private var headerTitle: String {
        model.form?.title ?? localization.text("feedbackkit.campaign.title")
    }

    private func requestClose() {
        if submissionTask != nil || model.isSubmitting {
            confirmCancelSubmission = true
        } else if model.hasInput {
            confirmDiscard = true
        } else {
            dismiss()
        }
    }

    private func cancelSubmission() {
        haptics.trigger(.warning)
        submissionTask?.cancel()
        dismiss()
    }

    private func goBack() {
        haptics.trigger(.navigation)
        model.goBack()
    }

    private func primaryAction() {
        if model.isLastPage {
            submit()
        } else if model.advance(locale: locale) {
            haptics.trigger(.navigation)
        } else {
            haptics.trigger(.error)
        }
    }

    private func submit(diagnosticsOverride: Bool? = nil) {
        guard submissionTask == nil else { return }
        submissionTask = Task {
            let response = await model.submit(
                locale: locale,
                localization: localization,
                diagnosticsOverride: diagnosticsOverride
            )
            let wasCancelled = Task.isCancelled
            submissionTask = nil
            guard wasCancelled == false else { return }
            guard let response else {
                haptics.trigger(.error)
                return
            }
            haptics.trigger(.success)
            onSubmitted(response)
            dismiss()
        }
    }
}

private struct FeedbackCampaignPageView: View {
    @Bindable var model: FeedbackCampaignSheetModel
    let form: FeedbackCampaignForm
    let page: FeedbackCampaignFormPage
    let style: FeedbackStyle

    @Environment(\.locale) private var locale
    @Environment(\.feedbackHaptics) private var haptics
    @Environment(\.feedbackLocalization) private var localization

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            if model.currentPageIndex == 0, form.description.isEmpty == false {
                Text(form.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 2)
            }

            ForEach(page.elements) { element in
                FeedbackCampaignElementView(
                    element: element,
                    state: questionState(for: element),
                    issue: validationIssue(for: element),
                    style: style
                )
            }

            if model.isLastPage {
                additionalComment
                if model.diagnosticsAvailable {
                    Toggle(isOn: $model.includesDiagnostics) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(localization.text("feedbackkit.diagnostics.include"))
                                .font(.headline)
                            Text(localization.text("feedbackkit.diagnostics.disclosure"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onChange(of: model.includesDiagnostics) {
                        haptics.trigger(.selection)
                    }
                    .padding(.top, 4)
                }
            }

            if let errorMessage = model.submissionErrorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("developerCommunity.campaign.submission.error")
            }
        }
        .padding(.top, 8)
    }

    private var additionalComment: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localization.text("feedbackkit.campaign.comment.title"))
                .font(.headline)
            TextField(
                "",
                text: $model.comment,
                prompt: Text(localization.text("feedbackkit.campaign.comment.placeholder"))
                    .foregroundStyle(.secondary),
                axis: .vertical
            )
            .lineLimit(2...7)
            .padding(14)
            .feedbackBorder(style)
            .accessibilityLabel(localization.text("feedbackkit.campaign.comment.title"))
            .accessibilityIdentifier("developerCommunity.campaign.comment")

            if model.commentIsTooLong {
                Text(localization.text("feedbackkit.campaign.validation.comment.too.long"))
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(.top, 4)
    }

    private func questionState(
        for element: FeedbackCampaignFormElement
    ) -> FeedbackCampaignQuestionState? {
        guard case let .question(question) = element.content else { return nil }
        return model.questionState(for: question)
    }

    private func validationIssue(
        for element: FeedbackCampaignFormElement
    ) -> FeedbackCampaignValidationIssue? {
        guard case let .question(question) = element.content else { return nil }
        return model.validationIssue(for: question, on: page, locale: locale)
    }
}

private struct FeedbackCampaignElementView: View {
    let element: FeedbackCampaignFormElement
    let state: FeedbackCampaignQuestionState?
    let issue: FeedbackCampaignValidationIssue?
    let style: FeedbackStyle

    var body: some View {
        VStack {
            switch element.content {
            case let .notice(text):
                FeedbackCampaignNoticeView(text: text, style: style)
            case .question:
                if let state {
                    FeedbackCampaignQuestionView(state: state, issue: issue, style: style)
                }
            }
        }
    }
}

struct FeedbackCampaignNavigationBar: View {
    let isFirstPage: Bool
    let isLastPage: Bool
    let isSubmitting: Bool
    let style: FeedbackStyle
    let back: () -> Void
    let primary: () -> Void

    @Environment(\.feedbackLocalization) private var localization

    var body: some View {
        HStack(spacing: 10) {
            if isFirstPage == false {
                Button(action: back) {
                    Text(localization.text("feedbackkit.campaign.back"))
                        .font(.headline)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 54)
                        .contentShape(
                            .interaction,
                            FeedbackComponentShape(cornerRadius: style.cardCornerRadius)
                        )
                        .feedbackBorder(style)
                }
                .buttonStyle(.plain)
                .disabled(isSubmitting)
                .accessibilityIdentifier("developerCommunity.campaign.back")
            }

            Button(action: primary) {
                ZStack {
                    if isSubmitting {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.primary)
                            .accessibilityLabel(localization.text("feedbackkit.loading"))
                    } else {
                        Text(
                            localization.text(
                                isLastPage
                                    ? "feedbackkit.campaign.submit"
                                    : "feedbackkit.continue"
                            )
                        )
                        .lineLimit(1)
                    }
                }
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, minHeight: 54)
                .contentShape(
                    .interaction,
                    FeedbackComponentShape(cornerRadius: style.cardCornerRadius)
                )
                .feedbackBorder(style)
            }
            .buttonStyle(.plain)
            .disabled(isSubmitting)
            .accessibilityIdentifier("developerCommunity.campaign.primary")
        }
    }
}
