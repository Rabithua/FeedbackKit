import Foundation

// The URL is immutable, and cleanup is performed only once during deinitialization.
final class FeedbackTemporaryFileLease: @unchecked Sendable {
    let url: URL

    init(copying sourceURL: URL) throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "FeedbackKit/Attachments",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let pathExtension = sourceURL.pathExtension
        let filename = UUID().uuidString
            + (pathExtension.isEmpty ? "" : ".\(pathExtension)")
        let destination = directory.appending(path: filename)
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        url = destination.standardizedFileURL
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
