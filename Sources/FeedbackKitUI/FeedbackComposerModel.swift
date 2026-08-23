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
        didSet { submissionInputDidChange() }
    }
    var isImporting = false
    var isSubmitting = false
    var errorMessage: String?
    var diagnosticFailure = false
    var disclosedVisibility: FeedbackVisibility
    private(set) var uploadedAttachmentIDs: [String]?
    @ObservationIgnored private var pendingSubmission: FeedbackSubmissionAttempt?

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
        for item in items.prefix(max(0, product.attachmentLimits.count - attachments.count)) {
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let type = item.supportedContentTypes.first(where: {
                          Self.allowedTypes.contains($0.identifier)
                      }),
                      let mime = type.preferredMIMEType
                else {
                    errorMessage = localization.text("feedbackkit.attachment.unsupported")
                    continue
                }
                let limit = mime.hasPrefix("video/")
                    ? product.attachmentLimits.videoBytes
                    : product.attachmentLimits.imageBytes
                guard data.count <= limit else {
                    errorMessage = localization.text("feedbackkit.attachment.too.large")
                    continue
                }
                let filename = "attachment-\(UUID().uuidString).\(type.preferredFilenameExtension ?? "data")"
                attachments.append(.init(filename: filename, contentType: mime, data: data))
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
        defer { isSubmitting = false }
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
            var attempt = submissionAttempt(
                for: snapshot,
                includesDiagnostics: includeDiagnostics,
                localeIdentifier: locale.identifier
            )
            let ids: [String]
            if let uploadedAttachmentIDs = attempt.uploadedAttachmentIDs {
                ids = uploadedAttachmentIDs
            } else {
                ids = try await client.uploadAttachments(snapshot.attachments)
                attempt.uploadedAttachmentIDs = ids
                retainPendingSubmissionIfCurrent(attempt)
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

    private func submissionAttempt(
        for snapshot: FeedbackSubmissionSnapshot,
        includesDiagnostics: Bool,
        localeIdentifier: String
    ) -> FeedbackSubmissionAttempt {
        if let pendingSubmission,
           pendingSubmission.matches(
               snapshot: snapshot,
               includesDiagnostics: includesDiagnostics,
               localeIdentifier: localeIdentifier
           )
        {
            return pendingSubmission
        }
        let reusableAttachmentIDs = pendingSubmission?.snapshot == snapshot
            ? pendingSubmission?.uploadedAttachmentIDs
            : nil
        let attempt = FeedbackSubmissionAttempt(
            snapshot: snapshot,
            includesDiagnostics: includesDiagnostics,
            localeIdentifier: localeIdentifier,
            uploadedAttachmentIDs: reusableAttachmentIDs
        )
        retainPendingSubmissionIfCurrent(attempt)
        return attempt
    }

    private func retainPendingSubmissionIfCurrent(_ attempt: FeedbackSubmissionAttempt) {
        guard submissionSnapshot == attempt.snapshot else { return }
        pendingSubmission = attempt
        uploadedAttachmentIDs = attempt.uploadedAttachmentIDs
    }

    private func completeSubmission(_ snapshot: FeedbackSubmissionSnapshot) async {
        pendingSubmission = nil
        uploadedAttachmentIDs = nil
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
        pendingSubmission = nil
        uploadedAttachmentIDs = nil
    }

    private func submissionInputDidChange() {
        pendingSubmission = nil
        uploadedAttachmentIDs = nil
    }

    private static let allowedTypes: Set<String> = [
        "public.jpeg",
        "public.png",
        "public.heic",
        "org.webmproject.webp",
        "com.compuserve.gif",
        "public.mpeg-4",
        "com.apple.quicktime-movie",
    ]
}
