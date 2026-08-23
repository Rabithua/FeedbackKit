import CryptoKit
import FeedbackKitCore
import Foundation
import OSLog

public struct FeedbackLogger: Sendable {
    private let store: FeedbackDiagnosticStore
    private let redactor: FeedbackRedactor
    private let subsystem: String

    init(store: FeedbackDiagnosticStore, redactor: FeedbackRedactor, subsystem: String) {
        self.store = store
        self.redactor = redactor
        self.subsystem = subsystem
    }

    public func debug(_ message: String, category: String = "app", metadata: [String: String] = [:], file: String = #fileID, function: String = #function, line: UInt = #line) {
        log(.debug, message, category: category, metadata: metadata, file: file, function: function, line: line)
    }

    public func info(_ message: String, category: String = "app", metadata: [String: String] = [:], file: String = #fileID, function: String = #function, line: UInt = #line) {
        log(.info, message, category: category, metadata: metadata, file: file, function: function, line: line)
    }

    public func warning(_ message: String, category: String = "app", metadata: [String: String] = [:], file: String = #fileID, function: String = #function, line: UInt = #line) {
        log(.warning, message, category: category, metadata: metadata, file: file, function: function, line: line)
    }

    public func error(_ message: String, category: String = "app", metadata: [String: String] = [:], file: String = #fileID, function: String = #function, line: UInt = #line) {
        log(.error, message, category: category, metadata: metadata, file: file, function: function, line: line)
    }

    public func critical(_ message: String, category: String = "app", metadata: [String: String] = [:], file: String = #fileID, function: String = #function, line: UInt = #line) {
        log(.critical, message, category: category, metadata: metadata, file: file, function: function, line: line)
    }

    public func log(_ level: FeedbackLogLevel, _ message: String, category: String, metadata: [String: String] = [:], file: String? = nil, function: String? = nil, line: UInt? = nil) {
        let event = redactor.event(
            FeedbackDiagnosticEvent(
                level: level,
                category: category,
                message: message,
                metadata: metadata,
                file: file,
                function: function,
                line: line
            )
        )
        let logger = Logger(subsystem: subsystem, category: event.category)
        switch level {
        case .debug: logger.debug("\(event.message, privacy: .public)")
        case .info: logger.info("\(event.message, privacy: .public)")
        case .warning: logger.warning("\(event.message, privacy: .public)")
        case .error: logger.error("\(event.message, privacy: .public)")
        case .critical: logger.critical("\(event.message, privacy: .public)")
        }
        Task { try? await store.append(event: event) }
    }
}

public final class FeedbackDiagnostics: FeedbackDiagnosticsProviding, @unchecked Sendable {
    public let logger: FeedbackLogger

    private let configuration: FeedbackDiagnosticsConfiguration
    private let store: FeedbackDiagnosticStore
    private let redactor: FeedbackRedactor
    private let metadataProvider: any FeedbackAppMetadataProvider
    private let state = FeedbackDiagnosticState()
    #if os(iOS)
    private let metricSubscriber: FeedbackMetricSubscriber
    #endif

    public init(
        configuration: FeedbackDiagnosticsConfiguration = .init(),
        metadataProvider: any FeedbackAppMetadataProvider = DefaultFeedbackAppMetadataProvider(),
        subsystem: String = Bundle.main.bundleIdentifier ?? "FeedbackKit"
    ) {
        self.configuration = configuration
        self.metadataProvider = metadataProvider
        let store = FeedbackDiagnosticStore(configuration: configuration)
        let redactor = FeedbackRedactor()
        self.store = store
        self.redactor = redactor
        logger = FeedbackLogger(store: store, redactor: redactor, subsystem: subsystem)
        #if os(iOS)
        metricSubscriber = FeedbackMetricSubscriber(state: state, redactor: redactor)
        metricSubscriber.start()
        #endif
    }

    deinit {
        #if os(iOS)
        metricSubscriber.stop()
        #endif
    }

    public func register(source: any FeedbackDiagnosticSource, id: String = UUID().uuidString) async {
        await state.register(source: source, id: id)
    }

    public func unregisterSource(id: String) async {
        await state.unregister(id: id)
    }

    public func breadcrumb(_ kind: FeedbackBreadcrumb.Kind, name: String, metadata: [String: String] = [:]) {
        let breadcrumb = redactor.breadcrumb(FeedbackBreadcrumb(kind: kind, name: name, metadata: metadata))
        Task { try? await store.append(breadcrumb: breadcrumb) }
    }

    public func record(_ event: FeedbackDiagnosticEvent) async {
        try? await store.append(event: redactor.event(event))
    }

    public func record(_ breadcrumb: FeedbackBreadcrumb) async {
        try? await store.append(breadcrumb: redactor.breadcrumb(breadcrumb))
    }

    public func recordNetwork(method: String, host: String, path: String, statusCode: Int?, duration: TimeInterval, errorCategory: String?) async {
        var metadata = [
            "method": method,
            "host": host,
            "path": path,
            "duration_ms": String(Int(duration * 1_000)),
        ]
        if let statusCode { metadata["status"] = String(statusCode) }
        if let errorCategory { metadata["error"] = errorCategory }
        let breadcrumb = redactor.breadcrumb(
            FeedbackBreadcrumb(kind: .network, name: "\(method) \(path)", metadata: metadata)
        )
        try? await store.append(breadcrumb: breadcrumb)
    }

    public func events() async throws -> [FeedbackDiagnosticEvent] {
        try await store.records().compactMap(\.event)
    }

    public func breadcrumbs() async throws -> [FeedbackBreadcrumb] {
        try await store.records().compactMap(\.breadcrumb)
    }

    public func exportText() async throws -> String {
        try await store.exportText()
    }

    public func clear() async throws {
        try await store.clear()
        let sources = await state.sources()
        for source in sources { try await source.clearDiagnostics() }
        await state.clearMetricSummary()
    }

    public func makeDiagnosticSnapshot() async throws -> FeedbackDiagnosticSnapshot {
        try await makeDiagnosticSnapshot(maxBytes: configuration.maximumSnapshotBytes)
    }

    public func makeDiagnosticSnapshot(maxBytes: Int) async throws -> FeedbackDiagnosticSnapshot {
        let maximumBytes = min(configuration.maximumSnapshotBytes, max(0, maxBytes))
        let now = Date()
        let sources = await state.sources()
        var records = try await store.records()
        var customSnapshots: [String] = []
        var sourceDataTruncated = false
        for source in sources {
            try Task.checkCancellation()
            let sourceEvents = try await source.diagnosticEvents().map(redactor.event)
            let sourceBreadcrumbs = try await source.diagnosticBreadcrumbs().map(redactor.breadcrumb)
            records.append(contentsOf: sourceEvents.map { StoredDiagnosticRecord(kind: .event, timestamp: $0.timestamp, event: $0, breadcrumb: nil) })
            records.append(contentsOf: sourceBreadcrumbs.map { StoredDiagnosticRecord(kind: .breadcrumb, timestamp: $0.timestamp, event: nil, breadcrumb: $0) })
            let sourceLimit = min(64 * 1024, maximumBytes)
            if let data = try await source.diagnosticSnapshotData(maxBytes: sourceLimit) {
                sourceDataTruncated = sourceDataTruncated || data.count > sourceLimit
                let sourceText = String(decoding: data.prefix(sourceLimit), as: UTF8.self)
                customSnapshots.append(
                    redactor.redact(sourceText).feedbackUTF8Prefix(maxBytes: sourceLimit)
                )
            }
        }
        let eventCutoff = now.addingTimeInterval(-30 * 60)
        let events = records.compactMap(\.event)
            .filter { $0.timestamp >= eventCutoff && $0.level.diagnosticPriority >= FeedbackLogLevel.warning.diagnosticPriority }
            .sorted { $0.timestamp < $1.timestamp }
            .suffix(200)
        let breadcrumbs = records.compactMap(\.breadcrumb)
            .sorted { $0.timestamp < $1.timestamp }
            .suffix(100)
        let rawContext = await metadataProvider.clientContext(locale: .current)
        let context = boundedContext(rawContext, maximumBytes: maximumBytes)
        let rawMetric = await state.metricSummary(since: now.addingTimeInterval(-7 * 86_400))
        let metric = rawMetric.map {
            $0.feedbackUTF8Prefix(maxBytes: maximumBytes / 8)
        }
        let bundle = DiagnosticBundle(
            schemaVersion: 1,
            generatedAt: now,
            context: context,
            events: Array(events),
            breadcrumbs: Array(breadcrumbs),
            metricKitCrashSummary: metric.map(redactor.redact),
            customSnapshots: customSnapshots,
            truncated: sourceDataTruncated || context != rawContext || metric != rawMetric
        )
        let data = try FeedbackDiagnosticSnapshotEncoder(maximumBytes: maximumBytes).encode(bundle)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return FeedbackDiagnosticSnapshot(data: data, schemaVersion: 1, sha256: digest)
    }

    private func boundedContext(
        _ context: FeedbackClientContext,
        maximumBytes: Int
    ) -> FeedbackClientContext {
        let fieldLimit = maximumBytes / 128
        return FeedbackClientContext(
            appVersion: context.appVersion.feedbackUTF8Prefix(maxBytes: fieldLimit),
            buildNumber: context.buildNumber.feedbackUTF8Prefix(maxBytes: fieldLimit),
            osVersion: context.osVersion.feedbackUTF8Prefix(maxBytes: fieldLimit),
            deviceCategory: context.deviceCategory.feedbackUTF8Prefix(maxBytes: fieldLimit),
            locale: context.locale.feedbackUTF8Prefix(maxBytes: fieldLimit)
        )
    }
}

private extension String {
    func feedbackUTF8Prefix(maxBytes: Int) -> String {
        guard maxBytes > 0, utf8.count > maxBytes else {
            return maxBytes > 0 ? self : ""
        }
        var data = Data(utf8.prefix(maxBytes))
        while String(data: data, encoding: .utf8) == nil, data.isEmpty == false {
            data.removeLast()
        }
        return String(decoding: data, as: UTF8.self)
    }
}

private actor FeedbackDiagnosticState {
    private var registeredSources: [String: any FeedbackDiagnosticSource] = [:]
    private var latestMetric: (date: Date, summary: String)?

    func register(source: any FeedbackDiagnosticSource, id: String) { registeredSources[id] = source }
    func unregister(id: String) { registeredSources[id] = nil }
    func sources() -> [any FeedbackDiagnosticSource] { Array(registeredSources.values) }
    func storeMetric(_ summary: String, date: Date = .now) { latestMetric = (date, summary) }
    func metricSummary(since cutoff: Date) -> String? {
        guard let latestMetric, latestMetric.date >= cutoff else { return nil }
        return latestMetric.summary
    }
    func clearMetricSummary() { latestMetric = nil }
}

#if os(iOS)
import MetricKit

private final class FeedbackMetricSubscriber: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    private let state: FeedbackDiagnosticState
    private let redactor: FeedbackRedactor

    init(state: FeedbackDiagnosticState, redactor: FeedbackRedactor) {
        self.state = state
        self.redactor = redactor
    }

    func start() { MXMetricManager.shared.add(self) }
    func stop() { MXMetricManager.shared.remove(self) }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        guard let latest = payloads.last,
              let summary = String(data: latest.jsonRepresentation(), encoding: .utf8)
        else { return }
        let redacted = redactor.redact(summary)
        Task { await state.storeMetric(redacted) }
    }
}
#endif
