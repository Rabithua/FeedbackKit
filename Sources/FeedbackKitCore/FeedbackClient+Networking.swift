import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension FeedbackClient {
    enum Scope: String { case client; case `public` }
    enum Method: String { case get = "GET"; case post = "POST"; case put = "PUT"; case delete = "DELETE" }

    func get<Value: Decodable & Sendable>(
        _ type: Value.Type,
        operation: FeedbackClientOperation,
        scope: Scope = .client,
        path: String,
        query: [URLQueryItem] = []
    ) async throws -> Value {
        try await perform(
            type,
            operation: operation,
            scope: scope,
            method: .get,
            path: path,
            query: query,
            body: nil,
            idempotencyKey: nil
        )
    }

    func send<Body: Encodable & Sendable, Value: Decodable & Sendable>(
        _ type: Value.Type,
        operation: FeedbackClientOperation,
        scope: Scope = .client,
        method: Method,
        path: String,
        body: Body,
        idempotencyKey: String? = nil
    ) async throws -> Value {
        try await perform(
            type,
            operation: operation,
            scope: scope,
            method: method,
            path: path,
            query: [],
            body: FeedbackCoding.encoder().encode(body),
            idempotencyKey: idempotencyKey
        )
    }

    package func postClientJSON<Body: Encodable & Sendable, Value: Decodable & Sendable>(
        _ type: Value.Type,
        operation: FeedbackClientOperation,
        path: String,
        body: Body,
        idempotencyKey: String? = nil
    ) async throws -> Value {
        try await send(
            type,
            operation: operation,
            method: .post,
            path: path,
            body: body,
            idempotencyKey: idempotencyKey
        )
    }

    func sendWithoutBody<Value: Decodable & Sendable>(
        _ type: Value.Type,
        operation: FeedbackClientOperation,
        scope: Scope = .client,
        method: Method,
        path: String
    ) async throws -> Value {
        try await perform(
            type,
            operation: operation,
            scope: scope,
            method: method,
            path: path,
            query: [],
            body: nil,
            idempotencyKey: nil
        )
    }

    private func apiRequest(
        method: Method,
        scope: Scope,
        path: String,
        query: [URLQueryItem],
        body: Data?,
        idempotencyKey: String?
    ) async throws -> URLRequest {
        let url = try makeURL(scope: scope, path: path, query: query)
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(configuration.productKey, forHTTPHeaderField: "X-Product-Key")
        request.setValue("release-body-only", forHTTPHeaderField: "X-FeedbackKit-Capabilities")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let idempotencyKey {
            request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        }
        if scope == .client {
            let credential = try await credentialStore.credential(for: configuration.productKey)
            request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func perform<Value: Decodable & Sendable>(
        _ type: Value.Type,
        operation: FeedbackClientOperation,
        scope: Scope,
        method: Method,
        path: String,
        query: [URLQueryItem],
        body: Data?,
        idempotencyKey: String?
    ) async throws -> Value {
        let started = ContinuousClock.now
        var requestURL: URL?
        var recordedFailure = false

        do {
            let request = try await apiRequest(
                method: method, scope: scope, path: path,
                query: query, body: body, idempotencyKey: idempotencyKey
            )
            let url = request.url!
            requestURL = url

            let (data, response) = try await transport.data(for: request)
            let duration = started.duration(to: .now).timeInterval
            guard (200...299).contains(response.statusCode) else {
                let error = httpError(data, response, operation: operation)
                record(
                    operation: operation,
                    outcome: .failed,
                    duration: duration,
                    response: response,
                    error: error
                )
                recordedFailure = true
                await diagnostics?.recordNetwork(
                    method: method.rawValue,
                    host: url.host ?? "",
                    path: url.path,
                    statusCode: response.statusCode,
                    duration: duration,
                    errorCategory: error.kind.rawValue
                )
                throw error
            }

            let value: Value
            do {
                value = try FeedbackCoding.decoder().decode(
                    FeedbackEnvelope<Value>.self,
                    from: data
                ).data
            } catch {
                let clientError = FeedbackClientError(
                    kind: .decoding,
                    context: FeedbackFailureContext(
                        operation: operation,
                        statusCode: response.statusCode,
                        requestID: requestID(from: response),
                        debugDescription: decodingDebugDescription(
                            error,
                            target: Value.self
                        )
                    )
                )
                record(
                    operation: operation,
                    outcome: .failed,
                    duration: duration,
                    response: response,
                    error: clientError
                )
                recordedFailure = true
                await diagnostics?.recordNetwork(
                    method: method.rawValue,
                    host: url.host ?? "",
                    path: url.path,
                    statusCode: response.statusCode,
                    duration: duration,
                    errorCategory: clientError.kind.rawValue
                )
                throw clientError
            }

            record(
                operation: operation,
                outcome: .succeeded,
                duration: duration,
                response: response,
                error: nil
            )
            await diagnostics?.recordNetwork(
                method: method.rawValue,
                host: url.host ?? "",
                path: url.path,
                statusCode: response.statusCode,
                duration: duration,
                errorCategory: nil
            )
            return value
        } catch {
            let duration = started.duration(to: .now).timeInterval
            if error is CancellationError || Task.isCancelled {
                if recordedFailure == false {
                    record(
                        operation: operation,
                        outcome: .cancelled,
                        duration: duration,
                        response: nil,
                        error: nil
                    )
                }
                throw CancellationError()
            }

            let clientError = map(error, operation: operation)
            if recordedFailure == false {
                record(
                    operation: operation,
                    outcome: .failed,
                    duration: duration,
                    response: nil,
                    error: clientError
                )
                await diagnostics?.recordNetwork(
                    method: method.rawValue,
                    host: requestURL?.host ?? "",
                    path: operation.rawValue,
                    statusCode: clientError.context.statusCode,
                    duration: duration,
                    errorCategory: clientError.kind.rawValue
                )
            }
            throw clientError
        }
    }

    func upload(
        _ data: Data,
        to url: URL,
        headers: RequiredHeaders,
        operation: FeedbackClientOperation
    ) async throws {
        try await upload(
            body: .data(data),
            to: url,
            headers: headers,
            operation: operation
        )
    }

    func upload(
        _ source: FeedbackAttachmentSource,
        to url: URL,
        headers: RequiredHeaders,
        operation: FeedbackClientOperation
    ) async throws {
        let body: UploadBody
        switch source.storage {
        case let .data(data): body = .data(data)
        case let .file(fileURL): body = .file(fileURL)
        }
        try await upload(
            body: body,
            to: url,
            headers: headers,
            operation: operation
        )
    }

    private func upload(
        body: UploadBody,
        to url: URL,
        headers: RequiredHeaders,
        operation: FeedbackClientOperation
    ) async throws {
        let started = ContinuousClock.now
        do {
            let request = try uploadRequest(to: url, headers: headers)
            let response: HTTPURLResponse
            switch body {
            case let .data(data):
                response = try await transport.upload(for: request, data: data)
            case let .file(fileURL):
                response = try await transport.upload(for: request, fromFile: fileURL)
            }
            let duration = started.duration(to: .now).timeInterval
            guard (200...299).contains(response.statusCode) else {
                throw FeedbackClientError(
                    kind: .server,
                    context: FeedbackFailureContext(
                        operation: operation,
                        statusCode: response.statusCode,
                        requestID: requestID(from: response)
                    )
                )
            }
            record(
                operation: operation,
                outcome: .succeeded,
                duration: duration,
                response: response,
                error: nil
            )
            await diagnostics?.recordNetwork(
                method: "PUT",
                host: url.host ?? "",
                path: operation.rawValue,
                statusCode: response.statusCode,
                duration: duration,
                errorCategory: nil
            )
        } catch {
            let duration = started.duration(to: .now).timeInterval
            if error is CancellationError || Task.isCancelled {
                record(
                    operation: operation,
                    outcome: .cancelled,
                    duration: duration,
                    response: nil,
                    error: nil
                )
                throw CancellationError()
            }
            let clientError = map(error, operation: operation)
            record(
                operation: operation,
                outcome: .failed,
                duration: duration,
                response: nil,
                error: clientError
            )
            await diagnostics?.recordNetwork(
                method: "PUT",
                host: url.host ?? "",
                path: operation.rawValue,
                statusCode: clientError.context.statusCode,
                duration: duration,
                errorCategory: clientError.kind.rawValue
            )
            throw clientError
        }
    }

    private func uploadRequest(to url: URL, headers: RequiredHeaders) throws -> URLRequest {
        guard url.isFeedbackSecureTransportURL else {
            throw FeedbackClientError(kind: .invalidURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        headers.apply(to: &request)
        return request
    }

    private func makeURL(scope: Scope, path: String, query: [URLQueryItem]) throws -> URL {
        var url = configuration.apiBaseURL.appending(path: scope.rawValue)
        for component in path.split(separator: "/") { url.append(path: String(component)) }
        guard query.isEmpty == false else { return url }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw FeedbackClientError(kind: .invalidURL)
        }
        components.queryItems = query
        guard let result = components.url else {
            throw FeedbackClientError(kind: .invalidURL)
        }
        return result
    }

    private func httpError(
        _ data: Data,
        _ response: HTTPURLResponse,
        operation: FeedbackClientOperation
    ) -> FeedbackClientError {
        let code = try? FeedbackCoding.decoder().decode(FeedbackErrorEnvelope.self, from: data).code
        let retryAfter = response.value(forHTTPHeaderField: "Retry-After")
            .flatMap(TimeInterval.init)
        let kind: FeedbackClientError.Kind
        switch response.statusCode {
        case 401: kind = .unauthorized
        case 403: kind = .forbidden
        case 404: kind = .notFound
        case 413: kind = .payloadTooLarge
        case 422: kind = .validation
        case 429: kind = .rateLimited
        default: kind = .server
        }
        return FeedbackClientError(
            kind: kind,
            context: FeedbackFailureContext(
                operation: operation,
                statusCode: response.statusCode,
                serverCode: code,
                requestID: requestID(from: response),
                retryAfter: retryAfter
            )
        )
    }

    private func map(
        _ error: Error,
        operation: FeedbackClientOperation
    ) -> FeedbackClientError {
        if let error = error as? FeedbackClientError {
            return error.addingOperation(operation)
        }
        if let error = error as? URLError,
           [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed].contains(error.code) {
            return FeedbackClientError(
                kind: .offline,
                context: FeedbackFailureContext(
                    operation: operation,
                    debugDescription: safeDebugDescription(for: error)
                )
            )
        }
        return FeedbackClientError(
            kind: .transport,
            context: FeedbackFailureContext(
                operation: operation,
                debugDescription: safeDebugDescription(for: error)
            )
        )
    }

    private func record(
        operation: FeedbackClientOperation,
        outcome: FeedbackClientEvent.Outcome,
        duration: TimeInterval,
        response: HTTPURLResponse?,
        error: FeedbackClientError?
    ) {
        observer?.record(
            FeedbackClientEvent(
                operation: operation,
                outcome: outcome,
                duration: duration,
                statusCode: error?.context.statusCode ?? response?.statusCode,
                serverCode: error?.context.serverCode,
                requestID: error?.context.requestID ?? response.flatMap(requestID(from:)),
                retryAfter: error?.context.retryAfter,
                failureKind: error?.kind
            )
        )
    }

    private func requestID(from response: HTTPURLResponse) -> String? {
        response.value(forHTTPHeaderField: "X-Request-ID")
    }

    func safeDebugDescription(for error: Error) -> String {
        if let error = error as? URLError {
            return "URLError(code: \(error.code.rawValue))"
        }
        if let error = error as? FeedbackClientError {
            return error.context.debugDescription ?? "FeedbackClientError(kind: \(error.kind.rawValue))"
        }
        return String(reflecting: type(of: error))
    }

    private func decodingDebugDescription<Value>(
        _ error: Error,
        target: Value.Type
    ) -> String {
        let failure: String
        let codingPath: [any CodingKey]
        switch error {
        case let DecodingError.typeMismatch(_, context):
            failure = "typeMismatch"
            codingPath = context.codingPath
        case let DecodingError.valueNotFound(_, context):
            failure = "valueNotFound"
            codingPath = context.codingPath
        case let DecodingError.keyNotFound(_, context):
            failure = "keyNotFound"
            codingPath = context.codingPath
        case let DecodingError.dataCorrupted(context):
            failure = "dataCorrupted"
            codingPath = context.codingPath
        default:
            failure = String(reflecting: type(of: error))
            codingPath = []
        }
        let path = codingPath.map(\.stringValue).joined(separator: ".")
        let location = path.isEmpty ? "<root>" : path
        return "\(failure) while decoding \(String(reflecting: target)) at \(location)"
    }
}

private enum UploadBody: Sendable {
    case data(Data)
    case file(URL)
}

private extension Duration {
    var timeInterval: TimeInterval { TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18 }
}

struct UploadDeclaration: Encodable, Sendable { let filename: String; let contentType: String; let size: Int }
struct UploadPresignRequest: Encodable, Sendable { let files: [UploadDeclaration] }
struct RequiredHeaders: Decodable, Sendable {
    let contentType: String
    let contentLength: String
    let checksumSHA256: String?
    enum CodingKeys: String, CodingKey {
        case contentType = "Content-Type"
        case contentLength = "Content-Length"
        case checksumSHA256 = "X-Amz-Checksum-Sha256"
    }

    func apply(to request: inout URLRequest) {
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(contentLength, forHTTPHeaderField: "Content-Length")
        if let checksumSHA256 {
            request.setValue(checksumSHA256, forHTTPHeaderField: "X-Amz-Checksum-Sha256")
        }
    }
}
struct PresignedUpload: Decodable, Sendable { let attachmentId: String; let uploadUrl: URL; let headers: RequiredHeaders; let expiresIn: Int }
struct UploadFinalizeItem: Encodable, Sendable { let id: String; let posterUploaded: Bool; let width: Int?; let height: Int?; let durationMs: Int? }
struct UploadFinalizeRequest: Encodable, Sendable { let attachments: [UploadFinalizeItem] }
struct FinalizedAttachment: Decodable, Sendable { let id: String }
struct Ack: Codable, Sendable { let cursor: Int }
struct VisitorMessageRequest: Encodable, Sendable { let body: String }
