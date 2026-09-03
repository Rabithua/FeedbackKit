@testable import FeedbackKitCore
@testable import FeedbackKitUI
import FeedbackKitTestSupport
import Foundation
import Testing

private actor ReplyInboxCredential: FeedbackVisitorCredentialProviding {
    private var existing: String?
    private(set) var creationRequests = 0

    init(existing: String? = "visitor-credential") {
        self.existing = existing
    }

    func credential(for productKey: String) async throws -> String {
        creationRequests += 1
        return "visitor-credential"
    }

    func existingCredential(for productKey: String) async throws -> String? {
        existing
    }

    func deleteCredential(for productKey: String) async throws {}

    func removeExistingCredential() {
        existing = nil
    }
}

private actor SuspendingReplyInboxTransport: FeedbackTransport {
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

private actor CancellationThenSuccessReplyInboxTransport: FeedbackTransport {
    private(set) var requestCount = 0

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requestCount += 1
        if requestCount == 1 {
            while Task.isCancelled == false {
                await Task.yield()
            }
            throw CancellationError()
        }

        let data = Data(
            #"{"code":"ok","message":"OK","data":{"events":[],"nextCursor":0,"acknowledgedCursor":0,"unreadCount":0,"hasMore":false}}"#.utf8
        )
        guard let url = request.url,
              let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        ) else {
            throw URLError(.badURL)
        }
        return (data, response)
    }

    func upload(for request: URLRequest, data: Data) async throws -> HTTPURLResponse {
        throw CancellationError()
    }
}

@MainActor
struct FeedbackReplyInboxControllerTests {
    @Test("All pages are scanned and only the latest administrator reply is prepared")
    func preparesLatestReplyBeforeAcknowledging() async throws {
        let latestFeedbackID = "33333333-3333-4333-8333-333333333333"
        let credential = ReplyInboxCredential()
        let transport = FeedbackFixtureTransport { request in
            switch (request.httpMethod, request.url?.path, request.url?.query) {
            case ("GET", "/v1/api/client/inbox", nil):
                return (200, [:], Self.inboxPage(
                    events: [
                        Self.event(sequence: 10, feedbackID: "11111111-1111-4111-8111-111111111111", type: "admin.reply"),
                        Self.event(sequence: 20, feedbackID: "22222222-2222-4222-8222-222222222222", type: "feedback.status_changed"),
                    ],
                    nextCursor: 20,
                    unreadCount: 4,
                    hasMore: true
                ))
            case ("GET", "/v1/api/client/inbox", "after=20"):
                return (200, [:], Self.inboxPage(
                    events: [
                        Self.event(sequence: 30, feedbackID: latestFeedbackID, type: "admin.reply"),
                        Self.event(sequence: 31, feedbackID: latestFeedbackID, type: "feedback.status_changed"),
                    ],
                    nextCursor: 31,
                    unreadCount: 4,
                    hasMore: false
                ))
            case ("GET", "/v1/api/client/feedback/\(latestFeedbackID)", nil):
                return (200, [:], Self.detail(feedbackID: latestFeedbackID))
            case ("POST", "/v1/api/client/inbox/ack", nil):
                #expect(String(decoding: request.httpBody ?? Data(), as: UTF8.self) == #"{"cursor":30}"#)
                return (200, [:], Data(#"{"code":"ok","message":"OK","data":{"cursor":30}}"#.utf8))
            default:
                Issue.record("Unexpected request: \(request.httpMethod ?? "") \(request.url?.absoluteString ?? "")")
                return (500, [:], Data())
            }
        }
        let controller = FeedbackReplyInboxController(
            client: client(transport: transport, credential: credential)
        )

        await controller.beginForegroundCycle()
        let presentation = try #require(controller.pendingPresentation)

        #expect(presentation.cursor == 30)
        #expect(presentation.feedbackID == latestFeedbackID)
        #expect(presentation.detail.id == latestFeedbackID)
        #expect(await transport.requests.count == 3)
        #expect(await credential.creationRequests == 0)

        await controller.beginForegroundCycle()
        #expect(await transport.requests.count == 3)

        await controller.acknowledge(presentation)
        #expect(controller.lastAcknowledgedCursor == 30)
        #expect(await transport.requests.count == 4)

        await controller.acknowledge(presentation)
        #expect(await transport.requests.count == 4)
    }

    @Test("A page without an administrator reply is not acknowledged")
    func nonReplyEventsDoNotPresentOrAcknowledge() async {
        let credential = ReplyInboxCredential()
        let transport = FeedbackFixtureTransport { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path == "/v1/api/client/inbox")
            return (200, [:], Self.inboxPage(
                events: [Self.event(
                    sequence: 12,
                    feedbackID: "11111111-1111-4111-8111-111111111111",
                    type: "feedback.status_changed"
                )],
                nextCursor: 12,
                unreadCount: 1,
                hasMore: false
            ))
        }
        let controller = FeedbackReplyInboxController(
            client: client(transport: transport, credential: credential)
        )

        await controller.beginForegroundCycle()

        #expect(controller.pendingPresentation == nil)
        #expect(controller.lastAcknowledgedCursor == nil)
        #expect(await transport.requests.count == 1)
    }

    @Test("A deleted identity is not recreated when the prepared sheet appears")
    func missingCredentialAtAcknowledgementHasNoSideEffects() async throws {
        let feedbackID = "11111111-1111-4111-8111-111111111111"
        let credential = ReplyInboxCredential()
        let transport = FeedbackFixtureTransport { request in
            if request.url?.path == "/v1/api/client/inbox" {
                return (200, [:], Self.inboxPage(
                    events: [Self.event(sequence: 9, feedbackID: feedbackID, type: "admin.reply")],
                    nextCursor: 9,
                    unreadCount: 1,
                    hasMore: false
                ))
            }
            if request.url?.path == "/v1/api/client/feedback/\(feedbackID)" {
                return (200, [:], Self.detail(feedbackID: feedbackID))
            }
            Issue.record("A deleted identity must not reach the acknowledgement endpoint")
            return (500, [:], Data())
        }
        let controller = FeedbackReplyInboxController(
            client: client(transport: transport, credential: credential)
        )

        await controller.beginForegroundCycle()
        let presentation = try #require(controller.pendingPresentation)
        await credential.removeExistingCredential()

        await controller.acknowledge(presentation)

        #expect(controller.lastAcknowledgedCursor == nil)
        #expect(controller.lastError == nil)
        #expect(await credential.creationRequests == 0)
        #expect(await transport.requests.count == 2)
    }

    @Test("Ending a cycle permits exactly one new check in the next foreground cycle")
    func nextForegroundCycleCanCheckAgain() async {
        let credential = ReplyInboxCredential()
        let transport = FeedbackFixtureTransport { _ in
            (200, [:], Self.inboxPage(events: [], nextCursor: 0, unreadCount: 0, hasMore: false))
        }
        let controller = FeedbackReplyInboxController(
            client: client(transport: transport, credential: credential)
        )

        await controller.beginForegroundCycle()
        await controller.beginForegroundCycle()
        #expect(await transport.requests.count == 1)

        controller.endForegroundCycle()
        await controller.beginForegroundCycle()
        await controller.beginForegroundCycle()
        #expect(await transport.requests.count == 2)
    }

    @Test("A cursor acknowledged during pagination suppresses a stale reply")
    func concurrentAcknowledgementSuppressesStaleReply() async {
        let feedbackID = "11111111-1111-4111-8111-111111111111"
        let credential = ReplyInboxCredential()
        let transport = FeedbackFixtureTransport { request in
            switch request.url?.query {
            case nil:
                return (200, [:], Self.inboxPage(
                    events: [Self.event(sequence: 10, feedbackID: feedbackID, type: "admin.reply")],
                    nextCursor: 10,
                    unreadCount: 1,
                    hasMore: true
                ))
            case "after=10":
                return (200, [:], Self.inboxPage(
                    events: [],
                    nextCursor: 10,
                    acknowledgedCursor: 10,
                    unreadCount: 0,
                    hasMore: false
                ))
            default:
                Issue.record("A feedback detail or acknowledgement request was not expected")
                return (500, [:], Data())
            }
        }
        let controller = FeedbackReplyInboxController(
            client: client(transport: transport, credential: credential)
        )

        await controller.beginForegroundCycle()

        #expect(controller.pendingPresentation == nil)
        #expect(controller.lastAcknowledgedCursor == nil)
        #expect(await transport.requests.count == 2)
    }

    @Test("A stalled pagination cursor fails instead of repeatedly fetching the same page")
    func stalledCursorStopsPagination() async {
        let credential = ReplyInboxCredential()
        let transport = FeedbackFixtureTransport { _ in
            (200, [:], Self.inboxPage(
                events: [Self.event(
                    sequence: 10,
                    feedbackID: "11111111-1111-4111-8111-111111111111",
                    type: "feedback.status_changed"
                )],
                nextCursor: 10,
                unreadCount: 1,
                hasMore: true
            ))
        }
        let controller = FeedbackReplyInboxController(
            client: client(transport: transport, credential: credential)
        )

        await controller.beginForegroundCycle()

        #expect(controller.pendingPresentation == nil)
        #expect((controller.lastError as? FeedbackClientError)?.kind == .invalidResponse)
        #expect(await transport.requests.count == 2)
    }

    @Test("A detail failure never prepares or acknowledges a reply")
    func detailFailureDoesNotAcknowledge() async {
        let feedbackID = "11111111-1111-4111-8111-111111111111"
        let credential = ReplyInboxCredential()
        let transport = FeedbackFixtureTransport { request in
            if request.url?.path == "/v1/api/client/inbox" {
                return (200, [:], Self.inboxPage(
                    events: [Self.event(sequence: 7, feedbackID: feedbackID, type: "admin.reply")],
                    nextCursor: 7,
                    unreadCount: 1,
                    hasMore: false
                ))
            }
            if request.url?.path == "/v1/api/client/feedback/\(feedbackID)" {
                return (500, [:], try FeedbackFixtureTransport.error(code: "server_error", message: "Failed"))
            }
            Issue.record("An acknowledgement request was not expected")
            return (500, [:], Data())
        }
        let controller = FeedbackReplyInboxController(
            client: client(transport: transport, credential: credential)
        )

        await controller.beginForegroundCycle()

        #expect(controller.pendingPresentation == nil)
        #expect(controller.lastAcknowledgedCursor == nil)
        #expect(controller.lastError != nil)
        #expect(await transport.requests.count == 2)
    }

    @Test("Ending a foreground cycle cancels its in-flight check without an error")
    func endingCycleCancelsCheck() async {
        let transport = SuspendingReplyInboxTransport()
        let controller = FeedbackReplyInboxController(
            client: client(transport: transport, credential: ReplyInboxCredential())
        )
        let check = Task { await controller.beginForegroundCycle() }

        while await transport.didStart == false {
            await Task.yield()
        }
        #expect(controller.isChecking)

        controller.endForegroundCycle()
        await check.value

        #expect(controller.isChecking == false)
        #expect(controller.pendingPresentation == nil)
        #expect(controller.lastAcknowledgedCursor == nil)
        #expect(controller.lastError == nil)
    }

    @Test("A new active call replaces a cancelling check before its caller finishes")
    func cancellingCheckCanBeReplacedBeforeItsCallerFinishes() async {
        let transport = CancellationThenSuccessReplyInboxTransport()
        let controller = FeedbackReplyInboxController(
            client: client(transport: transport, credential: ReplyInboxCredential())
        )
        let firstCheck = Task { await controller.beginForegroundCycle() }

        while await transport.requestCount == 0 {
            await Task.yield()
        }
        firstCheck.cancel()
        await controller.beginForegroundCycle()
        await firstCheck.value
        await controller.beginForegroundCycle()

        #expect(controller.isChecking == false)
        #expect(controller.pendingPresentation == nil)
        #expect(controller.lastError == nil)
        #expect(await transport.requestCount == 2)
    }

    private func client(
        transport: any FeedbackTransport,
        credential: any FeedbackVisitorCredentialProviding
    ) -> FeedbackClient {
        FeedbackClient(
            configuration: try! FeedbackConfiguration(
                productKey: "pk_test",
                keychainService: "test.feedback.visitor"
            ),
            transport: transport,
            credentialStore: credential
        )
    }

    nonisolated private static func inboxPage(
        events: [String],
        nextCursor: Int,
        acknowledgedCursor: Int = 0,
        unreadCount: Int,
        hasMore: Bool
    ) -> Data {
        Data(
            #"{"code":"ok","message":"OK","data":{"events":[\#(events.joined(separator: ","))],"nextCursor":\#(nextCursor),"acknowledgedCursor":\#(acknowledgedCursor),"unreadCount":\#(unreadCount),"hasMore":\#(hasMore)}}"#.utf8
        )
    }

    nonisolated private static func event(
        sequence: Int,
        feedbackID: String,
        type: String
    ) -> String {
        #"{"sequence":\#(sequence),"feedbackId":"\#(feedbackID)","type":"\#(type)","createdAt":"2026-08-03T10:00:00.000Z"}"#
    }

    nonisolated private static func detail(feedbackID: String) -> Data {
        Data(
            #"{"code":"ok","message":"OK","data":{"id":"\#(feedbackID)","type":"bug","title":"Sync failed","displayTitle":"Sync failed","body":"Cannot sync","status":"open","visibility":"private","publishedAt":null,"pinnedAt":null,"lastActivityAt":"2026-08-03T11:00:00.000Z","createdAt":"2026-08-03T10:00:00.000Z","updatedAt":"2026-08-03T11:00:00.000Z","authorDisplayCode":"ABC-123","isOwner":true,"voteCount":0,"hasVoted":false,"messages":[{"id":"44444444-4444-4444-8444-444444444444","actor":"admin","body":"Please try again","createdAt":"2026-08-03T11:00:00.000Z"}],"attachments":[],"diagnosticsIncluded":false}}"#.utf8
        )
    }
}
