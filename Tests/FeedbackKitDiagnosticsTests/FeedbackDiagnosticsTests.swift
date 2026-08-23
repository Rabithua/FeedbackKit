import FeedbackKitCore
import FeedbackKitDiagnostics
import Foundation
import Testing

private actor SensitiveSource: FeedbackDiagnosticSource {
    var cleared = false
    func diagnosticEvents() async throws -> [FeedbackDiagnosticEvent] {
        [.init(level: .error, category: "source", message: "Authorization: Bearer secret-token", metadata: ["email": "person@example.com"])]
    }
    func diagnosticSnapshotData() async throws -> Data? { Data("token=super-secret".utf8) }
    func clearDiagnostics() async throws { cleared = true }
}

private actor BudgetRecordingSource: FeedbackDiagnosticSource {
    private(set) var requestedMaximumBytes: Int?

    func diagnosticSnapshotData(maxBytes: Int) async throws -> Data? {
        requestedMaximumBytes = maxBytes
        return Data(repeating: 0x20, count: maxBytes)
    }
}

private struct LegacyOversizedSource: FeedbackDiagnosticSource {
    let byteCount: Int

    func diagnosticSnapshotData() async throws -> Data? {
        Data(repeating: 0x78, count: byteCount)
    }
}

struct FeedbackDiagnosticsTests {
    @Test func redactsBeforePersistence() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let diagnostics = makeDiagnostics(directory: directory)
        await diagnostics.record(.init(level: .error, category: "network", message: "Authorization: Bearer abc.def.ghi person@example.com https://example.com/path?token=secret", metadata: ["apiKey": "pk_secretvalue"]))
        let event = try #require(await diagnostics.events().first)
        #expect(event.message.contains("person@example.com") == false)
        #expect(event.message.contains("token=secret") == false)
        #expect(event.metadata["apiKey"] == "[REDACTED]")
        let disk = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).map { try String(contentsOf: $0, encoding: .utf8) }.joined()
        #expect(disk.contains("person@example.com") == false)
        #expect(disk.contains("pk_secretvalue") == false)
    }

    @Test func redactsQuotedAndNestedJSONSecrets() {
        let input = #"{"password":"dummy-password","nested":{"client_secret":"client-value","sessionToken":"session-value"},"items":[{"credential":"credential-value"}],"safe":"visible"}"#

        let output = FeedbackRedactor().redact(input)

        #expect(output.contains("dummy-password") == false)
        #expect(output.contains("client-value") == false)
        #expect(output.contains("session-value") == false)
        #expect(output.contains("credential-value") == false)
        #expect(output.contains("visible") == true)
        #expect(output.contains("[REDACTED]") == true)
    }

    @Test func redactsQuotedSecretKeysEmbeddedInText() {
        let output = FeedbackRedactor().redact(#"request failed: {"password":"dummy-password","client_secret":"client-value"}"#)

        #expect(output.contains("dummy-password") == false)
        #expect(output.contains("client-value") == false)
    }

    @Test func redactsStructuredKeysAndNumericPhoneValuesWithoutDroppingCollisions() throws {
        let input = #"{"person@example.com":"first","other@example.com":"second","https://example.com?token=secret":"third","identifier":15551234567}"#

        let output = FeedbackRedactor().redact(input)
        let object = try #require(
            JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any]
        )

        #expect(output.contains("person@example.com") == false)
        #expect(output.contains("other@example.com") == false)
        #expect(output.contains("token=secret") == false)
        #expect(output.contains("15551234567") == false)
        #expect(object.count == 4)
        #expect(Set(object.values.compactMap { $0 as? String }).isSuperset(of: [
            "first", "second", "[REDACTED]", "[REDACTED_PHONE]",
        ]))
    }

    @Test func redactsSensitiveMetadataKeysWithoutDroppingCollisions() {
        let output = FeedbackRedactor().redact(metadata: [
            "person@example.com": "first",
            "other@example.com": "second",
        ])

        #expect(output.keys.contains { $0.contains("example.com") } == false)
        #expect(output.count == 2)
        #expect(Set(output.values) == ["first", "second"])
    }

    @Test func appliesCountRetentionUnderConcurrentWrites() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let diagnostics = FeedbackDiagnostics(configuration: .init(retentionDays: 7, maximumEventCount: 25, maximumDiskBytes: 512 * 1024, directory: directory))
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<100 {
                group.addTask { await diagnostics.record(.init(level: .warning, category: "test", message: "Event \(index)")) }
            }
        }
        #expect(try await diagnostics.events().count == 25)
    }

    @Test func snapshotFiltersLevelsRedactsSourcesAndStaysWithinLimit() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let diagnostics = makeDiagnostics(directory: directory, snapshotBytes: 24 * 1024)
        let source = SensitiveSource()
        await diagnostics.register(source: source, id: "source")
        await diagnostics.record(.init(level: .info, category: "test", message: "Not included"))
        for index in 0..<200 {
            await diagnostics.record(.init(level: .error, category: "test", message: String(repeating: "x", count: 300) + " \(index)"))
            await diagnostics.record(.init(kind: .action, name: "Tap \(index)", metadata: ["url": "https://example.com?a=secret"]))
        }
        let snapshot = try await diagnostics.makeDiagnosticSnapshot()
        #expect(snapshot.schemaVersion == 1)
        #expect(snapshot.data.count <= 24 * 1024)
        let text = String(decoding: snapshot.data, as: UTF8.self)
        #expect(text.contains("Not included") == false)
        #expect(text.contains("person@example.com") == false)
        #expect(text.contains("super-secret") == false)
        #expect(text.contains("\"truncated\":true") == true)
    }

    @Test(arguments: [512, 8 * 1024, 16 * 1024])
    func explicitSnapshotLimitBoundsSourceCollectionAndProducesValidJSON(
        maximumBytes: Int
    ) async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let diagnostics = makeDiagnostics(directory: directory)
        let source = BudgetRecordingSource()
        await diagnostics.register(source: source, id: "budget")

        let snapshot = try await diagnostics.makeDiagnosticSnapshot(maxBytes: maximumBytes)
        let object = try #require(
            JSONSerialization.jsonObject(with: snapshot.data) as? [String: Any]
        )

        #expect(await source.requestedMaximumBytes == maximumBytes)
        #expect(snapshot.data.count <= maximumBytes)
        #expect(object["schemaVersion"] as? Int == 1)
    }

    @Test func customSnapshotSourcesShareOneCollectionBudget() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let diagnostics = makeDiagnostics(directory: directory)
        let sources = [BudgetRecordingSource(), BudgetRecordingSource(), BudgetRecordingSource()]
        for (index, source) in sources.enumerated() {
            await diagnostics.register(source: source, id: "budget-\(index)")
        }

        let maximumBytes = 96 * 1024
        let snapshot = try await diagnostics.makeDiagnosticSnapshot(maxBytes: maximumBytes)
        var requestedLimits: [Int] = []
        var skippedSourceCount = 0
        for source in sources {
            if let requestedMaximumBytes = await source.requestedMaximumBytes {
                requestedLimits.append(requestedMaximumBytes)
            } else {
                skippedSourceCount += 1
            }
        }

        #expect(requestedLimits.sorted() == [32 * 1024, 64 * 1024])
        #expect(skippedSourceCount == 1)
        #expect(snapshot.data.count <= maximumBytes)
    }

    @Test func legacySourceClippingMarksTheSnapshotAsTruncated() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let diagnostics = makeDiagnostics(directory: directory)
        await diagnostics.register(
            source: LegacyOversizedSource(byteCount: 64 * 1024 + 1),
            id: "legacy"
        )

        let snapshot = try await diagnostics.makeDiagnosticSnapshot(maxBytes: 128 * 1024)
        let object = try #require(
            JSONSerialization.jsonObject(with: snapshot.data) as? [String: Any]
        )

        #expect(object["truncated"] as? Bool == true)
    }

    @Test func boundedSnapshotRetainsNewestEvents() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let diagnostics = makeDiagnostics(directory: directory)
        for index in 0..<40 {
            await diagnostics.record(.init(
                level: .error,
                category: "retention",
                message: "event-\(index)-" + String(repeating: "x", count: 800)
            ))
        }

        let snapshot = try await diagnostics.makeDiagnosticSnapshot(maxBytes: 16 * 1024)
        let object = try #require(
            JSONSerialization.jsonObject(with: snapshot.data) as? [String: Any]
        )
        let events = try #require(object["events"] as? [[String: Any]])
        let messages = events.compactMap { $0["message"] as? String }

        #expect(snapshot.data.count <= 16 * 1024)
        #expect(messages.contains { $0.hasPrefix("event-39-") })
        #expect(messages.contains { $0.hasPrefix("event-0-") } == false)
        #expect(object["truncated"] as? Bool == true)
    }

    @Test func snapshotMetadataUsesTheSubmissionLocale() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let diagnostics = FeedbackDiagnostics(
            configuration: .init(directory: directory),
            metadataProvider: DefaultFeedbackAppMetadataProvider()
        )

        let snapshot = try await diagnostics.makeDiagnosticSnapshot(
            maxBytes: 16 * 1024,
            locale: Locale(identifier: "zh_Hant_TW")
        )
        let object = try #require(
            JSONSerialization.jsonObject(with: snapshot.data) as? [String: Any]
        )
        let context = try #require(object["context"] as? [String: Any])

        #expect(context["locale"] as? String == "zh-Hant-TW")
    }

    @Test func clearRemovesLocalAndRegisteredSourceData() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let diagnostics = makeDiagnostics(directory: directory)
        let source = SensitiveSource()
        await diagnostics.register(source: source, id: "source")
        await diagnostics.record(.init(level: .critical, category: "test", message: "Failure"))
        try await diagnostics.clear()
        #expect(try await diagnostics.events().isEmpty == true)
        #expect(await source.cleared == true)
    }

    @Test func inspectionCapabilityMapsExportsAndClearsDiagnostics() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let diagnostics = makeDiagnostics(directory: directory)
        let inspector: any FeedbackDiagnosticsInspecting = diagnostics
        await diagnostics.record(.init(
            level: .warning,
            category: "inspection",
            message: "Visible warning"
        ))

        let event = try #require(await inspector.diagnosticDisplayEvents().first)

        #expect(event.level == .warning)
        #expect(event.category == "inspection")
        #expect(event.message == "Visible warning")
        #expect(try await inspector.exportDiagnosticsText().contains("Visible warning"))
        try await inspector.clearDiagnostics()
        #expect(try await inspector.diagnosticDisplayEvents().isEmpty)
    }

    private func makeDiagnostics(directory: URL, snapshotBytes: Int = 256 * 1024) -> FeedbackDiagnostics {
        FeedbackDiagnostics(
            configuration: .init(retentionDays: 7, maximumEventCount: 500, maximumDiskBytes: 2 * 1024 * 1024, maximumSnapshotBytes: snapshotBytes, directory: directory),
            metadataProvider: FixedMetadata()
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "FeedbackKitDiagnosticsTests-\(UUID().uuidString)")
    }
}

private struct FixedMetadata: FeedbackAppMetadataProvider {
    func clientContext(locale: Locale) async -> FeedbackClientContext {
        .init(appVersion: "1.0", buildNumber: "1", osVersion: "TestOS", deviceCategory: "phone", locale: "en")
    }
}
