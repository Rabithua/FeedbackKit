import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public actor FeedbackClient {
    public let configuration: FeedbackConfiguration
    public nonisolated let diagnosticsProvider: (any FeedbackDiagnosticsProviding)?

    let transport: any FeedbackTransport
    let credentialStore: any FeedbackVisitorCredentialProviding
    let diagnostics: (any FeedbackDiagnosticsProviding)?
    let observer: FeedbackClientObserver?
    private let metadataProvider: any FeedbackAppMetadataProvider
    private var latestDiagnosticsCapability: FeedbackDiagnosticsCapability?

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

    /// Loads inbox events only when this Product already has an anonymous visitor identity.
    ///
    /// Unlike other visitor APIs, this method never creates or repairs a credential. It returns
    /// `nil` without making a network request when no existing credential is available. Omitting
    /// `after` lets FeedbackServer begin at the visitor's acknowledged cursor; pass a cursor only
    /// when continuing pagination.
    public func existingVisitorInbox(after: Int? = nil) async throws -> FeedbackInboxPage? {
        guard let credential = try await credentialStore.existingCredential(
            for: configuration.productKey
        ) else { return nil }

        let query = after.map { [URLQueryItem(name: "after", value: String($0))] } ?? []
        return try await get(
            FeedbackInboxPage.self,
            operation: .inbox,
            path: "inbox",
            query: query,
            existingCredential: credential
        )
    }

    /// Package-only counterpart used by FeedbackKitUI after an existing-identity inbox check.
    /// Keeping the same read-only identity rule ensures the SDK does not create a replacement
    /// visitor if the local credential disappears while the controller prepares a reply.
    package func existingVisitorFeedback(id: String) async throws -> FeedbackDetail? {
        guard let credential = try await credentialStore.existingCredential(
            for: configuration.productKey
        ) else { return nil }
        return try await get(
            FeedbackDetail.self,
            operation: .feedbackDetail,
            path: "feedback/\(id)",
            existingCredential: credential
        )
    }

    /// Acknowledges with an already established identity and never creates a replacement.
    package func acknowledgeExistingVisitorInbox(cursor: Int) async throws -> Int? {
        guard let credential = try await credentialStore.existingCredential(
            for: configuration.productKey
        ) else { return nil }
        return try await send(
            Ack.self,
            operation: .inboxAcknowledge,
            method: .post,
            path: "inbox/ack",
            body: Ack(cursor: cursor),
            existingCredential: credential
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
}
