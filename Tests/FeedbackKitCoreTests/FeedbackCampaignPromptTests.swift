@testable import FeedbackKitCore
import FeedbackKitTestSupport
import Foundation
import Testing

private enum CampaignPromptCredentialError: Error, Equatable {
    case unavailable
}

private actor CampaignPromptCredential: FeedbackVisitorCredentialProviding {
    let existing: String?
    let existingError: CampaignPromptCredentialError?
    private(set) var existingRequests = 0
    private(set) var creationRequests = 0

    init(existing: String?, existingError: CampaignPromptCredentialError? = nil) {
        self.existing = existing
        self.existingError = existingError
    }

    func credential(for productKey: String) async throws -> String {
        creationRequests += 1
        return "created-campaign-visitor"
    }

    func existingCredential(for productKey: String) async throws -> String? {
        existingRequests += 1
        if let existingError { throw existingError }
        return existing
    }

    func deleteCredential(for productKey: String) async throws {}
}

struct FeedbackCampaignPromptTests {
    @Test("A missing identity uses the public prompt without creating a visitor")
    func untrackedPromptHasNoIdentitySideEffects() async throws {
        let credential = CampaignPromptCredential(existing: nil)
        let transport = FeedbackFixtureTransport { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path == "/v1/api/public/campaigns/prompt")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            #expect(
                request.value(forHTTPHeaderField: "X-FeedbackKit-Capabilities")
                    == "release-body-only,campaign-post-action"
            )
            return (200, [:], Self.promptEnvelope)
        }
        let client = makeClient(credential: credential, transport: transport)

        let prompt = try #require(try await client.campaignPrompt())

        #expect(prompt.identityState == .untracked)
        #expect(prompt.id == "11111111-1111-4111-8111-111111111111")
        #expect(prompt.preview.title == "Help us plan Q3")
        #expect(await credential.existingRequests == 1)
        #expect(await credential.creationRequests == 0)
        #expect(await transport.requests.count == 1)
    }

    @Test("An existing identity uses the client prompt and its original credential")
    func trackedPromptReusesExistingCredential() async throws {
        let credential = CampaignPromptCredential(existing: "existing-campaign-visitor")
        let transport = FeedbackFixtureTransport { request in
            #expect(request.url?.path == "/v1/api/client/campaigns/prompt")
            #expect(
                request.value(forHTTPHeaderField: "Authorization")
                    == "Bearer existing-campaign-visitor"
            )
            return (200, [:], Self.promptEnvelope)
        }
        let client = makeClient(credential: credential, transport: transport)

        let prompt = try #require(try await client.campaignPrompt())

        #expect(prompt.identityState == .existingVisitor)
        #expect(await credential.creationRequests == 0)
    }

    @Test("No candidate decodes as nil")
    func emptyPromptIsNil() async throws {
        let credential = CampaignPromptCredential(existing: nil)
        let transport = FeedbackFixtureTransport { _ in
            (200, [:], Data(#"{"code":"ok","message":"OK","data":{"campaign":null}}"#.utf8))
        }

        #expect(try await makeClient(credential: credential, transport: transport).campaignPrompt() == nil)
    }

    @Test("Credential inspection errors never fall back to the public endpoint")
    func credentialFailurePropagates() async {
        let credential = CampaignPromptCredential(existing: nil, existingError: .unavailable)
        let transport = FeedbackFixtureTransport { _ in
            Issue.record("A Keychain failure must not make a public request")
            return (500, [:], Data())
        }
        let client = makeClient(credential: credential, transport: transport)

        await #expect(throws: CampaignPromptCredentialError.unavailable) {
            try await client.campaignPrompt()
        }
        #expect(await credential.creationRequests == 0)
        #expect(await transport.requests.isEmpty)
    }

    @Test("Explicitly marking read creates one visitor and decodes the first timestamp")
    func markReadCreatesIdentity() async throws {
        let credential = CampaignPromptCredential(existing: nil)
        let transport = FeedbackFixtureTransport { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/v1/api/client/campaigns/11111111-1111-4111-8111-111111111111/read")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer created-campaign-visitor")
            return (
                200,
                [:],
                Data(#"{"code":"ok","message":"OK","data":{"campaignId":"11111111-1111-4111-8111-111111111111","readAt":"2026-09-05T01:00:00.000Z"}}"#.utf8)
            )
        }
        let client = makeClient(credential: credential, transport: transport)

        let receipt = try await client.markCampaignRead(
            id: "11111111-1111-4111-8111-111111111111"
        )

        #expect(receipt.campaignID == "11111111-1111-4111-8111-111111111111")
        #expect(receipt.readAt == Date(timeIntervalSince1970: 1_788_570_000))
        #expect(await credential.creationRequests == 1)
    }

    @Test("Campaign actions decode campaignId while preserving the target projection")
    func campaignActionWireShape() throws {
        let data = Data(
            #"{"type":"campaign","campaignId":"11111111-1111-4111-8111-111111111111","label":"Start"}"#.utf8
        )
        let action = try FeedbackCoding.decoder().decode(
            FeedbackDeveloperPostAction.self,
            from: data
        )

        #expect(action.type == .campaign)
        #expect(action.campaignID == "11111111-1111-4111-8111-111111111111")
        #expect(action.target == action.campaignID)

        let encoded = try #require(
            JSONSerialization.jsonObject(with: FeedbackCoding.encoder().encode(action))
                as? [String: Any]
        )
        #expect(encoded["campaignId"] as? String == action.campaignID)
        #expect(encoded["target"] == nil)
    }

    private func makeClient(
        credential: CampaignPromptCredential,
        transport: FeedbackFixtureTransport
    ) -> FeedbackClient {
        FeedbackClient(
            configuration: try! FeedbackConfiguration(
                productKey: "pk_campaign_prompt",
                keychainService: "test.campaign.prompt"
            ),
            transport: transport,
            credentialStore: credential
        )
    }

    private static let promptEnvelope = Data(
        #"{"code":"ok","message":"OK","data":{"campaign":{"id":"11111111-1111-4111-8111-111111111111","title":"Help us plan Q3","description":"Two questions","publishedAt":"2026-09-01T00:00:00.000Z","updatedAt":"2026-09-02T00:00:00.000Z"}}}"#.utf8
    )
}
