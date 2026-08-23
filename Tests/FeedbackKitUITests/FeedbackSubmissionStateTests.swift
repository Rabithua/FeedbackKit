@testable import FeedbackKitCore
@testable import FeedbackKitUI
import Foundation
import Testing

struct FeedbackSubmissionStateTests {
    @Test("Unchanged input reuses its attempt and uploaded attachments")
    func unchangedInputReusesAttempt() {
        let snapshot = makeSnapshot()
        var state = FeedbackSubmissionState()
        var attempt = state.attempt(
            for: snapshot,
            includesDiagnostics: false,
            localeIdentifier: "en",
            currentSnapshot: snapshot
        )
        attempt = state.recordingUploadedAttachmentIDs(
            ["attachment-id"],
            in: attempt,
            currentSnapshot: snapshot
        )

        let retry = state.attempt(
            for: snapshot,
            includesDiagnostics: false,
            localeIdentifier: "en",
            currentSnapshot: snapshot
        )

        #expect(retry.idempotencyKey == attempt.idempotencyKey)
        #expect(retry.uploadedAttachmentIDs == ["attachment-id"])
    }

    @Test("Diagnostic consent changes rotate the key but reuse unchanged attachments")
    func diagnosticConsentChangeRotatesKey() {
        let snapshot = makeSnapshot()
        var state = FeedbackSubmissionState()
        var attempt = state.attempt(
            for: snapshot,
            includesDiagnostics: false,
            localeIdentifier: "en",
            currentSnapshot: snapshot
        )
        attempt = state.recordingUploadedAttachmentIDs(
            ["attachment-id"],
            in: attempt,
            currentSnapshot: snapshot
        )

        let changedContext = state.attempt(
            for: snapshot,
            includesDiagnostics: true,
            localeIdentifier: "en",
            currentSnapshot: snapshot
        )

        #expect(changedContext.idempotencyKey != attempt.idempotencyKey)
        #expect(changedContext.uploadedAttachmentIDs == ["attachment-id"])
    }

    @Test("Changed submission content discards uploaded attachment IDs")
    func changedSnapshotInvalidatesAttachments() {
        let original = makeSnapshot(body: "Original")
        let edited = makeSnapshot(body: "Edited")
        var state = FeedbackSubmissionState()
        var attempt = state.attempt(
            for: original,
            includesDiagnostics: false,
            localeIdentifier: "en",
            currentSnapshot: original
        )
        attempt = state.recordingUploadedAttachmentIDs(
            ["attachment-id"],
            in: attempt,
            currentSnapshot: original
        )

        let editedAttempt = state.attempt(
            for: edited,
            includesDiagnostics: false,
            localeIdentifier: "en",
            currentSnapshot: edited
        )

        #expect(editedAttempt.idempotencyKey != attempt.idempotencyKey)
        #expect(editedAttempt.uploadedAttachmentIDs == nil)
    }

    @Test("An attempt for stale input is not retained")
    func staleSnapshotIsNotRetained() {
        let stale = makeSnapshot(body: "Stale")
        let current = makeSnapshot(body: "Current")
        var state = FeedbackSubmissionState()
        let staleAttempt = state.attempt(
            for: stale,
            includesDiagnostics: false,
            localeIdentifier: "en",
            currentSnapshot: current
        )
        _ = state.recordingUploadedAttachmentIDs(
            ["stale-attachment-id"],
            in: staleAttempt,
            currentSnapshot: current
        )
        let retriedStaleAttempt = state.attempt(
            for: stale,
            includesDiagnostics: false,
            localeIdentifier: "en",
            currentSnapshot: stale
        )

        #expect(state.uploadedAttachmentIDs == nil)
        #expect(retriedStaleAttempt.idempotencyKey != staleAttempt.idempotencyKey)
    }

    private func makeSnapshot(body: String = "Body") -> FeedbackSubmissionSnapshot {
        FeedbackSubmissionSnapshot(
            kind: .bug,
            title: "Title",
            body: body,
            includesDiagnostics: false,
            attachments: [
                FeedbackAttachmentSource(
                    filename: "attachment.png",
                    contentType: "image/png",
                    data: Data("image".utf8)
                )
            ]
        )
    }
}
