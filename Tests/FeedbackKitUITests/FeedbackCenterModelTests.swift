@testable import FeedbackKitCore
@testable import FeedbackKitUI
import FeedbackKitTestSupport
import Foundation
import Testing

private actor Credential: FeedbackVisitorCredentialProviding {
    func credential(for productKey: String) async throws -> String { "visitor-credential" }
    func deleteCredential(for productKey: String) async throws {}
}

private actor DiagnosticProvider: FeedbackDiagnosticsProviding {
    private(set) var snapshotCount = 0

    func makeDiagnosticSnapshot() async throws -> FeedbackDiagnosticSnapshot {
        snapshotCount += 1
        return .init(
            data: Data("{}".utf8),
            schemaVersion: 1,
            sha256: String(repeating: "a", count: 64)
        )
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

private actor SuspendingFeedbackTransport: FeedbackTransport {
    private(set) var didStart = false

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        didStart = true
        while Task.isCancelled == false {
            await Task.yield()
        }
        throw CancellationError()
    }

    func upload(for request: URLRequest, data: Data) async throws -> HTTPURLResponse {
        throw CancellationError()
    }
}

@MainActor
struct FeedbackCenterModelTests {
    @Test func cancellingInitialLoadClearsLoadingWithoutPresentingAnError() async {
        let transport = SuspendingFeedbackTransport()
        let client = FeedbackClient(
            configuration: .init(
                baseURL: URL(string: "https://example.com/v1/api")!,
                productKey: "pk_test"
            ),
            transport: transport,
            credentialStore: Credential()
        )
        let model = FeedbackCenterModel(client: client)
        let loadingTask = Task {
            await model.load(locale: Locale(identifier: "en"))
        }

        while await transport.didStart == false {
            await Task.yield()
        }
        #expect(model.isLoading == true)

        loadingTask.cancel()
        await loadingTask.value

        #expect(model.isLoading == false)
        #expect(model.error == nil)
        #expect(model.bootstrap == nil)
    }

    @Test func viewingFeedbackAcknowledgesThroughItsNewestInboxEvent() async throws {
        let feedbackID = "11111111-1111-4111-8111-111111111111"
        let transport = FeedbackFixtureTransport { request in
            switch (request.httpMethod, request.url?.path) {
            case ("GET", "/v1/api/client/bootstrap"):
                let json = #"{"code":"ok","message":"OK","data":{"product":{"slug":"app","name":"App","defaultLocale":"en","defaultFeedbackVisibility":"private","iconUrl":null,"attachmentLimits":{"count":5,"imageBytes":100,"videoBytes":200},"diagnostics":null},"activity":{"entries":[],"nextCursor":null},"roadmap":[],"changelog":[],"visitor":{"displayCode":"ABC-123","lastReadCursor":0},"inbox":{"events":[{"sequence":24,"feedbackId":"11111111-1111-4111-8111-111111111111","type":"admin.reply","createdAt":"2026-08-03T10:00:00.000Z"},{"sequence":25,"feedbackId":"22222222-2222-4222-8222-222222222222","type":"admin.reply","createdAt":"2026-08-03T11:00:00.000Z"}],"nextCursor":25,"acknowledgedCursor":0,"unreadCount":2,"hasMore":false}}}"#
                return (200, [:], Data(json.utf8))
            case ("POST", "/v1/api/client/inbox/ack"):
                #expect(String(decoding: request.httpBody ?? Data(), as: UTF8.self) == #"{"cursor":24}"#)
                return (200, [:], Data(#"{"code":"ok","message":"OK","data":{"cursor":24}}"#.utf8))
            default:
                Issue.record("Unexpected request: \(request.httpMethod ?? "") \(request.url?.path ?? "")")
                return (500, [:], Data())
            }
        }
        let client = FeedbackClient(
            configuration: .init(baseURL: URL(string: "https://example.com/v1/api")!, productKey: "pk_test"),
            transport: transport,
            credentialStore: Credential()
        )
        let model = FeedbackCenterModel(client: client)

        await model.load(locale: Locale(identifier: "en"))
        #expect(model.bootstrap?.inbox.unreadCount == 2)

        await model.markFeedbackRead(feedbackID: feedbackID)

        #expect(model.bootstrap?.inbox.acknowledgedCursor == 24)
        #expect(model.bootstrap?.inbox.unreadCount == 1)
        #expect(await transport.requests.count == 2)
    }

    @Test(arguments: FeedbackKind.allCases)
    func newComposerNeverPreselectsDiagnostics(_ kind: FeedbackKind) {
        let diagnostics = DiagnosticProvider()
        let model = makeComposer(
            kind: kind,
            product: makeProduct(diagnosticsEnabled: true),
            diagnostics: diagnostics
        )

        #expect(model.diagnosticsAvailable == true)
        #expect(model.includesDiagnostics == false)
    }

    @Test func unavailableDiagnosticsRemainOff() {
        let model = makeComposer(
            kind: .bug,
            product: makeProduct(diagnosticsEnabled: false),
            diagnostics: DiagnosticProvider()
        )

        #expect(model.diagnosticsAvailable == false)
        #expect(model.includesDiagnostics == false)
    }

    @Test(arguments: [true, false])
    func draftRestoresDiagnosticConsentOnlyWhileAvailable(_ diagnosticsAvailable: Bool) async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FeedbackDraftStore(directory: directory)
        try await store.save(
            FeedbackDraft(
                productSlug: "app",
                kind: .bug,
                title: "Title",
                body: "Body",
                includesDiagnostics: true
            )
        )
        let model = makeComposer(
            kind: .suggestion,
            product: makeProduct(diagnosticsEnabled: diagnosticsAvailable),
            diagnostics: DiagnosticProvider(),
            draftStore: store
        )

        await model.restore()

        #expect(model.includesDiagnostics == diagnosticsAvailable)
    }

    @Test func draftRestorePreservesSelectedFeedbackKind() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FeedbackDraftStore(directory: directory)
        try await store.save(
            FeedbackDraft(
                productSlug: "app",
                kind: .bug,
                title: "Title",
                body: "Body",
                includesDiagnostics: false
            )
        )
        let model = makeComposer(
            kind: .suggestion,
            product: makeProduct(diagnosticsEnabled: false),
            diagnostics: nil,
            draftStore: store
        )

        await model.restore()

        #expect(model.kind == .suggestion)
        #expect(model.title == "Title")
        #expect(model.body == "Body")
    }

    @Test(arguments: [false, true])
    func submissionUploadsDiagnosticsOnlyAfterExplicitConsent(_ includesDiagnostics: Bool) async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let diagnostics = DiagnosticProvider()
        let transport = submissionTransport(
            capabilityEnabled: true,
            expectedDiagnosticsIncluded: includesDiagnostics
        )
        let client = FeedbackClient(
            configuration: .init(
                baseURL: URL(string: "https://example.com/v1/api")!,
                productKey: "pk_test"
            ),
            diagnostics: diagnostics,
            transport: transport,
            credentialStore: Credential()
        )
        let model = FeedbackComposerModel(
            kind: .bug,
            product: makeProduct(diagnosticsEnabled: true),
            client: client,
            draftStore: FeedbackDraftStore(directory: directory)
        )
        model.body = "Reproduction details"
        model.includesDiagnostics = includesDiagnostics

        let locale = Locale(identifier: "en")
        #expect(
            await model.submit(
                locale: locale,
                localization: FeedbackLocalization(locale: locale)
            ) == true
        )

        let paths = await transport.requests.compactMap(\.url?.path)
        #expect(paths.contains("/v1/api/client/diagnostics/presign") == includesDiagnostics)
        #expect(paths.contains("/private") == includesDiagnostics)
        #expect(paths.contains("/v1/api/client/diagnostics/finalize") == includesDiagnostics)
        #expect(await diagnostics.snapshotCount == (includesDiagnostics ? 1 : 0))
    }

    @Test func successfulSubmissionClearsComposerDataAndDoesNotRestoreItsDraft() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FeedbackDraftStore(directory: directory)
        let transport = submissionTransport(
            capabilityEnabled: true,
            expectedDiagnosticsIncluded: true
        )
        let client = FeedbackClient(
            configuration: .init(
                baseURL: URL(string: "https://example.com/v1/api")!,
                productKey: "pk_test"
            ),
            diagnostics: DiagnosticProvider(),
            transport: transport,
            credentialStore: Credential()
        )
        let model = FeedbackComposerModel(
            kind: .bug,
            product: makeProduct(diagnosticsEnabled: true),
            client: client,
            draftStore: store
        )
        model.title = "Title"
        model.body = "Reproduction details"
        model.includesDiagnostics = true
        model.attachments = [
            FeedbackAttachmentSource(
                filename: "screenshot.png",
                contentType: "image/png",
                data: Data("image".utf8)
            )
        ]
        await model.saveDraft()

        let locale = Locale(identifier: "en")
        #expect(
            await model.submit(
                locale: locale,
                localization: FeedbackLocalization(locale: locale)
            ) == true
        )

        #expect(model.title.isEmpty)
        #expect(model.body.isEmpty)
        #expect(model.includesDiagnostics == false)
        #expect(model.attachments.isEmpty)
        #expect(model.uploadedAttachmentIDs == nil)

        await model.saveDraft()
        #expect(await store.load(productSlug: "app") == nil)
    }

    @Test func submissionFallsBackToNoDiagnosticsWhenServerDisablesCapability() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let diagnostics = DiagnosticProvider()
        let transport = submissionTransport(
            capabilityEnabled: false,
            expectedDiagnosticsIncluded: false
        )
        let client = FeedbackClient(
            configuration: .init(
                baseURL: URL(string: "https://example.com/v1/api")!,
                productKey: "pk_test"
            ),
            diagnostics: diagnostics,
            transport: transport,
            credentialStore: Credential()
        )
        let model = FeedbackComposerModel(
            kind: .bug,
            product: makeProduct(diagnosticsEnabled: true),
            client: client,
            draftStore: FeedbackDraftStore(directory: directory)
        )
        model.body = "Reproduction details"
        model.includesDiagnostics = true

        let locale = Locale(identifier: "en")
        #expect(
            await model.submit(
                locale: locale,
                localization: FeedbackLocalization(locale: locale)
            ) == true
        )
        #expect(model.includesDiagnostics == false)
        #expect(await diagnostics.snapshotCount == 0)
        #expect(
            await transport.requests.contains(where: {
                $0.url?.path.contains("/diagnostics/") == true
            }) == false
        )
    }

    private func makeComposer(
        kind: FeedbackKind,
        product: FeedbackProduct,
        diagnostics: (any FeedbackDiagnosticsProviding)?,
        draftStore: FeedbackDraftStore? = nil
    ) -> FeedbackComposerModel {
        FeedbackComposerModel(
            kind: kind,
            product: product,
            client: FeedbackClient(
                configuration: .init(
                    baseURL: URL(string: "https://example.com/v1/api")!,
                    productKey: "pk_test"
                ),
                diagnostics: diagnostics,
                credentialStore: Credential()
            ),
            draftStore: draftStore ?? FeedbackDraftStore(directory: temporaryDirectory())
        )
    }

    private func makeProduct(diagnosticsEnabled: Bool) -> FeedbackProduct {
        FeedbackProduct(
            slug: "app",
            name: "App",
            defaultLocale: "en",
            defaultFeedbackVisibility: .private,
            iconUrl: nil,
            attachmentLimits: .init(count: 5, imageBytes: 100, videoBytes: 200),
            diagnostics: diagnosticsEnabled
                ? .init(enabled: true, maxBytes: 262_144, schemaVersions: [1])
                : nil
        )
    }

    private func submissionTransport(
        capabilityEnabled: Bool,
        expectedDiagnosticsIncluded: Bool
    ) -> FeedbackFixtureTransport {
        FeedbackFixtureTransport { request in
            switch (request.httpMethod, request.url?.path) {
            case ("GET", "/v1/api/client/bootstrap"):
                let diagnostics = capabilityEnabled
                    ? #"{"enabled":true,"maxBytes":262144,"schemaVersions":[1]}"#
                    : "null"
                let json = #"{"code":"ok","message":"OK","data":{"product":{"slug":"app","name":"App","defaultLocale":"en","defaultFeedbackVisibility":"private","iconUrl":null,"attachmentLimits":{"count":5,"imageBytes":100,"videoBytes":200},"diagnostics":\#(diagnostics)},"activity":{"entries":[],"nextCursor":null},"roadmap":[],"changelog":[],"visitor":{"displayCode":"ABC-123","lastReadCursor":0},"inbox":{"events":[],"nextCursor":0,"acknowledgedCursor":0,"unreadCount":0,"hasMore":false}}}"#
                return (200, [:], Data(json.utf8))
            case ("POST", "/v1/api/client/diagnostics/presign"):
                let json = #"{"code":"ok","message":"OK","data":{"diagnosticArtifactId":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","uploadUrl":"https://storage.example/private","headers":{"Content-Type":"application/json","Content-Length":"2","X-Amz-Checksum-Sha256":"test-base64-checksum"},"expiresIn":900}}"#
                return (200, [:], Data(json.utf8))
            case ("PUT", "/private"):
                return (200, [:], Data())
            case ("POST", "/v1/api/client/diagnostics/finalize"):
                let json = #"{"code":"ok","message":"OK","data":{"id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","filename":"diagnostics.json","contentType":"application/json","sizeBytes":2,"sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","schemaVersion":1,"finalizedAt":"2026-08-03T10:00:00.000Z"}}"#
                return (200, [:], Data(json.utf8))
            case ("POST", "/v1/api/client/uploads/presign"):
                let json = #"{"code":"ok","message":"OK","data":[{"attachmentId":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","uploadUrl":"https://storage.example/attachment","headers":{"Content-Type":"image/png","Content-Length":"5"},"expiresIn":900}]}"#
                return (200, [:], Data(json.utf8))
            case ("PUT", "/attachment"):
                return (200, [:], Data())
            case ("POST", "/v1/api/client/uploads/finalize"):
                let json = #"{"code":"ok","message":"OK","data":[{"id":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"}]}"#
                return (200, [:], Data(json.utf8))
            case ("POST", "/v1/api/client/feedback"):
                let body = try #require(request.httpBody)
                let object = try #require(
                    JSONSerialization.jsonObject(with: body) as? [String: Any]
                )
                #expect(
                    ((object["diagnosticArtifactId"] as? String) != nil)
                        == expectedDiagnosticsIncluded
                )
                let json = #"{"code":"ok","message":"OK","data":{"id":"11111111-1111-4111-8111-111111111111","type":"bug","title":null,"displayTitle":"Reproduction details","body":"Reproduction details","status":"open","visibility":"private","publishedAt":null,"pinnedAt":null,"lastActivityAt":"2026-08-03T10:00:00.000Z","createdAt":"2026-08-03T10:00:00.000Z","updatedAt":"2026-08-03T10:00:00.000Z","diagnosticsIncluded":\#(expectedDiagnosticsIncluded)}}"#
                return (201, [:], Data(json.utf8))
            default:
                Issue.record(
                    "Unexpected request: \(request.httpMethod ?? "") \(request.url?.absoluteString ?? "")"
                )
                return (500, [:], Data())
            }
        }
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(
            path: "FeedbackKitUITests-\(UUID().uuidString)"
        )
    }
}
