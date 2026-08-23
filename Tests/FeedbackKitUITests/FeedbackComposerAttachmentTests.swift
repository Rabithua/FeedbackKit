@testable import FeedbackKitCore
@testable import FeedbackKitUI
import Foundation
import Testing

private actor ComposerAttachmentCredential: FeedbackVisitorCredentialProviding {
    func credential(for productKey: String) async throws -> String {
        "visitor-credential"
    }

    func deleteCredential(for productKey: String) async throws {}
}

@MainActor
struct FeedbackComposerAttachmentTests {
    @Test("Removing an imported attachment deletes its temporary file")
    func removingImportedAttachmentReleasesTemporaryFile() throws {
        let originalURL = try makeOriginalFile()
        defer { try? FileManager.default.removeItem(at: originalURL.deletingLastPathComponent()) }
        var lease: FeedbackTemporaryFileLease? = try FeedbackTemporaryFileLease(
            copying: originalURL
        )
        let copiedURL = try #require(lease?.url)
        let source = try FeedbackAttachmentSource(
            filename: "attachment.png",
            contentType: "image/png",
            fileURL: copiedURL
        )
        let model = makeModel()
        model.addImportedAttachment(source, lease: try #require(lease))
        lease = nil

        #expect(FileManager.default.fileExists(atPath: copiedURL.path))
        model.removeAttachment(id: source.id)

        #expect(FileManager.default.fileExists(atPath: copiedURL.path) == false)
    }

    @Test("Composer deallocation deletes retained imported files")
    func composerDeallocationReleasesTemporaryFiles() throws {
        let originalURL = try makeOriginalFile()
        defer { try? FileManager.default.removeItem(at: originalURL.deletingLastPathComponent()) }
        var lease: FeedbackTemporaryFileLease? = try FeedbackTemporaryFileLease(
            copying: originalURL
        )
        let copiedURL = try #require(lease?.url)
        let source = try FeedbackAttachmentSource(
            filename: "attachment.png",
            contentType: "image/png",
            fileURL: copiedURL
        )
        var model: FeedbackComposerModel? = makeModel()
        model?.addImportedAttachment(source, lease: try #require(lease))
        lease = nil

        #expect(FileManager.default.fileExists(atPath: copiedURL.path))
        model = nil

        #expect(FileManager.default.fileExists(atPath: copiedURL.path) == false)
    }

    private func makeModel() -> FeedbackComposerModel {
        let product = FeedbackProduct(
            slug: "app",
            name: "App",
            defaultLocale: "en",
            defaultFeedbackVisibility: .private,
            iconUrl: nil,
            attachmentLimits: .init(count: 5, imageBytes: 100, videoBytes: 200),
            diagnostics: nil
        )
        let client = FeedbackClient(
            configuration: .init(
                baseURL: URL(string: "https://example.com/v1/api")!,
                productKey: "pk_test"
            ),
            credentialStore: ComposerAttachmentCredential()
        )
        let draftDirectory = FileManager.default.temporaryDirectory.appending(
            path: "FeedbackComposerAttachmentTests-Drafts-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        return FeedbackComposerModel(
            kind: .bug,
            product: product,
            client: client,
            draftStore: FeedbackDraftStore(directory: draftDirectory)
        )
    }

    private func makeOriginalFile() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "FeedbackComposerAttachmentTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let url = directory.appending(path: "original.png")
        try Data("image".utf8).write(to: url)
        return url
    }
}
