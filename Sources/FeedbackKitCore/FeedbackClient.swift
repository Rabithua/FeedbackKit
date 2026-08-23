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
    private let observer: FeedbackClientObserver?
    private var latestDiagnosticsCapability: FeedbackDiagnosticsCapability?
    private static let serviceRestrictionCodes: Set<String> = [
        "feedback_feature_unavailable",
        "feedback_service_read_only",
        "feedback_storage_unavailable",
    ]

    public init(
        configuration: FeedbackConfiguration,
        diagnostics: (any FeedbackDiagnosticsProviding)? = nil,
        observer: FeedbackClientObserver? = nil,
        transport: any FeedbackTransport = URLSessionFeedbackTransport(),
        credentialStore: (any FeedbackVisitorCredentialProviding)? = nil,
        metadataProvider: any FeedbackAppMetadataProvider = DefaultFeedbackAppMetadataProvider()
    ) {
        self.configuration = configuration
        self.diagnostics = diagnostics
        diagnosticsProvider = diagnostics
        self.observer = observer
        self.transport = transport
        self.credentialStore = credentialStore ?? FeedbackVisitorCredentialStore(service: configuration.keychainService)
        self.metadataProvider = metadataProvider
    }

    public func bootstrap(locale: Locale, after: Int = 0) async throws -> FeedbackBootstrap {
        try await loadBootstrap(locale: locale, after: after, operation: .bootstrap)
    }

    /// Runs the normal bootstrap flow to verify Keychain, network, Product, and diagnostics setup.
    ///
    /// This explicit preflight creates or reuses the anonymous visitor identity. Constructing a
    /// client does not invoke it automatically.
    public func verifyIntegration(locale: Locale = .current) async throws -> FeedbackIntegrationSummary {
        let bootstrap = try await loadBootstrap(
            locale: locale,
            after: 0,
            operation: .verifyIntegration
        )
        return FeedbackIntegrationSummary(
            product: bootstrap.product,
            diagnostics: diagnosticsReadiness(for: bootstrap.product.diagnostics)
        )
    }

    private func loadBootstrap(
        locale: Locale,
        after: Int,
        operation: FeedbackClientOperation
    ) async throws -> FeedbackBootstrap {
        let bootstrap = try await get(
            FeedbackBootstrap.self,
            operation: operation,
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
        return try await get(
            FeedbackActivityPage.self,
            operation: .activity,
            path: "activity",
            query: query
        )
    }

    public func ownedFeedback(cursor: String? = nil) async throws -> OwnedFeedbackPage {
        var query = [URLQueryItem(name: "limit", value: "25")]
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        return try await get(
            OwnedFeedbackPage.self,
            operation: .ownedFeedback,
            path: "feedback",
            query: query
        )
    }

    public func feedback(id: String) async throws -> FeedbackDetail {
        try await get(
            FeedbackDetail.self,
            operation: .feedbackDetail,
            path: "feedback/\(id)"
        )
    }

    public func addVisitorMessage(feedbackID: String, body: String, idempotencyKey: String) async throws -> FeedbackMessage {
        try await send(
            FeedbackMessage.self,
            operation: .visitorMessage,
            method: .post,
            path: "feedback/\(feedbackID)/messages",
            body: VisitorMessageRequest(body: body),
            idempotencyKey: idempotencyKey
        )
    }

    public func developerPost(id: String, locale: Locale) async throws -> FeedbackDeveloperPost {
        try await get(
            FeedbackDeveloperPost.self,
            operation: .developerPost,
            path: "developer-posts/\(id)",
            query: [URLQueryItem(name: "locale", value: locale.feedbackContentIdentifier)]
        )
    }

    public func releases(locale: Locale) async throws -> [FeedbackRelease] {
        try await get(
            [FeedbackRelease].self,
            operation: .releases,
            scope: .public,
            path: "releases",
            query: [URLQueryItem(name: "locale", value: locale.feedbackContentIdentifier)]
        )
    }

    public func createFeedback(_ request: FeedbackCreateRequest, idempotencyKey: String) async throws -> OwnedFeedbackSummary {
        try await send(
            OwnedFeedbackSummary.self,
            operation: .createFeedback,
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
            guard let diagnostics else {
                throw FeedbackClientError(
                    kind: .diagnosticsUnavailable,
                    context: FeedbackFailureContext(operation: .createFeedback)
                )
            }
            let capability: FeedbackDiagnosticsCapability
            if let latestDiagnosticsCapability {
                capability = latestDiagnosticsCapability
            } else {
                guard let fetched = try await bootstrap(locale: locale).product.diagnostics else {
                    throw FeedbackClientError(
                        kind: .diagnosticsUnavailable,
                        context: FeedbackFailureContext(operation: .createFeedback)
                    )
                }
                capability = fetched
            }
            guard capability.supportsSchemaOne else {
                throw FeedbackClientError(
                    kind: .diagnosticsUnavailable,
                    context: FeedbackFailureContext(operation: .createFeedback)
                )
            }
            let snapshot = try await diagnostics.makeDiagnosticSnapshot(
                maxBytes: capability.maxBytes,
                locale: locale
            )
            guard snapshot.data.count <= capability.maxBytes else {
                throw FeedbackClientError(
                    kind: .payloadTooLarge,
                    context: FeedbackFailureContext(operation: .createFeedback)
                )
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
            operation: .vote,
            method: voted ? .put : .delete,
            path: "feedback/\(feedbackID)/vote"
        )
    }

    public func signedAttachmentURL(id: String) async throws -> FeedbackSignedAttachmentURL {
        try await get(
            FeedbackSignedAttachmentURL.self,
            operation: .attachmentURL,
            path: "attachments/\(id)/url"
        )
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
            operation: .attachmentPresign,
            method: .post,
            path: "uploads/presign",
            body: UploadPresignRequest(files: declarations)
        )
        guard presigned.count == sources.count else {
            throw FeedbackClientError(
                kind: .invalidResponse,
                context: FeedbackFailureContext(operation: .attachmentPresign)
            )
        }
        let pairs = Array(zip(presigned, sources))
        try await withThrowingTaskGroup(of: Void.self) { group in
            var iterator = pairs.makeIterator()
            for _ in 0..<min(2, pairs.count) {
                if let pair = iterator.next() {
                    group.addTask {
                        try await self.upload(
                            pair.1,
                            to: pair.0.uploadUrl,
                            headers: pair.0.headers,
                            operation: .attachmentUpload
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
                            headers: pair.0.headers,
                            operation: .attachmentUpload
                        )
                    }
                }
            }
        }
        let finalized = try await send(
            [FinalizedAttachment].self,
            operation: .attachmentFinalize,
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
        guard finalized.count == sources.count else {
            throw FeedbackClientError(
                kind: .invalidResponse,
                context: FeedbackFailureContext(operation: .attachmentFinalize)
            )
        }
        return presigned.map(\.attachmentId)
    }

    public func acknowledgeInbox(cursor: Int) async throws -> Int {
        try await send(
            Ack.self,
            operation: .inboxAcknowledge,
            method: .post,
            path: "inbox/ack",
            body: Ack(cursor: cursor)
        ).cursor
    }

    public func deleteVisitor() async throws {
        let _: Bool? = try await sendWithoutBody(
            Bool?.self,
            operation: .visitorDelete,
            method: .delete,
            path: "me"
        )
        try await credentialStore.deleteCredential(for: configuration.productKey)
    }

    public func uploadDiagnosticSnapshot(_ snapshot: FeedbackDiagnosticSnapshot) async throws -> String {
        let presigned = try await send(
            DiagnosticPresignResponse.self,
            operation: .diagnosticPresign,
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
            try await upload(
                snapshot.data,
                to: presigned.uploadUrl,
                headers: presigned.headers,
                operation: .diagnosticUpload
            )
            let finalized = try await send(
                DiagnosticFinalizeResponse.self,
                operation: .diagnosticFinalize,
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
               clientError.kind == .server,
               clientError.context.statusCode == 503,
               let code = clientError.context.serverCode,
               Self.serviceRestrictionCodes.contains(code) {
                throw clientError
            }
            if let clientError = error as? FeedbackClientError {
                throw FeedbackClientError(
                    kind: .diagnosticUploadFailed,
                    context: clientError.context
                )
            }
            throw FeedbackClientError(
                kind: .diagnosticUploadFailed,
                context: FeedbackFailureContext(
                    operation: .diagnosticUpload,
                    debugDescription: safeDebugDescription(for: error)
                )
            )
        }
    }

    private func diagnosticsReadiness(
        for capability: FeedbackDiagnosticsCapability?
    ) -> FeedbackDiagnosticsReadiness {
        guard let capability, capability.enabled else { return .disabled }
        guard capability.schemaVersions.contains(1) else {
            return .unsupportedSchema(capability.schemaVersions)
        }
        guard diagnostics != nil else {
            return .providerMissing(maxBytes: capability.maxBytes)
        }
        return .ready(maxBytes: capability.maxBytes)
    }

    private enum Scope: String { case client; case `public` }
    private enum Method: String { case get = "GET"; case post = "POST"; case put = "PUT"; case delete = "DELETE" }

    private func get<Value: Decodable & Sendable>(
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

    private func send<Body: Encodable & Sendable, Value: Decodable & Sendable>(
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

    private func sendWithoutBody<Value: Decodable & Sendable>(
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
            let url = try makeURL(scope: scope, path: path, query: query)
            requestURL = url
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
                let credential = try await credentialStore.credential(
                    for: configuration.productKey
                )
                request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
            }

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

    private func upload(
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

    private func upload(
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
        request.setValue(headers.contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(headers.contentLength, forHTTPHeaderField: "Content-Length")
        if let checksumSHA256 = headers.checksumSHA256 {
            request.setValue(checksumSHA256, forHTTPHeaderField: "X-Amz-Checksum-Sha256")
        }
        return request
    }

    private func makeURL(scope: Scope, path: String, query: [URLQueryItem]) throws -> URL {
        guard configuration.apiBaseURL.isFeedbackSecureTransportURL else {
            throw FeedbackClientError(kind: .invalidURL)
        }
        var url = configuration.apiBaseURL.appending(path: scope.rawValue)
        for component in path.split(separator: "/") { url.append(path: String(component)) }
        guard query.isEmpty == false else {
            guard url.isFeedbackSecureTransportURL else {
                throw FeedbackClientError(kind: .invalidURL)
            }
            return url
        }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw FeedbackClientError(kind: .invalidURL)
        }
        components.queryItems = query
        guard let result = components.url, result.isFeedbackSecureTransportURL else {
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

    private func safeDebugDescription(for error: Error) -> String {
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
