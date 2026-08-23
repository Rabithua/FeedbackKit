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
        guard let http = response as? HTTPURLResponse else { throw FeedbackClientError.invalidResponse }
        return (data, http)
    }

    public func upload(for request: URLRequest, data: Data) async throws -> HTTPURLResponse {
        let (_, response) = try await session.upload(for: request, from: data)
        guard let http = response as? HTTPURLResponse else { throw FeedbackClientError.invalidResponse }
        return http
    }

    public func upload(for request: URLRequest, fromFile fileURL: URL) async throws -> HTTPURLResponse {
        let (_, response) = try await session.upload(for: request, fromFile: fileURL)
        guard let http = response as? HTTPURLResponse else {
            throw FeedbackClientError.invalidResponse
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
              redirectURL.feedbackTransportOrigin == originalURL.feedbackTransportOrigin
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

private struct FeedbackTransportOrigin: Equatable {
    let scheme: String
    let host: String
    let port: Int
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

    fileprivate var feedbackTransportOrigin: FeedbackTransportOrigin? {
        guard let scheme = scheme?.lowercased(),
              let host = host?.lowercased()
        else { return nil }
        let defaultPort: Int
        switch scheme {
        case "https": defaultPort = 443
        case "http": defaultPort = 80
        default: return nil
        }
        return FeedbackTransportOrigin(scheme: scheme, host: host, port: port ?? defaultPort)
    }
}

struct FeedbackEnvelope<Value: Decodable & Sendable>: Decodable, Sendable {
    let code: String
    let message: String
    let data: Value
}

struct FeedbackErrorEnvelope: Decodable, Sendable {
    let code: String
    let message: String
}

enum FeedbackCoding {
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) { return date }
            let standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
            if let date = standard.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date")
        }
        return decoder
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
