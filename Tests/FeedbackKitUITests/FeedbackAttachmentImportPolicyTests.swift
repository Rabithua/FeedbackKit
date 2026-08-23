@testable import FeedbackKitCore
@testable import FeedbackKitUI
import Testing
import UniformTypeIdentifiers

struct FeedbackAttachmentImportPolicyTests {
    private let policy = FeedbackAttachmentImportPolicy(
        limits: .init(count: 5, imageBytes: 100, videoBytes: 200)
    )

    @Test("Remaining attachment count never becomes negative")
    func remainingCountIsClamped() {
        #expect(policy.remainingCount(after: 2) == 3)
        #expect(policy.remainingCount(after: 5) == 0)
        #expect(policy.remainingCount(after: 8) == 0)
    }

    @Test("The first supported picker type is selected")
    func supportedTypeSelection() {
        #expect(policy.supportedType(in: [.pdf, .png]) == .png)
        #expect(policy.supportedType(in: [.pdf]) == nil)
    }

    @Test("Video and image attachments use separate byte limits")
    func mediaByteLimits() {
        #expect(policy.byteLimit(forMIMEType: "image/png") == 100)
        #expect(policy.byteLimit(forMIMEType: "video/mp4") == 200)
    }
}
