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
