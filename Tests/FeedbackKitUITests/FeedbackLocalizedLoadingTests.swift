@testable import FeedbackKitCore
@testable import FeedbackKitUI
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing

private extension Tag {
    @Tag static var localizedNetworking: Self
}

private actor LocalizedLoadingCredential: FeedbackVisitorCredentialProviding {
    func credential(for productKey: String) async throws -> String {
        "visitor-credential"
    }

    func deleteCredential(for productKey: String) async throws {}
}

private actor ControlledLocalizedLoadingTransport: FeedbackTransport {
    private var firstRequestContinuation: CheckedContinuation<Void, Never>?
    private var firstRequestWaiters: [CheckedContinuation<Void, Never>] = []
    private var requestCount = 0

    func waitForFirstRequest() async {
        guard requestCount == 0 else { return }
        await withCheckedContinuation { continuation in
            firstRequestWaiters.append(continuation)
        }
    }

    func releaseFirstRequest() {
        firstRequestContinuation?.resume()
        firstRequestContinuation = nil
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requestCount += 1
        if requestCount == 1 {
            let waiters = firstRequestWaiters
            firstRequestWaiters.removeAll()
            waiters.forEach { $0.resume() }
            await withCheckedContinuation { continuation in
                firstRequestContinuation = continuation
            }
        }

        let locale = URLComponents(
            url: try #require(request.url),
            resolvingAgainstBaseURL: false
        )?.queryItems?.first(where: { $0.name == "locale" })?.value ?? "unknown"
        let data: Data
        switch request.url?.path {
        case "/v1/api/client/activity":
            data = Self.activityEnvelope(locale: locale)
        case "/v1/api/client/developer-posts/post-id":
            data = Self.developerPostEnvelope(locale: locale)
        default:
            throw URLError(.unsupportedURL)
        }
        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: 200,
                  httpVersion: "HTTP/1.1",
                  headerFields: [:]
              )
        else { throw URLError(.badServerResponse) }
        return (data, response)
    }

    func upload(for request: URLRequest, data: Data) async throws -> HTTPURLResponse {
        throw URLError(.unsupportedURL)
    }

    private static func activityEnvelope(locale: String) -> Data {
        Data(
            #"{"code":"ok","message":"OK","data":{"entries":[{"kind":"feedback","id":"feedback-id","pinnedAt":null,"activityAt":"2026-08-03T10:00:00.000Z","data":{"type":"bug","status":"open","title":null,"displayTitle":"\#(locale)","body":"Body","authorDisplayCode":"ABC-123","voteCount":0,"hasVoted":false,"createdAt":"2026-08-03T10:00:00.000Z"}}],"nextCursor":null}}"#.utf8
        )
    }

    private static func developerPostEnvelope(locale: String) -> Data {
        Data(
            #"{"code":"ok","message":"OK","data":{"id":"post-id","title":"\#(locale)","body":"Body","locale":"\#(locale)","action":null,"publishedAt":"2026-08-03T10:00:00.000Z","pinnedAt":null,"updatedAt":"2026-08-03T10:00:00.000Z"}}"#.utf8
        )
    }
}

@MainActor
struct FeedbackLocalizedLoadingTests {
    @Test(
        "The latest activity locale wins when an older request finishes last",
        .tags(.localizedNetworking)
    )
    func latestActivityLocaleWins() async throws {
        let transport = ControlledLocalizedLoadingTransport()
        let model = FeedbackActivityListModel(client: makeClient(transport: transport))

        let firstLoad = Task {
            await model.load(locale: Locale(identifier: "en"))
        }
        await transport.waitForFirstRequest()
        await model.load(locale: Locale(identifier: "zh-Hans"))
        await transport.releaseFirstRequest()
        await firstLoad.value

        let entry = try #require(model.entries.first)
        guard case let .feedback(_, summary) = entry else {
            Issue.record("Expected a feedback activity entry")
            return
        }
        #expect(summary.displayTitle == "zh-Hans")
        #expect(model.isLoading == false)
    }

    @Test(
        "The latest developer-post locale wins when an older request finishes last",
        .tags(.localizedNetworking)
    )
    func latestDeveloperPostLocaleWins() async throws {
        let transport = ControlledLocalizedLoadingTransport()
        let model = FeedbackDeveloperPostModel(
            id: "post-id",
            client: makeClient(transport: transport)
        )

        let firstLoad = Task {
            await model.load(locale: Locale(identifier: "en"))
        }
        await transport.waitForFirstRequest()
        await model.load(locale: Locale(identifier: "zh-Hans"))
        await transport.releaseFirstRequest()
        await firstLoad.value

        #expect(model.post?.title == "zh-Hans")
        #expect(model.isLoading == false)
    }

    private func makeClient(
        transport: ControlledLocalizedLoadingTransport
    ) -> FeedbackClient {
        FeedbackClient(
            configuration: .init(
                baseURL: URL(string: "https://example.com/v1/api")!,
                productKey: "pk_test"
            ),
            transport: transport,
            credentialStore: LocalizedLoadingCredential()
        )
    }
}
