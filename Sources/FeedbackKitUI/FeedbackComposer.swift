import FeedbackKitCore
import PhotosUI
import SwiftUI

struct FeedbackComposer: View {
    @State private var model: FeedbackComposerModel
    @State private var selections: [PhotosPickerItem] = []
    @State private var confirmClose = false
    @State private var confirmCancelSubmission = false
    @State private var showsDisclosure = false
    @State private var importTask: Task<Void, Never>?
    @State private var submissionTask: Task<Void, Never>?
    @State private var hasSubmitted = false
    @State private var didFinishSubmission = false
    @FocusState private var focused: Field?
    let style: FeedbackStyle
    let submitted: () -> Void
    let close: () -> Void
    @Environment(\.locale) private var locale
    @Environment(\.feedbackHaptics) private var haptics
    @Environment(\.feedbackLocalization) private var localization

    private enum Field {
        case title
        case body
    }

    init(
        kind: FeedbackKind,
        product: FeedbackProduct,
        client: FeedbackClient,
        draftStore: FeedbackDraftStore,
        style: FeedbackStyle,
        submitted: @escaping () -> Void,
        close: @escaping () -> Void
    ) {
        _model = State(initialValue: FeedbackComposerModel(
            kind: kind,
            product: product,
            client: client,
            draftStore: draftStore
        ))
        self.style = style
        self.submitted = submitted
        self.close = close
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
                .disabled(isSubmissionActive)
            } close: {
                requestClose()
            }
            .padding(.horizontal, style.pagePadding)
            .padding(.top, 14)
            .padding(.bottom, 8)

            ZStack {
                form
                    .opacity(isSubmissionActive ? 0 : 1)
                    .allowsHitTesting(isSubmissionActive == false)
                    .accessibilityHidden(isSubmissionActive)

                if isSubmissionActive {
                    submissionStatus
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.18), value: isSubmissionActive)
            .animation(.easeInOut(duration: 0.18), value: hasSubmitted)
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled(isSubmissionActive)
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
        .confirmationDialog(
            localization.text("feedbackkit.attachment.discard.title"),
            isPresented: $confirmClose
        ) {
            Button(localization.text("feedbackkit.attachment.discard"), role: .destructive) {
                haptics.trigger(.warning)
                close()
            }
            Button(localization.text("feedbackkit.cancel"), role: .cancel) {}
        } message: {
            Text(localization.text("feedbackkit.attachment.discard.message"))
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

    private var isSubmissionActive: Bool {
        submissionTask != nil || model.isSubmitting || hasSubmitted
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TextField(
                    "",
                    text: $model.title,
                    prompt: Text(localization.text("feedbackkit.composer.title.placeholder"))
                        .foregroundStyle(.secondary)
                )
                .focused($focused, equals: .title)
                .padding(14)
                .feedbackBorder(style)
                .accessibilityLabel(localization.text("feedbackkit.composer.title.placeholder"))

                ZStack(alignment: .topLeading) {
                    if model.body.isEmpty {
                        Text(localization.text("feedbackkit.composer.body.placeholder"))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $model.body)
                        .focused($focused, equals: .body)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 170)
                        .padding(10)
                        .accessibilityLabel(localization.text("feedbackkit.composer.body.placeholder"))
                        .accessibilityIdentifier("developerCommunity.composer.body")
                }
                .feedbackBorder(style)

                if model.showsAttachmentStrip {
                    FeedbackAttachmentStrip(
                        model: model,
                        selections: $selections,
                        style: style,
                        remove: removeAttachment
                    )
                }

                if model.diagnosticsAvailable {
                    Toggle(isOn: diagnosticsBinding) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(localization.text("feedbackkit.diagnostics.include"))
                                .font(.headline)
                            Text(localization.text("feedbackkit.diagnostics.disclosure"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let message = model.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("developerCommunity.composer.error")
                }

                submissionButton
            }
            .disabled(isSubmissionActive)
            .padding(.horizontal, style.pagePadding)
            .padding(.bottom, 20)
        }
        .accessibilityIdentifier("developerCommunity.composer.form")
    }

    private var submissionButton: some View {
        Button {
            submit()
        } label: {
            Text(
                model.disclosedVisibility == .public
                    ? localization.text("feedbackkit.send.public")
                    : localization.text("feedbackkit.send")
            )
            .lineLimit(1)
            .font(.headline)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 54)
            .contentShape(.interaction, FeedbackComponentShape(cornerRadius: style.cardCornerRadius))
            .feedbackBorder(style)
        }
        .buttonStyle(.plain)
        .disabled(model.canSubmit == false || isSubmissionActive)
        .accessibilityIdentifier("developerCommunity.composer.submit")
    }

    private var submissionStatus: some View {
        VStack(spacing: 16) {
            ZStack {
                if hasSubmitted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(.primary)
                } else {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.primary)
                }
            }
            .frame(width: 40, height: 40)
            .accessibilityHidden(true)

            Text(localization.text(
                hasSubmitted ? "feedbackkit.submission.sent" : "feedbackkit.submission.sending"
            ))
            .font(.headline)
            .foregroundStyle(.primary)
            .accessibilityIdentifier(
                hasSubmitted
                    ? "developerCommunity.composer.sent"
                    : "developerCommunity.composer.submitting"
            )
        }
        .padding(.horizontal, style.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func requestClose() {
        if hasSubmitted {
            finishSubmission()
        } else if isSubmissionActive {
            confirmCancelSubmission = true
        } else if model.attachments.isEmpty {
            close()
        } else {
            confirmClose = true
        }
    }

    private func cancelSubmission() {
        guard hasSubmitted == false else {
            finishSubmission()
            return
        }
        haptics.trigger(.warning)
        submissionTask?.cancel()
        close()
    }

    private func finishSubmission() {
        guard didFinishSubmission == false else { return }
        didFinishSubmission = true
        submitted()
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
        guard isSubmissionActive == false else { return }
        focused = nil
        submissionTask = Task {
            defer { submissionTask = nil }
            let didSubmit = await model.submit(
                locale: locale,
                localization: localization,
                diagnosticsOverride: diagnosticsOverride,
                onSubmitted: {
                    confirmCancelSubmission = false
                    hasSubmitted = true
                    haptics.trigger(.success)
                    try? await Task.sleep(for: .milliseconds(800))
                }
            )
            guard Task.isCancelled == false else { return }
            if didSubmit {
                finishSubmission()
            } else {
                haptics.trigger(.error)
            }
        }
    }
}
