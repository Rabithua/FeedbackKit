@testable import FeedbackKitCore
@testable import FeedbackKitUI
import Foundation
import Testing

private actor InspectingDiagnostics: FeedbackDiagnosticsInspecting {
    private var events: [FeedbackDiagnosticDisplayEvent]
    private(set) var clearCount = 0

    init(events: [FeedbackDiagnosticDisplayEvent]) {
        self.events = events
    }

    func makeDiagnosticSnapshot() async throws -> FeedbackDiagnosticSnapshot {
        .init(data: Data(), schemaVersion: 1, sha256: "")
    }

    func recordNetwork(
        method: String,
        host: String,
        path: String,
        statusCode: Int?,
        duration: TimeInterval,
        errorCategory: String?
    ) async {}

    func diagnosticDisplayEvents() async throws -> [FeedbackDiagnosticDisplayEvent] {
        events
    }

    func exportDiagnosticsText() async throws -> String {
        events.map(\.message).joined(separator: "\n")
    }

    func clearDiagnostics() async throws {
        events.removeAll()
        clearCount += 1
    }
}

@MainActor
struct FeedbackDiagnosticsModelTests {
    @Test func modelLoadsFiltersAndClearsThroughTheCoreInspectionCapability() async throws {
        let diagnostics = InspectingDiagnostics(events: [
            .init(
                id: UUID(),
                timestamp: Date(timeIntervalSince1970: 1),
                level: .warning,
                category: "network",
                message: "Warning"
            ),
            .init(
                id: UUID(),
                timestamp: Date(timeIntervalSince1970: 2),
                level: .error,
                category: "storage",
                message: "Error"
            ),
        ])
        let model = FeedbackDiagnosticsModel(diagnostics: diagnostics)

        await model.load()
        model.filter = .error

        #expect(model.events.map(\.message) == ["Error", "Warning"])
        #expect(model.filtered.map(\.message) == ["Error"])
        #expect(model.exportText == "Warning\nError")
        #expect(await model.clear())
        #expect(model.events.isEmpty)
        #expect(await diagnostics.clearCount == 1)
    }
}
