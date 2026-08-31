import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol FeedbackTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
    func upload(for request: URLRequest, data: Data) async throws -> HTTPURLResponse
    func upload(for request: URLRequest, fromFile fileURL: URL) async throws -> HTTPURLResponse
}

public extension FeedbackTransport {
    func upload(for request: URLRequest, fromFile fileURL: URL) async throws -> HTTPURLResponse {
        try Task.checkCancellation()
        return try await upload(
            for: request,
            data: Data(contentsOf: fileURL, options: .mappedIfSafe)
        )
    }
}

public actor URLSessionFeedbackTransport: FeedbackTransport {
    private let session: URLSession

    public init(configuration: URLSessionConfiguration = .ephemeral) {
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(
            configuration: configuration,
            delegate: FeedbackSecureRedirectDelegate(),
            delegateQueue: nil
        )
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FeedbackClientError(kind: .invalidResponse)
        }
        return (data, http)
    }

    public func upload(for request: URLRequest, data: Data) async throws -> HTTPURLResponse {
        let (_, response) = try await session.upload(for: request, from: data)
        guard let http = response as? HTTPURLResponse else {
            throw FeedbackClientError(kind: .invalidResponse)
        }
        return http
    }

    public func upload(for request: URLRequest, fromFile fileURL: URL) async throws -> HTTPURLResponse {
        let (_, response) = try await session.upload(for: request, fromFile: fileURL)
        guard let http = response as? HTTPURLResponse else {
            throw FeedbackClientError(kind: .invalidResponse)
        }
        return http
    }
}

final class FeedbackSecureRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func approvedRedirectRequest(
        _ request: URLRequest,
        originalRequest: URLRequest?
    ) -> URLRequest? {
        guard let redirectURL = request.url,
              let originalURL = originalRequest?.url,
              redirectURL.isFeedbackSecureTransportURL,
              redirectURL.hasSameFeedbackTransportOrigin(as: originalURL)
        else { return nil }
        return request
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(approvedRedirectRequest(request, originalRequest: task.originalRequest))
    }
}

extension URL {
    var isFeedbackSecureTransportURL: Bool {
        guard user == nil,
              password == nil,
              let host = host?.lowercased(),
              host.isEmpty == false
        else { return false }
        if scheme?.lowercased() == "https" { return true }
        guard scheme?.lowercased() == "http" else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    fileprivate func hasSameFeedbackTransportOrigin(as other: URL) -> Bool {
        guard let scheme = scheme?.lowercased(),
              let host = host?.lowercased(),
              let port = feedbackTransportEffectivePort,
              let otherScheme = other.scheme?.lowercased(),
              let otherHost = other.host?.lowercased(),
              let otherPort = other.feedbackTransportEffectivePort
        else { return false }
        return scheme == otherScheme && host == otherHost && port == otherPort
    }

    private var feedbackTransportEffectivePort: Int? {
        if let port { return port }
        guard let scheme = scheme?.lowercased()
        else { return nil }
        switch scheme {
        case "https": return 443
        case "http": return 80
        default: return nil
        }
    }
}