import Foundation

/// Describes whether the host and Product are ready for user-authorized diagnostics.
public enum FeedbackDiagnosticsReadiness: Equatable, Sendable {
    case disabled
    case providerMissing(maxBytes: Int)
    case unsupportedSchema([Int])
    case ready(maxBytes: Int)
}

/// The Product binding and diagnostics state returned by integration verification.
public struct FeedbackIntegrationSummary: Equatable, Sendable {
    public let product: FeedbackProduct
    public let diagnostics: FeedbackDiagnosticsReadiness

    public init(
        product: FeedbackProduct,
        diagnostics: FeedbackDiagnosticsReadiness
    ) {
        self.product = product
        self.diagnostics = diagnostics
    }
}
