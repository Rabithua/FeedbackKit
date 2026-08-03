import FeedbackKitCore
import FeedbackKitTestSupport
import Foundation
import Testing

private actor Credential: FeedbackVisitorCredentialProviding {
    var deleted = false
    func credential(for productKey: String) async throws -> String { "visitor-credential" }
    func deleteCredential(for productKey: String) async throws { deleted = true }
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
            configuration: .init(baseURL: URL(string: "https://example.com/v1/api")!, productKey: "pk_test"),
            transport: transport,
            credentialStore: Credential()
        )
        let result = try await client.bootstrap(locale: Locale(identifier: "en"))
        #expect(result.product.diagnostics?.supportsSchemaOne == true)
        #expect(result.activity.entries.count == 2)
        #expect(result.activity.nextCursor == "opaque")
    }

    @Test(arguments: ["validation_error", "validation_failed"])
    func treatsBothValidationCodesAsHTTP422(_ code: String) async throws {
        let transport = FeedbackFixtureTransport { _ in
            (422, [:], try FeedbackFixtureTransport.error(code: code, message: "Invalid"))
        }
        let client = FeedbackClient(
            configuration: .init(baseURL: URL(string: "https://example.com/v1/api")!, productKey: "pk_test"),
            transport: transport,
            credentialStore: Credential()
        )
        await #expect(throws: FeedbackClientError.validation(code: code)) {
            _ = try await client.ownedFeedback()
        }
    }

    @Test func releaseDetailUsesPublicEndpointLocaleAndDecodesCompleteBody() async throws {
        let releaseID = "66666666-6666-4666-8666-666666666666"
        let completeBody = "让大型笔记列表更流畅，并提升加载恢复和编辑可靠性。\n\n修复了附件、分享链接和输入区域的多个问题。"
        let transport = FeedbackFixtureTransport { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path == "/v1/api/public/releases/\(releaseID)")
            #expect(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems == [
                URLQueryItem(name: "locale", value: "zh-Hans-CN"),
            ])
            #expect(request.value(forHTTPHeaderField: "X-Product-Key") == "pk_test")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            let object: [String: Any] = [
                "code": "ok",
                "message": "OK",
                "data": [
                    "id": releaseID,
                    "version": "2.0.7",
                    "releasedAt": "2026-08-01T08:00:00Z",
                    "title": "Rote 2.0.7",
                    "body": completeBody,
                    "locale": "zh-Hans",
                    "items": [],
                ],
            ]
            return (200, [:], try JSONSerialization.data(withJSONObject: object))
        }
        let client = FeedbackClient(
            configuration: .init(baseURL: URL(string: "https://example.com/v1/api")!, productKey: "pk_test"),
            transport: transport,
            credentialStore: Credential()
        )

        let release = try await client.release(id: releaseID, locale: Locale(identifier: "zh-Hans-CN"))

        #expect(release.version == "2.0.7")
        #expect(release.body == completeBody)
        #expect(release.items.isEmpty)
    }

    @Test func diagnosticUploadUsesSeparateEndpointsAndExactHeaders() async throws {
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
            configuration: .init(baseURL: URL(string: "https://example.com/v1/api")!, productKey: "pk_test"),
            transport: transport,
            credentialStore: Credential()
        )
        let id = try await client.uploadDiagnosticSnapshot(.init(data: Data("{}".utf8), schemaVersion: 1, sha256: String(repeating: "a", count: 64)))
        #expect(id == "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
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
            configuration: .init(baseURL: URL(string: "https://example.com/v1/api")!, productKey: "pk_test"),
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
