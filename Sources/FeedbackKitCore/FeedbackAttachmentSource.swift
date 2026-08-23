import Foundation

/// An attachment payload backed by either memory or a local file.
public struct FeedbackAttachmentSource: Identifiable, Sendable, Equatable {
    enum Storage: Sendable {
        case data(Data)
        case file(URL)
    }

    public let id: UUID
    public let filename: String
    public let contentType: String
    public let byteCount: Int
    public let width: Int?
    public let height: Int?
    public let durationMs: Int?
    let storage: Storage

    /// Materializes the attachment contents.
    ///
    /// This compatibility property returns empty data if a file-backed source can no longer
    /// be read. Use ``loadData()`` when the caller needs to handle read failures explicitly.
    public var data: Data {
        (try? loadData()) ?? Data()
    }

    public var fileURL: URL? {
        guard case let .file(url) = storage else { return nil }
        return url
    }

    public init(
        id: UUID = UUID(),
        filename: String,
        contentType: String,
        data: Data,
        width: Int? = nil,
        height: Int? = nil,
        durationMs: Int? = nil
    ) {
        self.id = id
        self.filename = filename
        self.contentType = contentType
        byteCount = data.count
        self.width = width
        self.height = height
        self.durationMs = durationMs
        storage = .data(data)
    }

    /// Creates a file-backed source without loading the file into memory.
    public init(
        id: UUID = UUID(),
        filename: String,
        contentType: String,
        fileURL: URL,
        width: Int? = nil,
        height: Int? = nil,
        durationMs: Int? = nil
    ) throws {
        guard fileURL.isFileURL else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        let standardizedURL = fileURL.standardizedFileURL
        let values = try standardizedURL.resourceValues(
            forKeys: [.fileSizeKey, .isRegularFileKey]
        )
        guard values.isRegularFile == true,
              let fileSize = values.fileSize,
              fileSize >= 0
        else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        self.id = id
        self.filename = filename
        self.contentType = contentType
        byteCount = fileSize
        self.width = width
        self.height = height
        self.durationMs = durationMs
        storage = .file(standardizedURL)
    }

    /// Materializes the attachment contents and reports file read failures.
    public func loadData() throws -> Data {
        switch storage {
        case let .data(data):
            return data
        case let .file(url):
            return try Data(contentsOf: url, options: .mappedIfSafe)
        }
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.id == rhs.id,
              lhs.filename == rhs.filename,
              lhs.contentType == rhs.contentType,
              lhs.byteCount == rhs.byteCount,
              lhs.width == rhs.width,
              lhs.height == rhs.height,
              lhs.durationMs == rhs.durationMs
        else { return false }
        switch (lhs.storage, rhs.storage) {
        case let (.data(lhsData), .data(rhsData)):
            return lhsData == rhsData
        case let (.file(lhsURL), .file(rhsURL)):
            return lhsURL == rhsURL
        case (.data, .file), (.file, .data):
            return false
        }
    }
}
