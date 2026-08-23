import FeedbackKitCore
import Foundation
import Observation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

@MainActor @Observable
final class FeedbackComposerModel {
    var kind: FeedbackKind {
        didSet { submissionInputDidChange() }
    }
    var title = "" {
        didSet { submissionInputDidChange() }
    }
    var body = "" {
        didSet { submissionInputDidChange() }
    }
    var includesDiagnostics = false {
        didSet { submissionInputDidChange() }
    }
    var attachments: [FeedbackAttachmentSource] = [] {
        didSet {
            submissionInputDidChange()
            if isSubmitting == false {
                pruneTemporaryAttachmentFiles()
            }
        }
    }
    var isImporting = false
    var isSubmitting = false
    var errorMessage: String?
    var diagnosticFailure = false
    var disclosedVisibility: FeedbackVisibility
    @ObservationIgnored private var submissionState = FeedbackSubmissionState()
    @ObservationIgnored private var attachmentLeases = FeedbackAttachmentLeaseRegistry()

    let product: FeedbackProduct
    let client: FeedbackClient
    let draftStore: FeedbackDraftStore

    init(
        kind: FeedbackKind,
        product: FeedbackProduct,
        client: FeedbackClient,
        draftStore: FeedbackDraftStore
    ) {
        self.kind = kind
        self.product = product
        self.client = client
        self.draftStore = draftStore
        disclosedVisibility = product.defaultFeedbackVisibility
    }

    var diagnosticsAvailable: Bool {
        product.diagnostics?.supportsSchemaOne == true && client.diagnosticsProvider != nil
    }

    var canSubmit: Bool {
        body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && isSubmitting == false
    }

    var uploadedAttachmentIDs: [String]? {
        submissionState.uploadedAttachmentIDs
    }

    func restore() async {
        guard let draft = await draftStore.load(productSlug: product.slug) else { return }
        title = draft.title
        body = draft.body
        includesDiagnostics = diagnosticsAvailable && draft.includesDiagnostics
    }

    func saveDraft() async {
        let draft = FeedbackDraft(
            productSlug: product.slug,
            kind: kind,
            title: title,
            body: body,
            includesDiagnostics: includesDiagnostics
        )
        if draft.isEmpty {
            try? await draftStore.remove(productSlug: product.slug)
        } else {
            try? await draftStore.save(draft)
        }
    }

    func importItems(
        _ items: [PhotosPickerItem],
        localization: FeedbackLocalization
    ) async -> Bool {
        guard items.isEmpty == false,
              isImporting == false,
              isSubmitting == false
        else { return false }
        isImporting = true
        defer { isImporting = false }
        var imported = false
        let policy = FeedbackAttachmentImportPolicy(limits: product.attachmentLimits)
        for item in items.prefix(policy.remainingCount(after: attachments.count)) {
            do {
                guard let type = policy.supportedType(in: item.supportedContentTypes),
                      let mime = type.preferredMIMEType
                else {
                    errorMessage = localization.text("feedbackkit.attachment.unsupported")
                    continue
                }
                guard let importedFile = try await item.loadTransferable(
                    type: FeedbackImportedAttachmentFile.self
                ) else {
                    errorMessage = localization.text("feedbackkit.attachment.failed")
                    continue
                }
                try Task.checkCancellation()
                let id = UUID()
                let filename = "attachment-\(id.uuidString).\(type.preferredFilenameExtension ?? "data")"
                let source = try FeedbackAttachmentSource(
                    id: id,
                    filename: filename,
                    contentType: mime,
                    fileURL: importedFile.lease.url
                )
                let limit = policy.byteLimit(forMIMEType: mime)
                guard source.byteCount <= limit else {
                    errorMessage = localization.text("feedbackkit.attachment.too.large")
                    continue
                }
                addImportedAttachment(source, lease: importedFile.lease)
                imported = true
            } catch is CancellationError {
                return imported
            } catch {
                errorMessage = localization.text("feedbackkit.attachment.failed")
            }
        }
        return imported
    }

    func submit(
        locale: Locale,
        localization: FeedbackLocalization,
        diagnosticsOverride: Bool? = nil
    ) async -> Bool {
        guard isSubmitting == false else { return false }
        var snapshot = submissionSnapshot
        guard snapshot.trimmedBody.isEmpty == false else {
            errorMessage = localization.text("feedbackkit.composer.body.required")
            return false
        }
        guard snapshot.trimmedTitle.count <= 240, snapshot.trimmedBody.count <= 20_000 else {
            errorMessage = localization.text("feedbackkit.composer.too.long")
            return false
        }
        isSubmitting = true
        errorMessage = nil
        diagnosticFailure = false
        defer {
            isSubmitting = false
            pruneTemporaryAttachmentFiles()
        }
        do {
            let refreshed = try await client.bootstrap(locale: locale).product
            try Task.checkCancellation()
            if refreshed.defaultFeedbackVisibility != disclosedVisibility {
                disclosedVisibility = refreshed.defaultFeedbackVisibility
                submissionInputDidChange()
                errorMessage = localization.text("feedbackkit.composer.visibility.changed")
                await saveDraft()
                return false
            }
            let refreshedDiagnosticsAvailable = refreshed.diagnostics?.supportsSchemaOne == true
                && client.diagnosticsProvider != nil
            if refreshedDiagnosticsAvailable == false {
                if includesDiagnostics {
                    includesDiagnostics = false
                }
                snapshot = snapshot.withIncludesDiagnostics(false)
            }
            let includeDiagnostics = (diagnosticsOverride ?? snapshot.includesDiagnostics)
                && refreshedDiagnosticsAvailable
            var attempt = submissionState.attempt(
                for: snapshot,
                includesDiagnostics: includeDiagnostics,
                localeIdentifier: locale.identifier,
                currentSnapshot: submissionSnapshot
            )
            let ids: [String]
            if let uploadedAttachmentIDs = attempt.uploadedAttachmentIDs {
                ids = uploadedAttachmentIDs
            } else {
                ids = try await client.uploadAttachments(snapshot.attachments)
                attempt = submissionState.recordingUploadedAttachmentIDs(
                    ids,
                    in: attempt,
                    currentSnapshot: submissionSnapshot
                )
            }
            try Task.checkCancellation()
            _ = try await client.submitFeedback(
                type: snapshot.kind,
                title: snapshot.trimmedTitle.isEmpty ? nil : snapshot.trimmedTitle,
                body: snapshot.trimmedBody,
                locale: locale,
                attachmentIds: ids,
                includeDiagnostics: includeDiagnostics,
                idempotencyKey: attempt.idempotencyKey
            )
            await completeSubmission(snapshot)
            return true
        } catch FeedbackClientError.diagnosticUploadFailed {
            diagnosticFailure = true
            errorMessage = localization.text("feedbackkit.diagnostics.upload.failed")
            await saveDraft()
            return false
        } catch is CancellationError {
            errorMessage = nil
            diagnosticFailure = false
            await saveDraft()
            return false
        } catch {
            errorMessage = localization.errorMessage(for: error)
            await saveDraft()
            return false
        }
    }

    private var submissionSnapshot: FeedbackSubmissionSnapshot {
        FeedbackSubmissionSnapshot(
            kind: kind,
            title: title,
            body: body,
            includesDiagnostics: includesDiagnostics,
            attachments: attachments
        )
    }

    private func completeSubmission(_ snapshot: FeedbackSubmissionSnapshot) async {
        submissionState.invalidate()
        if submissionSnapshot == snapshot {
            resetAfterSubmission()
            try? await draftStore.remove(productSlug: product.slug)
        } else {
            await saveDraft()
        }
    }

    private func resetAfterSubmission() {
        title = ""
        body = ""
        includesDiagnostics = false
        attachments.removeAll()
        attachmentLeases.removeAll()
        submissionState.invalidate()
    }

    func removeAttachment(id: UUID) {
        guard isSubmitting == false else { return }
        attachments.removeAll { $0.id == id }
        attachmentLeases.release(id: id)
    }

    func addImportedAttachment(
        _ source: FeedbackAttachmentSource,
        lease: FeedbackTemporaryFileLease
    ) {
        guard isSubmitting == false, attachmentLeases.retain(lease, for: source) else { return }
        attachments.append(source)
    }

    private func submissionInputDidChange() {
        submissionState.invalidate()
    }

    private func pruneTemporaryAttachmentFiles() {
        let retainedIDs = Set(attachments.map(\.id))
        attachmentLeases.retainOnly(ids: retainedIDs)
    }
}
