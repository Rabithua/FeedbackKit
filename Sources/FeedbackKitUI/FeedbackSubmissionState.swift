struct FeedbackSubmissionState {
    private var pendingAttempt: FeedbackSubmissionAttempt?

    var uploadedAttachmentIDs: [String]? {
        pendingAttempt?.uploadedAttachmentIDs
    }

    mutating func attempt(
        for snapshot: FeedbackSubmissionSnapshot,
        includesDiagnostics: Bool,
        localeIdentifier: String,
        currentSnapshot: FeedbackSubmissionSnapshot
    ) -> FeedbackSubmissionAttempt {
        if let pendingAttempt,
           pendingAttempt.matches(
               snapshot: snapshot,
               includesDiagnostics: includesDiagnostics,
               localeIdentifier: localeIdentifier
           )
        {
            return pendingAttempt
        }

        let reusableAttachmentIDs = pendingAttempt?.snapshot == snapshot
            ? pendingAttempt?.uploadedAttachmentIDs
            : nil
        let attempt = FeedbackSubmissionAttempt(
            snapshot: snapshot,
            includesDiagnostics: includesDiagnostics,
            localeIdentifier: localeIdentifier,
            uploadedAttachmentIDs: reusableAttachmentIDs
        )
        retain(attempt, currentSnapshot: currentSnapshot)
        return attempt
    }

    mutating func recordingUploadedAttachmentIDs(
        _ ids: [String],
        in attempt: FeedbackSubmissionAttempt,
        currentSnapshot: FeedbackSubmissionSnapshot
    ) -> FeedbackSubmissionAttempt {
        var updatedAttempt = attempt
        updatedAttempt.uploadedAttachmentIDs = ids
        retain(updatedAttempt, currentSnapshot: currentSnapshot)
        return updatedAttempt
    }

    mutating func invalidate() {
        pendingAttempt = nil
    }

    private mutating func retain(
        _ attempt: FeedbackSubmissionAttempt,
        currentSnapshot: FeedbackSubmissionSnapshot
    ) {
        guard currentSnapshot == attempt.snapshot else { return }
        pendingAttempt = attempt
    }
}
