@testable import FeedbackKitUI
import FeedbackKitCore
import FeedbackKitTestSupport
import Foundation
import Testing

private actor Credential: FeedbackVisitorCredentialProviding {
    func credential(for productKey: String) async throws -> String { "visitor-credential" }
    func deleteCredential(for productKey: String) async throws {}
}

@MainActor
struct FeedbackCenterModelTests {
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
}
