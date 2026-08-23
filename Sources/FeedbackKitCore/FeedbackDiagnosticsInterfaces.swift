import Foundation

public struct FeedbackDiagnosticSnapshot: Sendable {
    public let data: Data
    public let schemaVersion: Int
    public let sha256: String

    public init(data: Data, schemaVersion: Int, sha256: String) {
        self.data = data
        self.schemaVersion = schemaVersion
        self.sha256 = sha256
    }
}

public protocol FeedbackDiagnosticSnapshotProviding: Sendable {
    func makeDiagnosticSnapshot() async throws -> FeedbackDiagnosticSnapshot
    func makeDiagnosticSnapshot(maxBytes: Int) async throws -> FeedbackDiagnosticSnapshot
}

public extension FeedbackDiagnosticSnapshotProviding {
    /// Creates a snapshot that does not exceed the supplied server limit.
    ///
    /// The default implementation preserves compatibility with existing providers and validates
    /// their result. Providers should override this method when they can avoid collecting or
    /// encoding data beyond the limit in the first place.
    func makeDiagnosticSnapshot(maxBytes: Int) async throws -> FeedbackDiagnosticSnapshot {
        let snapshot = try await makeDiagnosticSnapshot()
        guard maxBytes >= 0, snapshot.data.count <= maxBytes else {
            throw FeedbackClientError.payloadTooLarge
        }
        return snapshot
    }
}

public protocol FeedbackDiagnosticsProviding: FeedbackDiagnosticSnapshotProviding {
    func recordNetwork(
        method: String,
        host: String,
        path: String,
        statusCode: Int?,
        duration: TimeInterval,
        errorCategory: String?
    ) async
}

public enum FeedbackDiagnosticDisplayLevel: String, Sendable {
    case debug
    case info
    case warning
    case error
    case critical
}

public struct FeedbackDiagnosticDisplayEvent: Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let level: FeedbackDiagnosticDisplayLevel
    public let category: String
    public let message: String

    public init(
        id: UUID,
        timestamp: Date,
        level: FeedbackDiagnosticDisplayLevel,
        category: String,
        message: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
    }
}

/// Optional management capability used by diagnostic inspection interfaces.
public protocol FeedbackDiagnosticsInspecting: FeedbackDiagnosticsProviding {
    func diagnosticDisplayEvents() async throws -> [FeedbackDiagnosticDisplayEvent]
    func exportDiagnosticsText() async throws -> String
    func clearDiagnostics() async throws
}
