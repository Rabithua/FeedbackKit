import Foundation

public struct FeedbackConfiguration: Sendable {
    public let baseURL: URL
    public let productKey: String
    public let keychainService: String

    public init(
        baseURL: URL,
        productKey: String,
        keychainService: String = "ink.rote.FeedbackKit.visitor"
    ) {
        self.baseURL = baseURL
        self.productKey = productKey
        self.keychainService = keychainService
    }
}

public enum FeedbackClientError: Error, Equatable, Sendable {
    case invalidURL
    case offline
    case transport
    case invalidResponse
    case decoding
    case unauthorized(code: String?)
    case forbidden(code: String?)
    case notFound
    case payloadTooLarge
    case validation(code: String?)
    case rateLimited(retryAfter: TimeInterval?)
    case server(statusCode: Int, code: String?)
    case diagnosticsUnavailable
    case diagnosticUploadFailed
}

extension FeedbackClientError: LocalizedError {
    public var errorDescription: String? {
        switch self {
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
        case let .server(statusCode, _): "FeedbackServer returned HTTP \(statusCode)."
        case .diagnosticsUnavailable: "Diagnostics are not available for this product."
        case .diagnosticUploadFailed: "The private diagnostic upload failed."
        }
    }
}

public protocol FeedbackAppMetadataProvider: Sendable {
    func clientContext(locale: Locale) async -> FeedbackClientContext
}

public struct DefaultFeedbackAppMetadataProvider: FeedbackAppMetadataProvider {
    private let bundle: Bundle

    public init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    public func clientContext(locale: Locale) async -> FeedbackClientContext {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        #if os(iOS)
        let osVersion = await MainActor.run { UIDevice.current.systemVersion }
        let category = await MainActor.run { UIDevice.current.userInterfaceIdiom == .pad ? "tablet" : "phone" }
        #else
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let category = "desktop"
        #endif
        return FeedbackClientContext(
            appVersion: version,
            buildNumber: build,
            osVersion: osVersion,
            deviceCategory: category,
            locale: locale.feedbackContentIdentifier
        )
    }
}

#if os(iOS)
import UIKit
#endif
