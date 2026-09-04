import Foundation
import OSLog

/// A privacy-safe logical operation performed by ``FeedbackClient``.
public struct FeedbackClientOperation: RawRepresentable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let bootstrap = Self(rawValue: "bootstrap")
    public static let verifyIntegration = Self(rawValue: "verify_integration")
    public static let activity = Self(rawValue: "activity")
    public static let ownedFeedback = Self(rawValue: "owned_feedback")
    public static let feedbackDetail = Self(rawValue: "feedback_detail")
    public static let visitorMessage = Self(rawValue: "visitor_message")
    public static let developerPost = Self(rawValue: "developer_post")
    public static let releases = Self(rawValue: "releases")
    public static let campaigns = Self(rawValue: "campaigns")
    public static let campaign = Self(rawValue: "campaign")
    public static let campaignResponse = Self(rawValue: "campaign_response")
    public static let createFeedback = Self(rawValue: "create_feedback")
    public static let vote = Self(rawValue: "vote")
    public static let attachmentURL = Self(rawValue: "attachment_url")
    public static let attachmentPresign = Self(rawValue: "attachment_presign")
    public static let attachmentUpload = Self(rawValue: "attachment_upload")
    public static let attachmentFinalize = Self(rawValue: "attachment_finalize")
    public static let inbox = Self(rawValue: "inbox")
    public static let inboxAcknowledge = Self(rawValue: "inbox_acknowledge")
    public static let visitorDelete = Self(rawValue: "visitor_delete")
    public static let diagnosticPresign = Self(rawValue: "diagnostic_presign")
    public static let journeySubmit = Self(rawValue: "journey_submit")
    public static let diagnosticUpload = Self(rawValue: "diagnostic_upload")
    public static let diagnosticFinalize = Self(rawValue: "diagnostic_finalize")
}

/// Sanitized metadata attached to a ``FeedbackClientError``.
public struct FeedbackFailureContext: Equatable, Sendable {
    public let operation: FeedbackClientOperation?
    public let statusCode: Int?
    public let serverCode: String?
    public let requestID: String?
    public let retryAfter: TimeInterval?
    public let debugDescription: String?

    public init(
        operation: FeedbackClientOperation? = nil,
        statusCode: Int? = nil,
        serverCode: String? = nil,
        requestID: String? = nil,
        retryAfter: TimeInterval? = nil,
        debugDescription: String? = nil
    ) {
        self.operation = operation
        self.statusCode = statusCode
        self.serverCode = serverCode
        self.requestID = requestID
        self.retryAfter = retryAfter
        self.debugDescription = debugDescription
    }

    func addingOperation(_ operation: FeedbackClientOperation) -> Self {
        Self(
            operation: operation,
            statusCode: statusCode,
            serverCode: serverCode,
            requestID: requestID,
            retryAfter: retryAfter,
            debugDescription: debugDescription
        )
    }
}

/// A sanitized completion event emitted by ``FeedbackClient``.
public struct FeedbackClientEvent: Equatable, Sendable {
    public enum Outcome: String, Equatable, Sendable {
        case succeeded
        case failed
        case cancelled
    }

    public let timestamp: Date
    public let operation: FeedbackClientOperation
    public let outcome: Outcome
    public let duration: TimeInterval
    public let statusCode: Int?
    public let serverCode: String?
    public let requestID: String?
    public let retryAfter: TimeInterval?
    public let failureKind: FeedbackClientError.Kind?

    public init(
        timestamp: Date = .now,
        operation: FeedbackClientOperation,
        outcome: Outcome,
        duration: TimeInterval,
        statusCode: Int? = nil,
        serverCode: String? = nil,
        requestID: String? = nil,
        retryAfter: TimeInterval? = nil,
        failureKind: FeedbackClientError.Kind? = nil
    ) {
        self.timestamp = timestamp
        self.operation = operation
        self.outcome = outcome
        self.duration = duration
        self.statusCode = statusCode
        self.serverCode = serverCode
        self.requestID = requestID
        self.retryAfter = retryAfter
        self.failureKind = failureKind
    }
}

/// A synchronous, opt-in receiver for privacy-safe client completion events.
public struct FeedbackClientObserver: Sendable {
    private let handler: @Sendable (FeedbackClientEvent) -> Void

    /// Creates a synchronous observer. The handler should return promptly.
    public init(_ handler: @escaping @Sendable (FeedbackClientEvent) -> Void) {
        self.handler = handler
    }

    public func record(_ event: FeedbackClientEvent) {
        handler(event)
    }

    /// Creates an observer that writes sanitized operation completions to the unified log.
    public static func osLog(
        subsystem: String,
        category: String = "FeedbackKit"
    ) -> Self {
        let logger = Logger(subsystem: subsystem, category: category)
        return Self { event in
            let status = event.statusCode.map(String.init) ?? "none"
            let code = event.serverCode ?? "none"
            let requestID = event.requestID ?? "none"
            logger.log(
                "FeedbackKit operation=\(event.operation.rawValue, privacy: .public) outcome=\(event.outcome.rawValue, privacy: .public) duration=\(event.duration, privacy: .public)s status=\(status, privacy: .public) code=\(code, privacy: .public) request_id=\(requestID, privacy: .public)"
            )
        }
    }
}
