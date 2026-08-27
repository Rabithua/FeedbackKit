@testable import FeedbackKitCore
import FeedbackKitTestSupport
import Foundation
import Synchronization
import Testing

private actor Credential: FeedbackVisitorCredentialProviding {
    var deleted = false
    func credential(for productKey: String) async throws -> String { "visitor-credential" }
    func deleteCredential(for productKey: String) async throws { deleted = true }
}

private actor MaximumRecordingDiagnostics: FeedbackDiagnosticsProviding {
    private(set) var requestedMaximumBytes: Int?
    private(set) var requestedLocaleIdentifier: String?

    func makeDiagnosticSnapshot() async throws -> FeedbackDiagnosticSnapshot {
        .init(
            data: Data("{}".utf8),
            schemaVersion: 1,
            sha256: String(repeating: "a", count: 64)
        )
    }

    func makeDiagnosticSnapshot(maxBytes: Int) async throws -> FeedbackDiagnosticSnapshot {
        requestedMaximumBytes = maxBytes
        return try await makeDiagnosticSnapshot()
    }

    func makeDiagnosticSnapshot(
        maxBytes: Int,
        locale: Locale
    ) async throws -> FeedbackDiagnosticSnapshot {
        requestedMaximumBytes = maxBytes
        requestedLocaleIdentifier = locale.identifier
        return try await makeDiagnosticSnapshot()
    }

    func recordNetwork(
        method: String,
        host: String,
        path: String,
        statusCode: Int?,
        duration: TimeInterval,
        errorCategory: String?
    ) async {}
}

struct FeedbackClientTests {
    @Test func bootstrapDecodesCapabilityAndMixedActivity() async throws {
        let transport = FeedbackFixtureTransport { request in
            #expect(request.value(forHTTPHeaderField: "X-Product-Key") == "pk_test")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer visitor-credential")
            let json = #"{"code":"ok","message":"OK","data":{"product":{"slug":"app","name":"App","defaultLocale":"en","defaultFeedbackVisibility":"private","iconUrl":null,"attachmentLimits":{"count":5,"imageBytes":100,"videoBytes":200},"diagnostics":{"enabled":true,"maxBytes":262144,"schemaVersions":[1]}},"activity":{"entries":[{"kind":"feedback","id":"11111111-1111-4111-8111-111111111111","pinnedAt":null,"activityAt":"2026-08-03T10:00:00.000Z","data":{"type":"bug","status":"open","title":null,"displayTitle":"Upload failed","body":"Details","authorDisplayCode":"ABC-123","voteCount":2,"hasVoted":false,"createdAt":"2026-08-03T10:00:00.000Z"}},{"kind":"developer_post","id":"22222222-2222-4222-8222-222222222222","pinnedAt":null,"activityAt":"2026-08-02T10:00:00.000Z","data":{"title":"News","body":"Body","locale":"en","action":null,"publishedAt":"2026-08-02T10:00:00.000Z","updatedAt":"2026-08-02T10:00:00.000Z"}}],"nextCursor":"opaque"},"roadmap":[],"changelog":[],"visitor":{"displayCode":"ABC-123","lastReadCursor":0},"inbox":{"events":[],"nextCursor":0,"acknowledgedCursor":0,"hasMore":false}}}"#
            return (200, [:], Data(json.utf8))
        }
        let client = FeedbackClient(
            configuration: try! FeedbackConfiguration(productKey: "pk_test", keychainService: "test.feedback.visitor"),
            transport: transport,
            credentialStore: Credential()
        )
        let result = try await client.bootstrap(locale: Locale(identifier: "en"))
        #expect(result.product.diagnostics?.supportsSchemaOne == true)
        #expect(result.activity.entries.count == 2)
        #expect(result.activity.nextCursor == "opaque")
    }

    @Test func inboxUsesServerCountInsteadOfSparseCursorDifference() async throws {
        let transport = FeedbackFixtureTransport { _ in
            let json = #"{"code":"ok","message":"OK","data":{"product":{"slug":"app","name":"App","defaultLocale":"en","defaultFeedbackVisibility":"private","iconUrl":null,"attachmentLimits":{"count":5,"imageBytes":100,"videoBytes":200},"diagnostics":null},"activity":{"entries":[],"nextCursor":null},"roadmap":[],"changelog":[],"visitor":{"displayCode":"ABC-123","lastReadCursor":0},"inbox":{"events":[{"sequence":25,"feedbackId":"11111111-1111-4111-8111-111111111111","type":"admin.reply","createdAt":"2026-08-03T10:00:00.000Z"}],"nextCursor":25,"acknowledgedCursor":0,"unreadCount":1,"hasMore":false}}}"#
            return (200, [:], Data(json.utf8))
        }
        let client = FeedbackClient(
            configuration: try! FeedbackConfiguration(productKey: "pk_test", keychainService: "test.feedback.visitor"),
            transport: transport,
            credentialStore: Credential()
        )

        let inbox = try await client.bootstrap(locale: Locale(identifier: "en")).inbox

        #expect(inbox.nextCursor - inbox.acknowledgedCursor == 25)
        #expect(inbox.unreadCount == 1)
        let acknowledged = inbox.acknowledging(through: 25)
        #expect(acknowledged.acknowledgedCursor == 25)
        #expect(acknowledged.unreadCount == 0)
    }

    @Test(arguments: ["validation_error", "validation_failed"])
    func treatsBothValidationCodesAsHTTP422(_ code: String) async throws {
        let transport = FeedbackFixtureTransport { _ in
            (422, [:], try FeedbackFixtureTransport.error(code: code, message: "Invalid"))
        }
        let client = FeedbackClient(
            configuration: try! FeedbackConfiguration(productKey: "pk_test", keychainService: "test.feedback.visitor"),
            transport: transport,
            credentialStore: Credential()
        )
        await expectClientError(
            kind: .validation,
            operation: .ownedFeedback,
            statusCode: 422,
            serverCode: code
        ) {
            _ = try await client.ownedFeedback()
        }
    }

    @Test(
        arguments: [
            "feedback_feature_unavailable",
            "feedback_service_read_only",
            "feedback_storage_unavailable",
        ]
    )
    func preservesServiceRestrictionMachineCode(_ code: String) async {
        let transport = FeedbackFixtureTransport { _ in
            (503, [:], try FeedbackFixtureTransport.error(code: code, message: "Unavailable"))
        }
        let client = FeedbackClient(
            configuration: try! FeedbackConfiguration(
                productKey: "pk_test",
                keychainService: "test.feedback.visitor"
            ),
            transport: transport,
            credentialStore: Credential()
        )

        await expectClientError(
            kind: .server,
            operation: .ownedFeedback,
            statusCode: 503,
            serverCode: code
        ) {
            _ = try await client.ownedFeedback()
        }
    }

    @Test func releaseListUsesPublicEndpointLocaleAndDecodesCompleteBody() async throws {
        let releaseID = "66666666-6666-4666-8666-666666666666"
        let completeBody = "让大型笔记列表更流畅，并提升加载恢复和编辑可靠性。\n\n修复了附件、分享链接和输入区域的多个问题。"
        let transport = FeedbackFixtureTransport { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path == "/v1/api/public/releases")
            #expect(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems == [
                URLQueryItem(name: "locale", value: "zh-Hans-CN"),
            ])
            #expect(request.value(forHTTPHeaderField: "X-Product-Key") == "pk_test")
            #expect(request.value(forHTTPHeaderField: "X-FeedbackKit-Capabilities") == "release-body-only")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            let object: [String: Any] = [
                "code": "ok",
                "message": "OK",
                "data": [[
                    "id": releaseID,
                    "version": "2.0.7",
                    "releasedAt": "2026-08-01T08:00:00Z",
                    "body": completeBody,
                    "locale": "zh-Hans",
                    "items": [],
                ]],
            ]
            return (200, [:], try JSONSerialization.data(withJSONObject: object))
        }
        let client = FeedbackClient(
            configuration: try! FeedbackConfiguration(productKey: "pk_test", keychainService: "test.feedback.visitor"),
            transport: transport,
            credentialStore: Credential()
        )

        let releases = try await client.releases(locale: Locale(identifier: "zh_CN"))
        let release = try #require(releases.first)

        #expect(release.version == "2.0.7")
        #expect(release.body == completeBody)
        #expect(release.items.isEmpty)
    }

    @Test func diagnosticUploadUsesSeparateEndpointsAndExactHeaders() async throws {
        let events = Mutex<[FeedbackClientEvent]>([])
        let uploadURL = URL(string: "https://storage.example/private?signature=secret")!
        let transport = FeedbackFixtureTransport { request in
            switch (request.httpMethod, request.url?.path) {
            case ("POST", "/v1/api/client/diagnostics/presign"):
                let json = #"{"code":"ok","message":"OK","data":{"diagnosticArtifactId":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","uploadUrl":"https://storage.example/private?signature=secret","headers":{"Content-Type":"application/json","Content-Length":"2","X-Amz-Checksum-Sha256":"test-base64-checksum"},"expiresIn":900}}"#
                return (200, [:], Data(json.utf8))
            case ("PUT", "/private"):
                #expect(request.url == uploadURL)
                #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
                #expect(request.value(forHTTPHeaderField: "Content-Length") == "2")
                #expect(request.value(forHTTPHeaderField: "X-Amz-Checksum-Sha256") == "test-base64-checksum")
                return (200, [:], Data())
            case ("POST", "/v1/api/client/diagnostics/finalize"):
                let json = #"{"code":"ok","message":"OK","data":{"id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","filename":"diagnostics.json","contentType":"application/json","sizeBytes":2,"sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","schemaVersion":1,"finalizedAt":"2026-08-03T10:00:00.000Z"}}"#
                return (200, [:], Data(json.utf8))
            default:
                Issue.record("Unexpected request: \(request.httpMethod ?? "") \(request.url?.absoluteString ?? "")")
                return (500, [:], Data())
            }
        }
        let client = FeedbackClient(
            configuration: try! FeedbackConfiguration(productKey: "pk_test", keychainService: "test.feedback.visitor"),
            observer: FeedbackClientObserver { event in
                events.withLock { $0.append(event) }
            },
            transport: transport,
            credentialStore: Credential()
        )
        let id = try await client.uploadDiagnosticSnapshot(.init(data: Data("{}".utf8), schemaVersion: 1, sha256: String(repeating: "a", count: 64)))
        #expect(id == "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
        #expect(events.withLock { $0.map(\.operation) } == [
            .diagnosticPresign,
            .diagnosticUpload,
            .diagnosticFinalize,
        ])
        #expect(events.withLock { $0.allSatisfy { $0.outcome == .succeeded } })
        let eventDescription = events.withLock { String(reflecting: $0) }
        #expect(eventDescription.contains("signature=secret") == false)
        #expect(eventDescription.contains("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa") == false)
    }

    @Test func submissionPassesTheServerDiagnosticLimitToTheProvider() async throws {
        let diagnostics = MaximumRecordingDiagnostics()
        let transport = FeedbackFixtureTransport { request in
            switch (request.httpMethod, request.url?.path) {
            case ("GET", "/v1/api/client/bootstrap"):
                let json = #"{"code":"ok","message":"OK","data":{"product":{"slug":"app","name":"App","defaultLocale":"en","defaultFeedbackVisibility":"private","iconUrl":null,"attachmentLimits":{"count":5,"imageBytes":100,"videoBytes":200},"diagnostics":{"enabled":true,"maxBytes":16384,"schemaVersions":[1]}},"activity":{"entries":[],"nextCursor":null},"roadmap":[],"changelog":[],"visitor":{"displayCode":"ABC-123","lastReadCursor":0},"inbox":{"events":[],"nextCursor":0,"acknowledgedCursor":0,"unreadCount":0,"hasMore":false}}}"#
                return (200, [:], Data(json.utf8))
            case ("POST", "/v1/api/client/diagnostics/presign"):
                let json = #"{"code":"ok","message":"OK","data":{"diagnosticArtifactId":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","uploadUrl":"https://storage.example/private","headers":{"Content-Type":"application/json","Content-Length":"2"},"expiresIn":900}}"#
                return (200, [:], Data(json.utf8))
            case ("PUT", "/private"):
                return (200, [:], Data())
            case ("POST", "/v1/api/client/diagnostics/finalize"):
                let json = #"{"code":"ok","message":"OK","data":{"id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","filename":"diagnostics.json","contentType":"application/json","sizeBytes":2,"sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","schemaVersion":1,"finalizedAt":"2026-08-03T10:00:00.000Z"}}"#
                return (200, [:], Data(json.utf8))
            case ("POST", "/v1/api/client/feedback"):
                let json = #"{"code":"ok","message":"OK","data":{"id":"11111111-1111-4111-8111-111111111111","type":"bug","title":null,"displayTitle":"Details","body":"Details","status":"open","visibility":"private","publishedAt":null,"pinnedAt":null,"lastActivityAt":"2026-08-03T10:00:00.000Z","createdAt":"2026-08-03T10:00:00.000Z","updatedAt":"2026-08-03T10:00:00.000Z","diagnosticsIncluded":true}}"#
                return (201, [:], Data(json.utf8))
            default:
                Issue.record("Unexpected request: \(request.httpMethod ?? "") \(request.url?.path ?? "")")
                return (500, [:], Data())
            }
        }
        let client = FeedbackClient(
            configuration: try! FeedbackConfiguration(
                productKey: "pk_test",
                keychainService: "test.feedback.visitor"
            ),
            diagnostics: diagnostics,
            transport: transport,
            credentialStore: Credential()
        )

        let submissionLocale = Locale(identifier: "zh_Hant_TW")
        _ = try await client.bootstrap(locale: submissionLocale)
        _ = try await client.submitFeedback(
            type: .bug,
            title: nil,
            body: "Details",
            locale: submissionLocale,
            includeDiagnostics: true,
            idempotencyKey: "diagnostic-limit"
        )

        #expect(await diagnostics.requestedMaximumBytes == 16_384)
        #expect(await diagnostics.requestedLocaleIdentifier == submissionLocale.identifier)
        #expect(await transport.requests.filter { $0.url?.path.hasSuffix("/bootstrap") == true }.count == 1)
    }

    @Test func diagnosticFinalizePreservesServiceRestrictionMachineCode() async {
        let code = "feedback_storage_unavailable"
        let transport = FeedbackFixtureTransport { request in
            switch (request.httpMethod, request.url?.path) {
            case ("POST", "/v1/api/client/diagnostics/presign"):
                let json = #"{"code":"ok","message":"OK","data":{"diagnosticArtifactId":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","uploadUrl":"https://storage.example/private","headers":{"Content-Type":"application/json","Content-Length":"2","X-Amz-Checksum-Sha256":"test-base64-checksum"},"expiresIn":900}}"#
                return (200, [:], Data(json.utf8))
            case ("PUT", "/private"):
                return (200, [:], Data())
            case ("POST", "/v1/api/client/diagnostics/finalize"):
                return (
                    503,
                    [:],
                    try FeedbackFixtureTransport.error(
                        code: code,
                        message: "Unavailable"
                    )
                )
            default:
                Issue.record(
                    "Unexpected request: \(request.httpMethod ?? "") \(request.url?.path ?? "")"
                )
                return (500, [:], Data())
            }
        }
        let client = FeedbackClient(
            configuration: try! FeedbackConfiguration(
                productKey: "pk_test",
                keychainService: "test.feedback.visitor"
            ),
            transport: transport,
            credentialStore: Credential()
        )

        await expectClientError(
            kind: .server,
            operation: .diagnosticFinalize,
            statusCode: 503,
            serverCode: code
        ) {
            _ = try await client.uploadDiagnosticSnapshot(
                .init(
                    data: Data("{}".utf8),
                    schemaVersion: 1,
                    sha256: String(repeating: "a", count: 64)
                )
            )
        }
    }

    @Test func diagnosticStorage503WithoutMachineCodeUsesDiagnosticFallback() async {
        let transport = FeedbackFixtureTransport { request in
            switch (request.httpMethod, request.url?.path) {
            case ("POST", "/v1/api/client/diagnostics/presign"):
                let json = #"{"code":"ok","message":"OK","data":{"diagnosticArtifactId":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","uploadUrl":"https://storage.example/private","headers":{"Content-Type":"application/json","Content-Length":"2","X-Amz-Checksum-Sha256":"test-base64-checksum"},"expiresIn":900}}"#
                return (200, [:], Data(json.utf8))
            case ("PUT", "/private"):
                return (503, [:], Data())
            default:
                Issue.record(
                    "Unexpected request: \(request.httpMethod ?? "") \(request.url?.path ?? "")"
                )
                return (500, [:], Data())
            }
        }
        let client = FeedbackClient(
            configuration: try! FeedbackConfiguration(
                productKey: "pk_test",
                keychainService: "test.feedback.visitor"
            ),
            transport: transport,
            credentialStore: Credential()
        )

        await expectClientError(
            kind: .diagnosticUploadFailed,
            operation: .diagnosticUpload,
            statusCode: 503
        ) {
            _ = try await client.uploadDiagnosticSnapshot(
                .init(
                    data: Data("{}".utf8),
                    schemaVersion: 1,
                    sha256: String(repeating: "a", count: 64)
                )
            )
        }
    }

    @Test func redirectPolicyRejectsInsecureOrMalformedTargets() {
        let policy = FeedbackSecureRedirectDelegate()
        let original = URLRequest(url: URL(string: "https://storage.example/private")!)

        #expect(policy.approvedRedirectRequest(
            URLRequest(url: URL(string: "https://storage.example:443/next")!),
            originalRequest: original
        ) != nil)
        #expect(policy.approvedRedirectRequest(
            URLRequest(url: URL(string: "https://other-storage.example/private")!),
            originalRequest: original
        ) == nil)
        #expect(policy.approvedRedirectRequest(
            URLRequest(url: URL(string: "https://storage.example:8443/private")!),
            originalRequest: original
        ) == nil)
        #expect(policy.approvedRedirectRequest(
            URLRequest(url: URL(string: "http://storage.example/private")!),
            originalRequest: original
        ) == nil)
        #expect(policy.approvedRedirectRequest(
            URLRequest(url: URL(string: "https:/storage.example/private")!),
            originalRequest: original
        ) == nil)
    }

    @Test func allowsLoopbackHTTPForLocalDevelopment() async throws {
        let transport = FeedbackFixtureTransport { request in
            #expect(request.url?.host == "127.0.0.1")
            return (200, [:], Data(#"{"code":"ok","message":"OK","data":{"feedback":[],"nextCursor":null}}"#.utf8))
        }
        let client = FeedbackClient(
            configuration: try! FeedbackConfiguration(
                productKey: "pk_test",
                keychainService: "test.feedback.visitor",
                apiBaseURL: URL(string: "http://127.0.0.1:3000/v1/api")!
            ),
            transport: transport,
            credentialStore: Credential()
        )

        _ = try await client.ownedFeedback()
        #expect(await transport.requests.count == 1)
    }

    @Test func rejectsInsecureRemotePresignedUploads() async {
        let transport = FeedbackFixtureTransport { request in
            if request.url?.path == "/v1/api/client/diagnostics/presign" {
                let json = #"{"code":"ok","message":"OK","data":{"diagnosticArtifactId":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","uploadUrl":"http://storage.example/private","headers":{"Content-Type":"application/json","Content-Length":"2"},"expiresIn":900}}"#
                return (200, [:], Data(json.utf8))
            }
            Issue.record("Unexpected insecure upload: \(request.url?.absoluteString ?? "")")
            return (500, [:], Data())
        }
        let client = FeedbackClient(
            configuration: try! FeedbackConfiguration(productKey: "pk_test", keychainService: "test.feedback.visitor"),
            transport: transport,
            credentialStore: Credential()
        )

        await expectClientError(
            kind: .diagnosticUploadFailed,
            operation: .diagnosticUpload
        ) {
            _ = try await client.uploadDiagnosticSnapshot(
                .init(data: Data("{}".utf8), schemaVersion: 1, sha256: String(repeating: "a", count: 64))
            )
        }
        #expect(await transport.requests.count == 1)
    }

    @Test func visitorMessageUsesOwnedConversationEndpointAndStableIdempotencyKey() async throws {
        let transport = FeedbackFixtureTransport { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/v1/api/client/feedback/11111111-1111-4111-8111-111111111111/messages")
            #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == "message-attempt-1")
            let body = try #require(request.httpBody)
            #expect(String(decoding: body, as: UTF8.self) == #"{"body":"Still happening"}"#)
            let json = #"{"code":"ok","message":"OK","data":{"id":"22222222-2222-4222-8222-222222222222","actor":"visitor","body":"Still happening","createdAt":"2026-08-03T10:00:00.000Z"}}"#
            return (201, ["Idempotency-Replayed": "false"], Data(json.utf8))
        }
        let client = FeedbackClient(
            configuration: try! FeedbackConfiguration(productKey: "pk_test", keychainService: "test.feedback.visitor"),
            transport: transport,
            credentialStore: Credential()
        )
        let message = try await client.addVisitorMessage(
            feedbackID: "11111111-1111-4111-8111-111111111111",
            body: "Still happening",
            idempotencyKey: "message-attempt-1"
        )
        #expect(message.actor == "visitor")
        #expect(message.body == "Still happening")
    }

    @Test func draftPersistsDiagnosticChoiceWithoutAttachmentState() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "FeedbackKitCoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FeedbackDraftStore(directory: directory)
        let draft = FeedbackDraft(productSlug: "app", kind: .bug, title: "Title", body: "Body", includesDiagnostics: false)
        try await store.save(draft)
        let restored = try #require(await store.load(productSlug: "app"))
        #expect(restored.productSlug == draft.productSlug)
        #expect(restored.kind == .bug)
        #expect(restored.title == "Title")
        #expect(restored.body == "Body")
        #expect(restored.includesDiagnostics == false)
        try await store.remove(productSlug: "app")
        #expect(await store.load(productSlug: "app") == nil)
    }
}

private func expectClientError(
    kind: FeedbackClientError.Kind,
    operation: FeedbackClientOperation,
    statusCode: Int? = nil,
    serverCode: String? = nil,
    performing operationBody: () async throws -> Void
) async {
    do {
        try await operationBody()
        Issue.record("Expected FeedbackClientError.\(kind.rawValue)")
    } catch let error as FeedbackClientError {
        #expect(error.kind == kind)
        #expect(error.context.operation == operation)
        #expect(error.context.statusCode == statusCode)
        #expect(error.context.serverCode == serverCode)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}
