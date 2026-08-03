import Foundation

public struct FeedbackDraft: Codable, Equatable, Sendable {
    public let productSlug: String
    public var kind: FeedbackKind
    public var title: String
    public var body: String
    public var includesDiagnostics: Bool
    public var updatedAt: Date

    public init(productSlug: String, kind: FeedbackKind, title: String, body: String, includesDiagnostics: Bool, updatedAt: Date = .now) {
        self.productSlug = productSlug
        self.kind = kind
        self.title = title
        self.body = body
        self.includesDiagnostics = includesDiagnostics
        self.updatedAt = updatedAt
    }

    public var isEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public actor FeedbackDraftStore {
    private let directory: URL

    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.directory = base.appending(path: "FeedbackKit/Drafts", directoryHint: .isDirectory)
        }
    }

    public func load(productSlug: String) -> FeedbackDraft? {
        try? FeedbackCoding.decoder().decode(FeedbackDraft.self, from: Data(contentsOf: url(productSlug)))
    }

    public func save(_ draft: FeedbackDraft) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FeedbackCoding.encoder().encode(draft).write(to: url(draft.productSlug), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var folder = directory
        try? folder.setResourceValues(values)
    }

    public func remove(productSlug: String) throws {
        let target = url(productSlug)
        if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
    }

    private func url(_ slug: String) -> URL {
        let safe = slug.replacingOccurrences(of: "/", with: "_")
        return directory.appending(path: "\(safe).json")
    }
}
