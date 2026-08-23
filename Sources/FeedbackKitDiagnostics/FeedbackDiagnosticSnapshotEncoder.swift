import FeedbackKitCore
import Foundation

/// Encodes a diagnostic bundle without ever growing the destination buffer past its limit.
struct FeedbackDiagnosticSnapshotEncoder {
    private let maximumBytes: Int
    private let encoder: JSONEncoder

    init(maximumBytes: Int) {
        self.maximumBytes = maximumBytes
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
    }

    func encode(_ bundle: DiagnosticBundle) throws -> Data {
        guard maximumBytes >= 0 else {
            throw FeedbackClientError(kind: .payloadTooLarge)
        }

        let context = try encoder.encode(bundle.context)
        let generatedAt = try encoder.encode(bundle.generatedAt)
        let metricKitCrashSummary = try encoder.encode(bundle.metricKitCrashSummary)
        let schemaVersion = Data(String(bundle.schemaVersion).utf8)
        let baseSize = Self.fixedFragments.reduce(0) { $0 + $1.count }
            + context.count
            + generatedAt.count
            + metricKitCrashSummary.count
            + schemaVersion.count
            + Self.falseValue.count
        guard baseSize <= maximumBytes else {
            throw FeedbackClientError(kind: .payloadTooLarge)
        }

        var remainingBytes = maximumBytes - baseSize
        var truncated = bundle.truncated
        let customSnapshots = try encodedSuffix(
            bundle.customSnapshots,
            remainingBytes: &remainingBytes,
            truncated: &truncated
        )
        let events = try encodedSuffix(
            bundle.events,
            remainingBytes: &remainingBytes,
            truncated: &truncated
        )
        let breadcrumbs = try encodedSuffix(
            bundle.breadcrumbs,
            remainingBytes: &remainingBytes,
            truncated: &truncated
        )

        var writer = BoundedDataWriter(maximumBytes: maximumBytes)
        try writer.append(Self.openBreadcrumbs)
        try writer.appendJSONList(breadcrumbs)
        try writer.append(Self.contextKey)
        try writer.append(context)
        try writer.append(Self.openCustomSnapshots)
        try writer.appendJSONList(customSnapshots)
        try writer.append(Self.openEvents)
        try writer.appendJSONList(events)
        try writer.append(Self.generatedAtKey)
        try writer.append(generatedAt)
        try writer.append(Self.metricKitCrashSummaryKey)
        try writer.append(metricKitCrashSummary)
        try writer.append(Self.schemaVersionKey)
        try writer.append(schemaVersion)
        try writer.append(Self.truncatedKey)
        try writer.append(truncated ? Self.trueValue : Self.falseValue)
        try writer.append(Self.closeObject)
        return writer.data
    }

    private func encodedSuffix<Value: Encodable>(
        _ values: [Value],
        remainingBytes: inout Int,
        truncated: inout Bool
    ) throws -> [Data] {
        var reversedResult: [Data] = []
        for value in values.reversed() {
            let encoded = try encoder.encode(value)
            let separatorBytes = reversedResult.isEmpty ? 0 : 1
            guard encoded.count + separatorBytes <= remainingBytes else {
                truncated = true
                break
            }
            reversedResult.append(encoded)
            remainingBytes -= encoded.count + separatorBytes
        }
        if reversedResult.count < values.count { truncated = true }
        return reversedResult.reversed()
    }

    private static let openBreadcrumbs = Data(#"{"breadcrumbs":["#.utf8)
    private static let contextKey = Data(#"],"context":"#.utf8)
    private static let openCustomSnapshots = Data(#","customSnapshots":["#.utf8)
    private static let openEvents = Data(#"],"events":["#.utf8)
    private static let generatedAtKey = Data(#"],"generatedAt":"#.utf8)
    private static let metricKitCrashSummaryKey = Data(#","metricKitCrashSummary":"#.utf8)
    private static let schemaVersionKey = Data(#","schemaVersion":"#.utf8)
    private static let truncatedKey = Data(#","truncated":"#.utf8)
    private static let trueValue = Data("true".utf8)
    private static let falseValue = Data("false".utf8)
    private static let closeObject = Data("}".utf8)
    private static let fixedFragments = [
        openBreadcrumbs,
        contextKey,
        openCustomSnapshots,
        openEvents,
        generatedAtKey,
        metricKitCrashSummaryKey,
        schemaVersionKey,
        truncatedKey,
        closeObject,
    ]
}

private struct BoundedDataWriter {
    let maximumBytes: Int
    private(set) var data = Data()

    mutating func append(_ fragment: Data) throws {
        guard fragment.count <= maximumBytes - data.count else {
            throw FeedbackClientError(kind: .payloadTooLarge)
        }
        data.append(fragment)
    }

    mutating func appendJSONList(_ fragments: [Data]) throws {
        for (index, fragment) in fragments.enumerated() {
            if index > 0 { try append(Data([0x2C])) }
            try append(fragment)
        }
    }
}
