import FeedbackKitCore
import Foundation

struct FeedbackSubmissionSnapshot: Equatable, Sendable {
    let kind: FeedbackKind
    let title: String
    let body: String
    let includesDiagnostics: Bool
    let attachments: [FeedbackAttachmentSource]

    var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedBody: String {
        body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func withIncludesDiagnostics(_ includesDiagnostics: Bool) -> Self {
        Self(
            kind: kind,
            title: title,
            body: body,
            includesDiagnostics: includesDiagnostics,
            attachments: attachments
        )
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.kind == rhs.kind
            && lhs.title == rhs.title
            && lhs.body == rhs.body
            && lhs.includesDiagnostics == rhs.includesDiagnostics
            && lhs.attachments.elementsEqual(rhs.attachments, by: attachmentsAreEqual)
    }

    private static func attachmentsAreEqual(
        _ lhs: FeedbackAttachmentSource,
        _ rhs: FeedbackAttachmentSource
    ) -> Bool {
        lhs == rhs
    }
}
