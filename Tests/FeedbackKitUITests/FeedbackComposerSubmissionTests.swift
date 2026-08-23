@testable import FeedbackKitCore
@testable import FeedbackKitUI
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing

private extension Tag {
    @Tag static var submissionNetworking: Self
}

private actor SubmissionCredential: FeedbackVisitorCredentialProviding {
    func credential(for productKey: String) async throws -> String {
        "visitor-credential"
    }

    func deleteCredential(for productKey: String) async throws {}
}

private struct FeedbackSubmissionRecord: Sendable {
    let idempotencyKey: String?
    let body: Data
}

private actor ControlledSubmissionTransport: FeedbackTransport {
    private var feedbackStatusCodes: [Int]
    private let suspendsBootstrap: Bool
    private var bootstrapContinuation: CheckedContinuation<Void, Never>?
    private var bootstrapWaiters: [CheckedContinuation<Void, Never>] = []
    private var lastPresignedAttachmentIDs: [String] = []
    private(set) var attachmentPresignCount = 0
    private(set) var feedbackRecords: [FeedbackSubmissionRecord] = []

    init(feedbackStatusCodes: [Int], suspendsBootstrap: Bool = false) {
        self.feedbackStatusCodes = feedbackStatusCodes
        self.suspendsBootstrap = suspendsBootstrap
    }

    func waitForBootstrapRequest() async {
        guard bootstrapContinuation == nil else { return }
        await withCheckedContinuation { continuation in
            bootstrapWaiters.append(continuation)
        }
    }

    func releaseBootstrap() {
        guard let continuation = bootstrapContinuation else { return }
        bootstrapContinuation = nil
        continuation.resume()
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let path = request.url?.path else { throw URLError(.badURL) }
        switch (request.httpMethod, path) {
        case ("GET", "/v1/api/client/bootstrap"):
            if suspendsBootstrap {
                let waiters = bootstrapWaiters
                bootstrapWaiters.removeAll()
                waiters.forEach { $0.resume() }
                await withCheckedContinuation { continuation in
                    bootstrapContinuation = continuation
                }
                try Task.checkCancellation()
            }
            return try response(for: request, data: Self.bootstrapEnvelope)

        case ("POST", "/v1/api/client/uploads/presign"):
            attachmentPresignCount += 1
            let id = attachmentPresignCount == 1
                ? "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
                : "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
            lastPresignedAttachmentIDs = [id]
            let json = #"{"code":"ok","message":"OK","data":[{"attachmentId":"\#(id)","uploadUrl":"https://storage.example/attachment","headers":{"Content-Type":"image/png","Content-Length":"5"},"expiresIn":900}]}"#
            return try response(for: request, data: Data(json.utf8))

        case ("POST", "/v1/api/client/uploads/finalize"):
            let items = lastPresignedAttachmentIDs
                .map { #"{"id":"\#($0)"}"# }
                .joined(separator: ",")
            let json = #"{"code":"ok","message":"OK","data":[\#(items)]}"#
            return try response(for: request, data: Data(json.utf8))

        case ("POST", "/v1/api/client/feedback"):
            feedbackRecords.append(
                FeedbackSubmissionRecord(
                    idempotencyKey: request.value(forHTTPHeaderField: "Idempotency-Key"),
                    body: request.httpBody ?? Data()
                )
            )
            let statusCode = feedbackStatusCodes.isEmpty ? 201 : feedbackStatusCodes.removeFirst()
            if statusCode != 201 {
                let data = Data(
                    #"{"code":"feedback_storage_unavailable","message":"Unavailable"}"#.utf8
                )
                return try response(for: request, statusCode: statusCode, data: data)
            }
            return try response(for: request, statusCode: 201, data: Self.feedbackEnvelope)

        default:
            throw URLError(.unsupportedURL)
        }
    }

    func upload(for request: URLRequest, data: Data) async throws -> HTTPURLResponse {
        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: 200,
                  httpVersion: "HTTP/1.1",
                  headerFields: [:]
              )
        else { throw URLError(.badServerResponse) }
        return response
    }

    private func response(
        for request: URLRequest,
        statusCode: Int = 200,
        data: Data
    ) throws -> (Data, HTTPURLResponse) {
        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: statusCode,
                  httpVersion: "HTTP/1.1",
                  headerFields: [:]
              )
        else { throw URLError(.badServerResponse) }
        return (data, response)
    }

    private static let bootstrapEnvelope = Data(
        #"{"code":"ok","message":"OK","data":{"product":{"slug":"app","name":"App","defaultLocale":"en","defaultFeedbackVisibility":"private","iconUrl":null,"attachmentLimits":{"count":5,"imageBytes":100,"videoBytes":200},"diagnostics":null},"activity":{"entries":[],"nextCursor":null},"roadmap":[],"changelog":[],"visitor":{"displayCode":"ABC-123","lastReadCursor":0},"inbox":{"events":[],"nextCursor":0,"acknowledgedCursor":0,"unreadCount":0,"hasMore":false}}}"#.utf8
    )

    private static let feedbackEnvelope = Data(
        #"{"code":"ok","message":"OK","data":{"id":"11111111-1111-4111-8111-111111111111","type":"bug","title":null,"displayTitle":"Body","body":"Body","status":"open","visibility":"private","publishedAt":null,"pinnedAt":null,"lastActivityAt":"2026-08-03T10:00:00.000Z","createdAt":"2026-08-03T10:00:00.000Z","updatedAt":"2026-08-03T10:00:00.000Z","diagnosticsIncluded":false}}"#.utf8
    )
}

@MainActor
struct FeedbackComposerSubmissionTests {
    @Test("Unchanged retry reuses its idempotency key", .tags(.submissionNetworking))
    func unchangedRetryReusesIdempotencyKey() async throws {
        let context = makeContext(feedbackStatusCodes: [503, 201])
        defer { context.cleanup() }
        context.model.body = "Original body"

        #expect(await submit(context.model) == false)
        #expect(await submit(context.model) == true)

        let records = await context.transport.feedbackRecords
        #expect(records.count == 2)
        let firstKey = try #require(records.first?.idempotencyKey)
        let secondKey = try #require(records.last?.idempotencyKey)
        #expect(firstKey == secondKey)
    }

    @Test("Editing content after failure rotates the idempotency key", .tags(.submissionNetworking))
    func editedRetryUsesNewIdempotencyKey() async throws {
        let context = makeContext(feedbackStatusCodes: [503, 201])
        defer { context.cleanup() }
        context.model.body = "Original body"

        #expect(await submit(context.model) == false)
        context.model.body = "Edited body"
        #expect(await submit(context.model) == true)

        let records = await context.transport.feedbackRecords
        let firstKey = try #require(records.first?.idempotencyKey)
        let secondKey = try #require(records.last?.idempotencyKey)
        #expect(firstKey != secondKey)
        let secondBody = try requestObject(records.last?.body)
        #expect(secondBody["body"] as? String == "Edited body")
    }

    @Test("Changing locale rotates the idempotency key", .tags(.submissionNetworking))
    func localizedRetryUsesNewIdempotencyKey() async throws {
        let context = makeContext(feedbackStatusCodes: [503, 201])
        defer { context.cleanup() }
        context.model.body = "Body"

        #expect(await submit(context.model, localeIdentifier: "en") == false)
        #expect(await submit(context.model, localeIdentifier: "zh-Hans") == true)

        let records = await context.transport.feedbackRecords
        #expect(records.first?.idempotencyKey != records.last?.idempotencyKey)
        let secondBody = try requestObject(records.last?.body)
        let clientContext = try #require(secondBody["clientContext"] as? [String: Any])
        #expect(clientContext["locale"] as? String == "zh-Hans")
    }

    @Test("Changing attachments invalidates uploaded IDs", .tags(.submissionNetworking))
    func editedAttachmentsAreUploadedForRetry() async throws {
        let context = makeContext(feedbackStatusCodes: [503, 201])
        defer { context.cleanup() }
        context.model.body = "Body"
        context.model.attachments = [attachment(id: UUID(), filename: "first.png")]

        #expect(await submit(context.model) == false)
        context.model.attachments = [attachment(id: UUID(), filename: "second.png")]
        #expect(await submit(context.model) == true)

        #expect(await context.transport.attachmentPresignCount == 2)
        let records = await context.transport.feedbackRecords
        let firstBody = try requestObject(records.first?.body)
        let secondBody = try requestObject(records.last?.body)
        #expect(firstBody["attachmentIds"] as? [String] == ["bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"])
        #expect(secondBody["attachmentIds"] as? [String] == ["cccccccc-cccc-4ccc-8ccc-cccccccccccc"])
        #expect(records.first?.idempotencyKey != records.last?.idempotencyKey)
    }

    @Test("Submission uses a snapshot and preserves later edits", .tags(.submissionNetworking))
    func submissionSnapshotPreservesEditsMadeWhileAwaiting() async throws {
        let context = makeContext(feedbackStatusCodes: [201], suspendsBootstrap: true)
        defer { context.cleanup() }
        let originalAttachment = attachment(id: UUID(), filename: "original.png")
        let laterAttachment = attachment(id: UUID(), filename: "later.png")
        context.model.title = "Original title"
        context.model.body = "Original body"
        context.model.attachments = [originalAttachment]

        let submission = Task { await submit(context.model) }
        await context.transport.waitForBootstrapRequest()
        context.model.title = "Later title"
        context.model.body = "Later body"
        context.model.attachments = [laterAttachment]
        await context.transport.releaseBootstrap()

        #expect(await submission.value == true)
        let record = try #require(await context.transport.feedbackRecords.first)
        let submittedBody = try requestObject(record.body)
        #expect(submittedBody["title"] as? String == "Original title")
        #expect(submittedBody["body"] as? String == "Original body")
        #expect(context.model.title == "Later title")
        #expect(context.model.body == "Later body")
        #expect(context.model.attachments.map(\.id) == [laterAttachment.id])
        let draft = try #require(await context.store.load(productSlug: "app"))
        #expect(draft.title == "Later title")
        #expect(draft.body == "Later body")
    }

    @Test("Cancellation is silent and preserves the draft", .tags(.submissionNetworking))
    func cancelledSubmissionDoesNotPresentAnError() async throws {
        let context = makeContext(feedbackStatusCodes: [], suspendsBootstrap: true)
        defer { context.cleanup() }
        context.model.body = "Body"

        let submission = Task { await submit(context.model) }
        await context.transport.waitForBootstrapRequest()
        submission.cancel()
        await context.transport.releaseBootstrap()

        #expect(await submission.value == false)
        #expect(context.model.isSubmitting == false)
        #expect(context.model.errorMessage == nil)
        #expect(await context.store.load(productSlug: "app")?.body == "Body")
    }

    private func submit(
        _ model: FeedbackComposerModel,
        localeIdentifier: String = "en"
    ) async -> Bool {
        let locale = Locale(identifier: localeIdentifier)
        return await model.submit(
            locale: locale,
            localization: FeedbackLocalization(locale: locale)
        )
    }

    private func makeContext(
        feedbackStatusCodes: [Int],
        suspendsBootstrap: Bool = false
    ) -> SubmissionTestContext {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "FeedbackComposerSubmissionTests-\(UUID().uuidString)"
        )
        let transport = ControlledSubmissionTransport(
            feedbackStatusCodes: feedbackStatusCodes,
            suspendsBootstrap: suspendsBootstrap
        )
        let store = FeedbackDraftStore(directory: directory)
        let client = FeedbackClient(
            configuration: .init(
                baseURL: URL(string: "https://example.com/v1/api")!,
                productKey: "pk_test"
            ),
            transport: transport,
            credentialStore: SubmissionCredential()
        )
        let product = FeedbackProduct(
            slug: "app",
            name: "App",
            defaultLocale: "en",
            defaultFeedbackVisibility: .private,
            iconUrl: nil,
            attachmentLimits: .init(count: 5, imageBytes: 100, videoBytes: 200),
            diagnostics: nil
        )
        return SubmissionTestContext(
            model: FeedbackComposerModel(
                kind: .bug,
                product: product,
                client: client,
                draftStore: store
            ),
            transport: transport,
            store: store,
            directory: directory
        )
    }

    private func attachment(id: UUID, filename: String) -> FeedbackAttachmentSource {
        FeedbackAttachmentSource(
            id: id,
            filename: filename,
            contentType: "image/png",
            data: Data("image".utf8)
        )
    }

    private func requestObject(_ data: Data?) throws -> [String: Any] {
        let data = try #require(data)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

@MainActor
private struct SubmissionTestContext {
    let model: FeedbackComposerModel
    let transport: ControlledSubmissionTransport
    let store: FeedbackDraftStore
    let directory: URL

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }
}
