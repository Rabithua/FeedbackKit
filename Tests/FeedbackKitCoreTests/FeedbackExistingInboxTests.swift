@testable import FeedbackKitCore
import FeedbackKitTestSupport
import Foundation
import Testing

private actor ExistingInboxCredential: FeedbackVisitorCredentialProviding {
    let existing: String?
    private(set) var creationRequests = 0

    init(existing: String?) {
        self.existing = existing
    }

    func credential(for productKey: String) async throws -> String {
        creationRequests += 1
        return "created-credential"
    }

    func existingCredential(for productKey: String) async throws -> String? {
        existing
    }

    func deleteCredential(for productKey: String) async throws {}
}

struct FeedbackExistingInboxTests {
    @Test("No established visitor causes no identity creation and no network request")
    func missingCredentialHasNoSideEffects() async throws {
        let credential = ExistingInboxCredential(existing: nil)
        let transport = FeedbackFixtureTransport { _ in
            Issue.record("A missing visitor credential must not reach the network")
            return (500, [:], Data())
        }
        let client = FeedbackClient(
            configuration: configuration(),
            transport: transport,
            credentialStore: credential
        )

        let inbox = try await client.existingVisitorInbox()

        #expect(inbox == nil)
        #expect(await credential.creationRequests == 0)
        #expect(await transport.requests.isEmpty)
    }

    @Test("An established visitor uses its existing credential and preserves cursor omission")
    func existingCredentialLoadsInboxWithoutCreatingIdentity() async throws {
        let credential = ExistingInboxCredential(existing: "existing-credential")
        let transport = FeedbackFixtureTransport { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path == "/v1/api/client/inbox")
            #expect(request.url?.query == nil)
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer existing-credential")
            return (
                200,
                [:],
                Data(
                    #"{"code":"ok","message":"OK","data":{"events":[],"nextCursor":42,"acknowledgedCursor":42,"unreadCount":0,"hasMore":false}}"#.utf8
                )
            )
        }
        let client = FeedbackClient(
            configuration: configuration(),
            transport: transport,
            credentialStore: credential
        )

        let inbox = try #require(try await client.existingVisitorInbox())

        #expect(inbox.acknowledgedCursor == 42)
        #expect(await credential.creationRequests == 0)
        #expect(await transport.requests.count == 1)
    }

    @Test("An explicit cursor is sent only for inbox pagination")
    func explicitCursorIsEncoded() async throws {
        let credential = ExistingInboxCredential(existing: "existing-credential")
        let transport = FeedbackFixtureTransport { request in
            #expect(request.url?.query == "after=42")
            return (
                200,
                [:],
                Data(
                    #"{"code":"ok","message":"OK","data":{"events":[],"nextCursor":42,"acknowledgedCursor":10,"unreadCount":0,"hasMore":false}}"#.utf8
                )
            )
        }
        let client = FeedbackClient(
            configuration: configuration(),
            transport: transport,
            credentialStore: credential
        )

        _ = try await client.existingVisitorInbox(after: 42)

        #expect(await credential.creationRequests == 0)
    }

    private func configuration() -> FeedbackConfiguration {
        try! FeedbackConfiguration(
            productKey: "pk_test",
            keychainService: "test.feedback.visitor"
        )
    }
}
