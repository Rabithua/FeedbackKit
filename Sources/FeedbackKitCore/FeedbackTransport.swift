import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol FeedbackTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
    func upload(for request: URLRequest, data: Data) async throws -> HTTPURLResponse
}

public actor URLSessionFeedbackTransport: FeedbackTransport {
    private let session: URLSession

    public init(configuration: URLSessionConfiguration = .ephemeral) {
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
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
