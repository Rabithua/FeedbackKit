@testable import FeedbackKitCore
@testable import FeedbackKitUI
import FeedbackKitTestSupport
import Foundation
import Testing

private actor DeletingCredential: FeedbackVisitorCredentialProviding {
    private(set) var isDeleted = false

    func credential(for productKey: String) async throws -> String {
        "visitor-credential"
    }

    func deleteCredential(for productKey: String) async throws {
        isDeleted = true
    }
}

@MainActor
struct FeedbackIdentityModelTests {
    @Test func successfulRemovalDeletesTheServerVisitorAndLocalCredential() async {
        let credential = DeletingCredential()
        let transport = FeedbackFixtureTransport { request in
            #expect(request.httpMethod == "DELETE")
            #expect(request.url?.path == "/v1/api/client/me")
            return (
                200,
                [:],
                Data(#"{"code":"ok","message":"OK","data":null}"#.utf8)
            )
        }
        let client = FeedbackClient(
            configuration: try! FeedbackConfiguration(
                productKey: "pk_test",
                keychainService: "test.feedback.visitor"
            ),
            transport: transport,
            credentialStore: credential
        )
        let model = FeedbackIdentityModel(client: client, productSlug: nil)

        let didRemove = await model.remove()

        #expect(didRemove)
        #expect(model.isDeleting == false)
        #expect(model.error == nil)
        #expect(await credential.isDeleted)
    }

    @Test func failedRemovalKeepsTheErrorInTheModel() async {
        let transport = FeedbackFixtureTransport { _ in
            (
                500,
                [:],
                try FeedbackFixtureTransport.error(code: "server_error", message: "Failed")
            )
        }
        let client = FeedbackClient(
            configuration: try! FeedbackConfiguration(
                productKey: "pk_test",
                keychainService: "test.feedback.visitor"
            ),
            transport: transport,
            credentialStore: DeletingCredential()
        )
        let model = FeedbackIdentityModel(client: client, productSlug: nil)

        let didRemove = await model.remove()

        #expect(didRemove == false)
        #expect(model.isDeleting == false)
        #expect(model.error != nil)
    }
}
