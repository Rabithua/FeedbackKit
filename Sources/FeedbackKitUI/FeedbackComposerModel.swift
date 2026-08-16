import FeedbackKitCore
import Foundation
import Observation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

@MainActor @Observable
final class FeedbackComposerModel {
    var kind: FeedbackKind
    var title = ""
    var body = ""
    var includesDiagnostics = false
    var attachments: [FeedbackAttachmentSource] = []
    var isImporting = false
    var isSubmitting = false
    var errorMessage: String?
    var diagnosticFailure = false
    var disclosedVisibility: FeedbackVisibility
    let idempotencyKey = UUID().uuidString
    private(set) var uploadedAttachmentIDs: [String]?

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
        kind = draft.kind
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
        guard items.isEmpty == false, isImporting == false else { return false }
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
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedBody.isEmpty == false else {
            errorMessage = localization.text("feedbackkit.composer.body.required")
            return false
        }
        guard trimmedTitle.count <= 240, trimmedBody.count <= 20_000 else {
            errorMessage = localization.text("feedbackkit.composer.too.long")
            return false
        }
        isSubmitting = true
        errorMessage = nil
        diagnosticFailure = false
        defer { isSubmitting = false }
        do {
            let refreshed = try await client.bootstrap(locale: locale).product
            if refreshed.defaultFeedbackVisibility != disclosedVisibility {
                disclosedVisibility = refreshed.defaultFeedbackVisibility
                errorMessage = localization.text("feedbackkit.composer.visibility.changed")
                return false
            }
            let refreshedDiagnosticsAvailable = refreshed.diagnostics?.supportsSchemaOne == true
                && client.diagnosticsProvider != nil
            if refreshedDiagnosticsAvailable == false {
                includesDiagnostics = false
            }
            let includeDiagnostics = (diagnosticsOverride ?? includesDiagnostics)
                && refreshedDiagnosticsAvailable
            let ids: [String]
            if let uploadedAttachmentIDs {
                ids = uploadedAttachmentIDs
            } else {
                ids = try await client.uploadAttachments(attachments)
                uploadedAttachmentIDs = ids
            }
            _ = try await client.submitFeedback(
                type: kind,
                title: trimmedTitle.isEmpty ? nil : trimmedTitle,
                body: trimmedBody,
                locale: locale,
                attachmentIds: ids,
                includeDiagnostics: includeDiagnostics,
                idempotencyKey: idempotencyKey
            )
            resetAfterSubmission()
            try? await draftStore.remove(productSlug: product.slug)
            return true
        } catch FeedbackClientError.diagnosticUploadFailed {
            diagnosticFailure = true
            errorMessage = localization.text("feedbackkit.diagnostics.upload.failed")
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func resetAfterSubmission() {
        title = ""
        body = ""
        includesDiagnostics = false
        attachments.removeAll()
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
