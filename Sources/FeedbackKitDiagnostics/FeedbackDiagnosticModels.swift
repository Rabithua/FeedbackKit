import Foundation

public enum FeedbackLogLevel: String, Codable, CaseIterable, Sendable {
    case debug
    case info
    case warning
    case error
    case critical

    var diagnosticPriority: Int {
        switch self {
        case .debug: 0
        case .info: 1
        case .warning: 2
        case .error: 3
        case .critical: 4
        }
    }
}

public struct FeedbackDiagnosticEvent: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let level: FeedbackLogLevel
    public let category: String
    public let message: String
    public let metadata: [String: String]
    public let file: String?
    public let function: String?
    public let line: UInt?

    public init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        level: FeedbackLogLevel,
        category: String,
        message: String,
        metadata: [String: String] = [:],
        file: String? = nil,
        function: String? = nil,
        line: UInt? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
        self.metadata = metadata
        self.file = file
        self.function = function
        self.line = line
    }
}

public struct FeedbackBreadcrumb: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case page; case action; case network }

    public let id: UUID
    public let timestamp: Date
    public let kind: Kind
    public let name: String
    public let metadata: [String: String]

    public init(id: UUID = UUID(), timestamp: Date = .now, kind: Kind, name: String, metadata: [String: String] = [:]) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.name = name
        self.metadata = metadata
    }
}

public protocol FeedbackDiagnosticSource: Sendable {
    func diagnosticEvents() async throws -> [FeedbackDiagnosticEvent]
    func diagnosticBreadcrumbs() async throws -> [FeedbackBreadcrumb]
    func diagnosticSnapshotData() async throws -> Data?
    func clearDiagnostics() async throws
}

public extension FeedbackDiagnosticSource {
    func diagnosticEvents() async throws -> [FeedbackDiagnosticEvent] { [] }
    func diagnosticBreadcrumbs() async throws -> [FeedbackBreadcrumb] { [] }
    func diagnosticSnapshotData() async throws -> Data? { nil }
    func clearDiagnostics() async throws {}
}

public struct FeedbackDiagnosticsConfiguration: Sendable {
    public let retentionDays: Int
    public let maximumEventCount: Int
    public let maximumDiskBytes: Int
    public let maximumSnapshotBytes: Int
    public let directory: URL?

    public init(
        retentionDays: Int = 7,
        maximumEventCount: Int = 500,
        maximumDiskBytes: Int = 2 * 1024 * 1024,
        maximumSnapshotBytes: Int = 256 * 1024,
        directory: URL? = nil
    ) {
        self.retentionDays = max(1, retentionDays)
        self.maximumEventCount = max(1, maximumEventCount)
        self.maximumDiskBytes = max(16 * 1024, maximumDiskBytes)
        self.maximumSnapshotBytes = max(16 * 1024, maximumSnapshotBytes)
        self.directory = directory
    }
}

struct StoredDiagnosticRecord: Codable, Sendable {
    enum Kind: String, Codable, Sendable { case event; case breadcrumb }
    let kind: Kind
    let timestamp: Date
    let event: FeedbackDiagnosticEvent?
    let breadcrumb: FeedbackBreadcrumb?
}

struct DiagnosticBundle: Codable, Sendable {
    let schemaVersion: Int
    let generatedAt: Date
    let context: FeedbackKitCore.FeedbackClientContext
    var events: [FeedbackDiagnosticEvent]
    var breadcrumbs: [FeedbackBreadcrumb]
    let metricKitCrashSummary: String?
    var customSnapshots: [String]
    var truncated: Bool
}

import FeedbackKitCore
