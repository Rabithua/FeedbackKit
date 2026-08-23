import FeedbackKitCore
import Foundation
import Observation

@MainActor
@Observable
final class DemoLiveModel {
    let client: FeedbackClient?
    let configurationError: String?

    private(set) var integration: FeedbackIntegrationSummary?
    private(set) var verificationError: String?
    private(set) var isVerifying = false

    init(bundle: Bundle = .main) {
        do {
            client = try DemoClientFactory.live(bundle: bundle)
            configurationError = nil
        } catch {
            client = nil
            configurationError = error.localizedDescription
        }
    }

    func verifyIntegration() async {
        guard let client else { return }
        isVerifying = true
        verificationError = nil
        integration = nil
        defer { isVerifying = false }

        do {
            integration = try await client.verifyIntegration(locale: .current)
        } catch is CancellationError {
            return
        } catch {
            verificationError = Self.message(for: error)
        }
    }

    private static func message(for error: Error) -> String {
        guard let clientError = error as? FeedbackClientError else {
            return error.localizedDescription
        }
        let requestID = clientError.context.requestID.map { " Request ID: \($0)." } ?? ""
        return "\(clientError.localizedDescription)\(requestID)"
    }
}
