@testable import FeedbackKitCore
@testable import FeedbackKitUI
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing

private extension Tag {
    @Tag static var networking: Self
}

private actor VoteCredential: FeedbackVisitorCredentialProviding {
    func credential(for productKey: String) async throws -> String {
        "visitor-credential"
    }

    func deleteCredential(for productKey: String) async throws {}
}

private actor ControlledVoteTransport: FeedbackTransport {
    private var firstVoteContinuation: CheckedContinuation<Void, Never>?
    private var firstVoteWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var voteRequestCount = 0

    func waitForFirstVoteRequest() async {
        guard voteRequestCount == 0 else { return }
        await withCheckedContinuation { continuation in
            firstVoteWaiters.append(continuation)
        }
    }

    func releaseFirstVote() {
        guard let continuation = firstVoteContinuation else { return }
        firstVoteContinuation = nil
        continuation.resume()
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url else { throw URLError(.badURL) }
        if url.path == "/v1/api/client/bootstrap" {
            return try response(for: request, data: Self.bootstrapEnvelope)
        }
        guard url.path.hasSuffix("/vote") else {
            throw URLError(.unsupportedURL)
        }

        voteRequestCount += 1
        let requestNumber = voteRequestCount
        if requestNumber == 1 {
            let waiters = firstVoteWaiters
            firstVoteWaiters.removeAll()
            waiters.forEach { $0.resume() }
            await withCheckedContinuation { continuation in
                firstVoteContinuation = continuation
            }
        }
        try Task.checkCancellation()

        let hasVoted = request.httpMethod == "PUT"
        let count = hasVoted ? 11 : 10
        let data = Data(
            #"{"code":"ok","message":"OK","data":{"feedbackId":"11111111-1111-4111-8111-111111111111","hasVoted":\#(hasVoted),"voteCount":\#(count)}}"#.utf8
        )
        return try response(for: request, data: data)
    }

    func upload(for request: URLRequest, data: Data) async throws -> HTTPURLResponse {
        throw URLError(.unsupportedURL)
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
        #"{"code":"ok","message":"OK","data":{"product":{"slug":"app","name":"App","defaultLocale":"en","defaultFeedbackVisibility":"private","iconUrl":null,"attachmentLimits":{"count":5,"imageBytes":100,"videoBytes":200},"diagnostics":null},"activity":{"entries":[{"kind":"feedback","id":"11111111-1111-4111-8111-111111111111","pinnedAt":null,"activityAt":"2026-08-03T10:00:00.000Z","data":{"type":"bug","status":"open","title":null,"displayTitle":"Title","body":"Body","authorDisplayCode":"ABC-123","voteCount":10,"hasVoted":false,"createdAt":"2026-08-03T10:00:00.000Z"}}],"nextCursor":null},"roadmap":[],"changelog":[],"visitor":{"displayCode":"ABC-123","lastReadCursor":0},"inbox":{"events":[],"nextCursor":0,"acknowledgedCursor":0,"unreadCount":0,"hasMore":false}}}"#.utf8
    )
}

@MainActor
struct FeedbackVoteModelTests {
    private let feedbackID = "11111111-1111-4111-8111-111111111111"

    @Test("Activity vote response follows its ID after entries reorder", .tags(.networking))
    func activityVoteResponseUsesCurrentIndex() async throws {
        let transport = ControlledVoteTransport()
        let model = FeedbackActivityListModel(client: makeClient(transport: transport))
        let target = activityEntry(id: feedbackID, voteCount: 10)
        let other = activityEntry(
            id: "22222222-2222-4222-8222-222222222222",
            voteCount: 3
        )
        model.entries = [target, other]

        let voteTask = Task {
            await model.optimisticVote(id: feedbackID, target: true)
        }
        await transport.waitForFirstVoteRequest()
        model.entries = [other, target]
        await transport.releaseFirstVote()

        #expect(await voteTask.value == true)
        let updatedTarget = try #require(
            model.entries.first(where: { $0.id == feedbackID })?.vote
        )
        let unchangedOther = try #require(
            model.entries.first(where: { $0.id == other.id })?.vote
        )
        #expect(updatedTarget.hasVoted == true)
        #expect(updatedTarget.count == 11)
        #expect(unchangedOther.hasVoted == false)
        #expect(unchangedOther.count == 3)
    }

    @Test("Activity list allows only one in-flight vote per feedback", .tags(.networking))
    func activityVoteIsDeduplicated() async {
        let transport = ControlledVoteTransport()
        let model = FeedbackActivityListModel(client: makeClient(transport: transport))
        model.entries = [activityEntry(id: feedbackID, voteCount: 10)]

        let firstVote = Task {
            await model.optimisticVote(id: feedbackID, target: true)
        }
        await transport.waitForFirstVoteRequest()
        let duplicateResult = await model.optimisticVote(id: feedbackID, target: true)
        let requestCount = await transport.voteRequestCount
        await transport.releaseFirstVote()

        #expect(duplicateResult == false)
        #expect(requestCount == 1)
        #expect(await firstVote.value == true)
    }

    @Test("Hub allows only one in-flight vote per feedback", .tags(.networking))
    func hubVoteIsDeduplicated() async {
        let transport = ControlledVoteTransport()
        let model = FeedbackCenterModel(client: makeClient(transport: transport))
        await model.load(locale: Locale(identifier: "en"))

        let firstVote = Task {
            await model.updateVote(feedbackID: feedbackID, target: true)
        }
        await transport.waitForFirstVoteRequest()
        let duplicateResult = await model.updateVote(feedbackID: feedbackID, target: true)
        let requestCount = await transport.voteRequestCount
        await transport.releaseFirstVote()

        #expect(duplicateResult == false)
        #expect(requestCount == 1)
        #expect(await firstVote.value == true)
    }

    @Test("Detail vote response preserves detail loaded while awaiting", .tags(.networking))
    func detailVotePreservesRefreshedContent() async throws {
        let transport = ControlledVoteTransport()
        let model = FeedbackDetailModel(
            id: feedbackID,
            client: makeClient(transport: transport),
            voteChanged: { _ in }
        )
        model.detail = feedbackDetail(messages: [])

        let voteTask = Task { await model.vote() }
        await transport.waitForFirstVoteRequest()
        let refreshedMessage = FeedbackMessage(
            id: "33333333-3333-4333-8333-333333333333",
            actor: "admin",
            body: "New reply",
            createdAt: Date(timeIntervalSince1970: 2)
        )
        model.detail = feedbackDetail(messages: [refreshedMessage])
        await transport.releaseFirstVote()

        #expect(await voteTask.value == true)
        let detail = try #require(model.detail)
        #expect(detail.messages == [refreshedMessage])
        #expect(detail.hasVoted == true)
        #expect(detail.voteCount == 11)
    }

    private func makeClient(transport: ControlledVoteTransport) -> FeedbackClient {
        FeedbackClient(
            configuration: .init(
                baseURL: URL(string: "https://example.com/v1/api")!,
                productKey: "pk_test"
            ),
            transport: transport,
            credentialStore: VoteCredential()
        )
    }

    private func activityEntry(id: String, voteCount: Int) -> FeedbackActivityEntry {
        .feedback(
            .init(
                id: id,
                pinnedAt: nil,
                activityAt: Date(timeIntervalSince1970: 1)
            ),
            .init(
                type: .bug,
                status: .open,
                title: nil,
                displayTitle: "Title",
                body: "Body",
                authorDisplayCode: "ABC-123",
                voteCount: voteCount,
                hasVoted: false,
                createdAt: Date(timeIntervalSince1970: 1)
            )
        )
    }

    private func feedbackDetail(messages: [FeedbackMessage]) -> FeedbackDetail {
        FeedbackDetail(
            id: feedbackID,
            type: .bug,
            title: "Title",
            displayTitle: "Title",
            body: "Body",
            status: .open,
            visibility: .public,
            publishedAt: Date(timeIntervalSince1970: 1),
            pinnedAt: nil,
            lastActivityAt: Date(timeIntervalSince1970: 1),
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1),
            authorDisplayCode: "ABC-123",
            isOwner: false,
            voteCount: 10,
            hasVoted: false,
            messages: messages,
            attachments: [],
            diagnosticsIncluded: false
        )
    }
}
