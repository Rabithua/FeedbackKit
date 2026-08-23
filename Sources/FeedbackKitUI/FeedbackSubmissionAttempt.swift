import Foundation

struct FeedbackSubmissionAttempt: Sendable {
    let snapshot: FeedbackSubmissionSnapshot
    let includesDiagnostics: Bool
    let localeIdentifier: String
    let idempotencyKey: String
    var uploadedAttachmentIDs: [String]?

    init(
        snapshot: FeedbackSubmissionSnapshot,
        includesDiagnostics: Bool,
        localeIdentifier: String,
        idempotencyKey: String = UUID().uuidString,
        uploadedAttachmentIDs: [String]? = nil
    ) {
        self.snapshot = snapshot
        self.includesDiagnostics = includesDiagnostics
        self.localeIdentifier = localeIdentifier
        self.idempotencyKey = idempotencyKey
        self.uploadedAttachmentIDs = uploadedAttachmentIDs
    }

    func matches(
        snapshot: FeedbackSubmissionSnapshot,
        includesDiagnostics: Bool,
        localeIdentifier: String
    ) -> Bool {
        self.snapshot == snapshot
            && self.includesDiagnostics == includesDiagnostics
            && self.localeIdentifier == localeIdentifier
    }
}
