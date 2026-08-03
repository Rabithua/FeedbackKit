import FeedbackKitCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public actor FeedbackFixtureTransport: FeedbackTransport {
    public typealias Handler = @Sendable (URLRequest) throws -> (statusCode: Int, headers: [String: String], data: Data)

    private let handler: Handler
    private(set) public var requests: [URLRequest] = []

    public init(handler: @escaping Handler) {
        self.handler = handler
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let response = try handler(request)
        guard let http = HTTPURLResponse(url: request.url!, statusCode: response.statusCode, httpVersion: "HTTP/1.1", headerFields: response.headers) else {
            throw URLError(.badServerResponse)
        }
        return (response.data, http)
    }

    public func upload(for request: URLRequest, data: Data) async throws -> HTTPURLResponse {
        var request = request
        request.httpBody = data
        requests.append(request)
        let response = try handler(request)
        guard let http = HTTPURLResponse(url: request.url!, statusCode: response.statusCode, httpVersion: "HTTP/1.1", headerFields: response.headers) else {
            throw URLError(.badServerResponse)
        }
        return http
    }

    public static func envelope<T: Encodable>(_ value: T, code: String = "ok", message: String = "OK") throws -> Data {
        try JSONEncoder.feedbackFixture.encode(FixtureEnvelope(code: code, message: message, data: value))
    }

    public static func error(code: String, message: String) throws -> Data {
        try JSONEncoder.feedbackFixture.encode(FixtureError(code: code, message: message))
    }
}

public struct FeedbackFixedClock: Sendable {
    public let now: Date
    public init(now: Date) { self.now = now }
}

public struct FeedbackFixedMetadataProvider: FeedbackAppMetadataProvider {
    public let context: FeedbackClientContext
    public init(context: FeedbackClientContext) { self.context = context }
    public func clientContext(locale: Locale) async -> FeedbackClientContext { context }
}

private struct FixtureEnvelope<T: Encodable>: Encodable { let code: String; let message: String; let data: T }
private struct FixtureError: Encodable { let code: String; let message: String }

private extension JSONEncoder {
    static var feedbackFixture: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
