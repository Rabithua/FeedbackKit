import FeedbackKitCore
import Observation

@MainActor
@Observable
final class FeedbackDiagnosticsModel {
    enum Filter: String, CaseIterable, Identifiable {
        case all
        case warning
        case error
        case critical

        var id: Self { self }
    }

    var events: [FeedbackDiagnosticDisplayEvent] = []
    var filter: Filter = .all
    var exportText = ""
    var isLoading = false
    var error: Error?
    let diagnostics: any FeedbackDiagnosticsInspecting

    init(diagnostics: any FeedbackDiagnosticsInspecting) {
        self.diagnostics = diagnostics
    }

    var filtered: [FeedbackDiagnosticDisplayEvent] {
        switch filter {
        case .all:
            events
        case .warning:
            events.filter { $0.level == .warning }
        case .error:
            events.filter { $0.level == .error }
        case .critical:
            events.filter { $0.level == .critical }
        }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            events = try await diagnostics.diagnosticDisplayEvents()
                .sorted { $0.timestamp > $1.timestamp }
            exportText = try await diagnostics.exportDiagnosticsText()
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error
        }
    }

    func clear() async -> Bool {
        do {
            try await diagnostics.clearDiagnostics()
            await load()
            return true
        } catch is CancellationError {
            return false
        } catch {
            self.error = error
            return false
        }
    }
}
