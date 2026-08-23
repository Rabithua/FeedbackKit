import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public actor FeedbackClient {
    public let configuration: FeedbackConfiguration
    public nonisolated let diagnosticsProvider: (any FeedbackDiagnosticsProviding)?

    private let transport: any FeedbackTransport
    private let credentialStore: any FeedbackVisitorCredentialProviding
    private let metadataProvider: any FeedbackAppMetadataProvider
    private let diagnostics: (any FeedbackDiagnosticsProviding)?
    private var latestDiagnosticsCapability: FeedbackDiagnosticsCapability?
    private static let serviceRestrictionCodes: Set<String> = [
        "feedback_feature_unavailable",
        "feedback_service_read_only",
        "feedback_storage_unavailable",
    ]

    public init(
        configuration: FeedbackConfiguration,
        diagnostics: (any FeedbackDiagnosticsProviding)? = nil,
        transport: any FeedbackTransport = URLSessionFeedbackTransport(),
        credentialStore: (any FeedbackVisitorCredentialProviding)? = nil,
        metadataProvider: any FeedbackAppMetadataProvider = DefaultFeedbackAppMetadataProvider()
    ) {
        self.configuration = configuration
        self.diagnostics = diagnostics
        diagnosticsProvider = diagnostics
        self.transport = transport
        self.credentialStore = credentialStore ?? FeedbackVisitorCredentialStore(service: configuration.keychainService)
        self.metadataProvider = metadataProvider
    }

    public func bootstrap(locale: Locale, after: Int = 0) async throws -> FeedbackBootstrap {
        let bootstrap = try await get(
            FeedbackBootstrap.self,
            path: "bootstrap",
            query: [
                URLQueryItem(name: "after", value: String(after)),
                URLQueryItem(name: "locale", value: locale.feedbackContentIdentifier),
            ]
        )
        latestDiagnosticsCapability = bootstrap.product.diagnostics
        return bootstrap
    }

    public func activity(locale: Locale, cursor: String? = nil) async throws -> FeedbackActivityPage {
        var query = [
            URLQueryItem(name: "locale", value: locale.feedbackContentIdentifier),
            URLQueryItem(name: "limit", value: "25"),
        ]
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        return try await get(FeedbackActivityPage.self, path: "activity", query: query)
    }

    public func ownedFeedback(cursor: String? = nil) async throws -> OwnedFeedbackPage {
        var query = [URLQueryItem(name: "limit", value: "25")]
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        return try await get(OwnedFeedbackPage.self, path: "feedback", query: query)
    }

    public func feedback(id: String) async throws -> FeedbackDetail {
        try await get(FeedbackDetail.self, path: "feedback/\(id)")
    }

    public func addVisitorMessage(feedbackID: String, body: String, idempotencyKey: String) async throws -> FeedbackMessage {
        try await send(
            FeedbackMessage.self,
            method: .post,
            path: "feedback/\(feedbackID)/messages",
            body: VisitorMessageRequest(body: body),
            idempotencyKey: idempotencyKey
        )
    }

    public func developerPost(id: String, locale: Locale) async throws -> FeedbackDeveloperPost {
        try await get(
            FeedbackDeveloperPost.self,
            path: "developer-posts/\(id)",
            query: [URLQueryItem(name: "locale", value: locale.feedbackContentIdentifier)]
        )
    }

    public func releases(locale: Locale) async throws -> [FeedbackRelease] {
        try await get(
            [FeedbackRelease].self,
            scope: .public,
            path: "releases",
            query: [URLQueryItem(name: "locale", value: locale.feedbackContentIdentifier)]
        )
    }

    public func createFeedback(_ request: FeedbackCreateRequest, idempotencyKey: String) async throws -> OwnedFeedbackSummary {
        try await send(
            OwnedFeedbackSummary.self,
            method: .post,
            path: "feedback",
            body: request,
            idempotencyKey: idempotencyKey
        )
    }

    public func submitFeedback(
        type: FeedbackKind,
        title: String?,
        body: String,
        locale: Locale,
        attachmentIds: [String] = [],
        includeDiagnostics: Bool,
        idempotencyKey: String
    ) async throws -> OwnedFeedbackSummary {
        var diagnosticID: String?
        if includeDiagnostics {
            guard let diagnostics else { throw FeedbackClientError.diagnosticsUnavailable }
            let capability: FeedbackDiagnosticsCapability
            if let latestDiagnosticsCapability {
                capability = latestDiagnosticsCapability
            } else {
                guard let fetched = try await bootstrap(locale: locale).product.diagnostics else {
                    throw FeedbackClientError.diagnosticsUnavailable
                }
                capability = fetched
            }
            guard capability.supportsSchemaOne else {
                throw FeedbackClientError.diagnosticsUnavailable
            }
            let snapshot = try await diagnostics.makeDiagnosticSnapshot(
                maxBytes: capability.maxBytes,
                locale: locale
            )
            guard snapshot.data.count <= capability.maxBytes else {
                throw FeedbackClientError.payloadTooLarge
            }
            diagnosticID = try await uploadDiagnosticSnapshot(snapshot)
        }
        let context = await metadataProvider.clientContext(locale: locale)
        return try await createFeedback(
            FeedbackCreateRequest(
                type: type,
                title: title,
                body: body,
                clientContext: context,
                attachmentIds: attachmentIds,
                diagnosticArtifactId: diagnosticID
            ),
            idempotencyKey: idempotencyKey
        )
    }

    public func setVote(feedbackID: String, voted: Bool) async throws -> FeedbackVoteResult {
        try await sendWithoutBody(
            FeedbackVoteResult.self,
            method: voted ? .put : .delete,
            path: "feedback/\(feedbackID)/vote"
        )
    }

    public func signedAttachmentURL(id: String) async throws -> FeedbackSignedAttachmentURL {
        try await get(FeedbackSignedAttachmentURL.self, path: "attachments/\(id)/url")
    }

    public func uploadAttachments(_ sources: [FeedbackAttachmentSource]) async throws -> [String] {
        guard sources.isEmpty == false else { return [] }
        let declarations = sources.map {
            UploadDeclaration(
                filename: $0.filename,
                contentType: $0.contentType,
                size: $0.byteCount
            )
        }
        let presigned = try await send(
            [PresignedUpload].self,
            method: .post,
            path: "uploads/presign",
            body: UploadPresignRequest(files: declarations)
        )
        guard presigned.count == sources.count else { throw FeedbackClientError.invalidResponse }
        let pairs = Array(zip(presigned, sources))
        try await withThrowingTaskGroup(of: Void.self) { group in
            var iterator = pairs.makeIterator()
            for _ in 0..<min(2, pairs.count) {
                if let pair = iterator.next() {
                    group.addTask {
                        try await self.upload(
                            pair.1,
                            to: pair.0.uploadUrl,
                            headers: pair.0.headers
                        )
                    }
                }
            }
            while try await group.next() != nil {
                if let pair = iterator.next() {
                    group.addTask {
                        try await self.upload(
                            pair.1,
                            to: pair.0.uploadUrl,
                            headers: pair.0.headers
                        )
                    }
                }
            }
        }
        let finalized = try await send(
            [FinalizedAttachment].self,
            method: .post,
            path: "uploads/finalize",
            body: UploadFinalizeRequest(
                attachments: pairs.map { upload, source in
                    UploadFinalizeItem(
                        id: upload.attachmentId,
                        posterUploaded: false,
                        width: source.width,
                        height: source.height,
                        durationMs: source.durationMs
                    )
                }
            )
        )
        guard finalized.count == sources.count else { throw FeedbackClientError.invalidResponse }
        return presigned.map(\.attachmentId)
    }

    public func acknowledgeInbox(cursor: Int) async throws -> Int {
        try await send(Ack.self, method: .post, path: "inbox/ack", body: Ack(cursor: cursor)).cursor
    }

    public func deleteVisitor() async throws {
        let _: Bool? = try await sendWithoutBody(Bool?.self, method: .delete, path: "me")
        try await credentialStore.deleteCredential(for: configuration.productKey)
    }

    public func uploadDiagnosticSnapshot(_ snapshot: FeedbackDiagnosticSnapshot) async throws -> String {
        let presigned = try await send(
            DiagnosticPresignResponse.self,
            method: .post,
            path: "diagnostics/presign",
            body: DiagnosticPresignRequest(
                filename: "diagnostics.json",
                contentType: "application/json",
                size: snapshot.data.count,
                sha256: snapshot.sha256,
                schemaVersion: snapshot.schemaVersion
            )
        )
        do {
            try await upload(snapshot.data, to: presigned.uploadUrl, headers: presigned.headers)
            let finalized = try await send(
                DiagnosticFinalizeResponse.self,
                method: .post,
                path: "diagnostics/finalize",
                body: DiagnosticFinalizeRequest(diagnosticArtifactId: presigned.diagnosticArtifactId)
            )
            return finalized.id
        } catch {
            if error is CancellationError || Task.isCancelled {
                throw CancellationError()
            }
            if let clientError = error as? FeedbackClientError,
               case let .server(statusCode, code) = clientError,
               statusCode == 503,
               let code,
               Self.serviceRestrictionCodes.contains(code) {
                throw clientError
            }
            throw FeedbackClientError.diagnosticUploadFailed
        }
    }

    private enum Scope: String { case client; case `public` }
    private enum Method: String { case get = "GET"; case post = "POST"; case put = "PUT"; case delete = "DELETE" }

    private func get<Value: Decodable & Sendable>(_ type: Value.Type, scope: Scope = .client, path: String, query: [URLQueryItem] = []) async throws -> Value {
        try await perform(type, scope: scope, method: .get, path: path, query: query, body: nil, idempotencyKey: nil)
    }

    private func send<Body: Encodable & Sendable, Value: Decodable & Sendable>(_ type: Value.Type, scope: Scope = .client, method: Method, path: String, body: Body, idempotencyKey: String? = nil) async throws -> Value {
        try await perform(type, scope: scope, method: method, path: path, query: [], body: FeedbackCoding.encoder().encode(body), idempotencyKey: idempotencyKey)
    }

    private func sendWithoutBody<Value: Decodable & Sendable>(_ type: Value.Type, scope: Scope = .client, method: Method, path: String) async throws -> Value {
        try await perform(type, scope: scope, method: method, path: path, query: [], body: nil, idempotencyKey: nil)
    }

    private func perform<Value: Decodable & Sendable>(_ type: Value.Type, scope: Scope, method: Method, path: String, query: [URLQueryItem], body: Data?, idempotencyKey: String?) async throws -> Value {
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
        if let idempotencyKey { request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key") }
        if scope == .client {
            request.setValue("Bearer \(try await credentialStore.credential(for: configuration.productKey))", forHTTPHeaderField: "Authorization")
        }
        let started = ContinuousClock.now
        do {
            let (data, response) = try await transport.data(for: request)
            let duration = started.duration(to: .now).timeInterval
            guard (200...299).contains(response.statusCode) else {
                let error = httpError(data, response)
                await diagnostics?.recordNetwork(method: method.rawValue, host: url.host ?? "", path: url.path, statusCode: response.statusCode, duration: duration, errorCategory: String(reflecting: error))
                throw error
            }
            await diagnostics?.recordNetwork(method: method.rawValue, host: url.host ?? "", path: url.path, statusCode: response.statusCode, duration: duration, errorCategory: nil)
            do { return try FeedbackCoding.decoder().decode(FeedbackEnvelope<Value>.self, from: data).data }
            catch { throw FeedbackClientError.decoding }
        } catch {
            if error is CancellationError || Task.isCancelled {
                throw CancellationError()
            }
            if error is FeedbackClientError { throw error }
            let duration = started.duration(to: .now).timeInterval
            await diagnostics?.recordNetwork(method: method.rawValue, host: url.host ?? "", path: url.path, statusCode: nil, duration: duration, errorCategory: String(reflecting: error))
            throw map(error)
        }
    }

    private func upload(_ data: Data, to url: URL, headers: RequiredHeaders) async throws {
        let request = try uploadRequest(to: url, headers: headers)
        let response = try await transport.upload(for: request, data: data)
        try validateUploadResponse(response)
    }

    private func upload(
        _ source: FeedbackAttachmentSource,
        to url: URL,
        headers: RequiredHeaders
    ) async throws {
        let request = try uploadRequest(to: url, headers: headers)
        let response: HTTPURLResponse
        switch source.storage {
        case let .data(data):
            response = try await transport.upload(for: request, data: data)
        case let .file(fileURL):
            response = try await transport.upload(for: request, fromFile: fileURL)
        }
        try validateUploadResponse(response)
    }

    private func uploadRequest(to url: URL, headers: RequiredHeaders) throws -> URLRequest {
        guard url.isFeedbackSecureTransportURL else { throw FeedbackClientError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(headers.contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(headers.contentLength, forHTTPHeaderField: "Content-Length")
        if let checksumSHA256 = headers.checksumSHA256 {
            request.setValue(checksumSHA256, forHTTPHeaderField: "X-Amz-Checksum-Sha256")
        }
        return request
    }

    private func validateUploadResponse(_ response: HTTPURLResponse) throws {
        guard (200...299).contains(response.statusCode) else {
            throw FeedbackClientError.server(statusCode: response.statusCode, code: nil)
        }
    }

    private func makeURL(scope: Scope, path: String, query: [URLQueryItem]) throws -> URL {
        guard configuration.baseURL.isFeedbackSecureTransportURL else {
            throw FeedbackClientError.invalidURL
        }
        var url = configuration.baseURL.appending(path: scope.rawValue)
        for component in path.split(separator: "/") { url.append(path: String(component)) }
        guard query.isEmpty == false else {
            guard url.isFeedbackSecureTransportURL else { throw FeedbackClientError.invalidURL }
            return url
        }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw FeedbackClientError.invalidURL }
        components.queryItems = query
        guard let result = components.url, result.isFeedbackSecureTransportURL else {
            throw FeedbackClientError.invalidURL
        }
        return result
    }

    private func httpError(_ data: Data, _ response: HTTPURLResponse) -> FeedbackClientError {
        let code = try? FeedbackCoding.decoder().decode(FeedbackErrorEnvelope.self, from: data).code
        switch response.statusCode {
        case 401: return .unauthorized(code: code)
        case 403: return .forbidden(code: code)
        case 404: return .notFound
        case 413: return .payloadTooLarge
        case 422: return .validation(code: code)
        case 429: return .rateLimited(retryAfter: response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init))
        default: return .server(statusCode: response.statusCode, code: code)
        }
    }

    private func map(_ error: Error) -> FeedbackClientError {
        if let error = error as? FeedbackClientError { return error }
        if let error = error as? URLError, [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed].contains(error.code) { return .offline }
        return .transport
    }
}

private extension Duration {
    var timeInterval: TimeInterval { TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18 }
}

private struct UploadDeclaration: Codable, Sendable { let filename: String; let contentType: String; let size: Int }
private struct UploadPresignRequest: Codable, Sendable { let files: [UploadDeclaration] }
private struct RequiredHeaders: Codable, Sendable {
    let contentType: String
    let contentLength: String
    let checksumSHA256: String?
    enum CodingKeys: String, CodingKey {
        case contentType = "Content-Type"
        case contentLength = "Content-Length"
        case checksumSHA256 = "X-Amz-Checksum-Sha256"
    }
}
private struct PresignedUpload: Codable, Sendable { let attachmentId: String; let uploadUrl: URL; let headers: RequiredHeaders; let expiresIn: Int }
private struct UploadFinalizeItem: Codable, Sendable { let id: String; let posterUploaded: Bool; let width: Int?; let height: Int?; let durationMs: Int? }
private struct UploadFinalizeRequest: Codable, Sendable { let attachments: [UploadFinalizeItem] }
private struct FinalizedAttachment: Codable, Sendable { let id: String }
private struct Ack: Codable, Sendable { let cursor: Int }
private struct DiagnosticPresignRequest: Codable, Sendable { let filename: String; let contentType: String; let size: Int; let sha256: String; let schemaVersion: Int }
private struct DiagnosticPresignResponse: Codable, Sendable { let diagnosticArtifactId: String; let uploadUrl: URL; let headers: RequiredHeaders; let expiresIn: Int }
private struct DiagnosticFinalizeRequest: Codable, Sendable { let diagnosticArtifactId: String }
private struct DiagnosticFinalizeResponse: Codable, Sendable { let id: String }
private struct VisitorMessageRequest: Codable, Sendable { let body: String }
