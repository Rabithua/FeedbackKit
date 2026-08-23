import Foundation

/// A categorized client failure with sanitized developer context.
public struct FeedbackClientError: Error, Equatable, Sendable {
    /// The stable category used for programmatic error handling.
    public enum Kind: String, Equatable, Sendable {
        case invalidURL
        case offline
        case transport
        case invalidResponse
        case decoding
        case unauthorized
        case forbidden
        case notFound
        case payloadTooLarge
        case validation
        case rateLimited
        case server
        case diagnosticsUnavailable
        case diagnosticUploadFailed
    }

    /// The stable failure category.
    public let kind: Kind
    /// Sanitized metadata for diagnostics and support workflows.
    public let context: FeedbackFailureContext

    public init(
        kind: Kind,
        context: FeedbackFailureContext = FeedbackFailureContext()
    ) {
        self.kind = kind
        self.context = context
    }
}

extension FeedbackClientError: LocalizedError {
    public var errorDescription: String? {
        switch kind {
        case .invalidURL: "Invalid FeedbackServer URL."
        case .offline: "You appear to be offline."
        case .transport: "The network request failed."
        case .invalidResponse: "FeedbackServer returned an invalid response."
        case .decoding: "FeedbackServer returned unsupported data."
        case .unauthorized: "The anonymous identity is not authorized."
        case .forbidden: "This action is not permitted."
        case .notFound: "This content is unavailable."
        case .payloadTooLarge: "The data exceeds the server limit."
        case .validation: "Some submitted values are invalid."
        case .rateLimited: "Too many requests. Please try again later."
        case .server:
            if let statusCode = context.statusCode {
                "FeedbackServer returned HTTP \(statusCode)."
            } else {
                "FeedbackServer returned an error."
            }
        case .diagnosticsUnavailable: "Diagnostics are not available for this product."
        case .diagnosticUploadFailed: "The private diagnostic upload failed."
        }
    }
}

extension FeedbackClientError {
    func addingOperation(_ operation: FeedbackClientOperation) -> Self {
        guard context.operation == nil else { return self }
        return FeedbackClientError(
            kind: kind,
            context: context.addingOperation(operation)
        )
    }
}
