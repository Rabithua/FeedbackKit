@testable import FeedbackKitCore
import FeedbackKitTestSupport
import Foundation
import Testing

private extension Tag {
    @Tag static var liveNetworking: Self
}

@Suite(
    "FeedbackServer v2 live contract",
    .enabled(
        if: LiveFeedbackServerEnvironment.isConfigured,
        "Set FEEDBACKKIT_TEST_BASE_URL and FEEDBACKKIT_TEST_PRODUCT_KEY to enable."
    ),
    .tags(.liveNetworking)
)
struct FeedbackServerV2ContractTests {
    @Test("Public content and an isolated visitor workflow match the SDK contract", .timeLimit(.minutes(2)))
    func publicAndVisitorWorkflow() async throws {
        let environment = try LiveFeedbackServerEnvironment.load()
        let credentialStore = LiveFeedbackServerCredentialStore()
        let client = FeedbackClient(
            configuration: try FeedbackConfiguration(
                productKey: environment.productKey,
                keychainService: "FeedbackKitTests.live.v2",
                apiBaseURL: environment.baseURL
            ),
            credentialStore: credentialStore,
            metadataProvider: FeedbackFixedMetadataProvider(
                context: FeedbackClientContext(
                    appVersion: "2.0.0",
                    buildNumber: "contract-test",
                    osVersion: "contract-test",
                    deviceCategory: "desktop",
                    locale: "en"
                )
            )
        )

        do {
            try await exerciseContract(using: client)
        } catch {
            try? await client.deleteVisitor()
            throw error
        }
        try await client.deleteVisitor()
    }

    private func exerciseContract(using client: FeedbackClient) async throws {
        let locale = Locale(identifier: "en")
        let bootstrap = try await client.bootstrap(locale: locale)

        #expect(bootstrap.product.slug.isEmpty == false)
        #expect(bootstrap.product.name.isEmpty == false)
        #expect(bootstrap.visitor.displayCode.isEmpty == false)
        #expect(bootstrap.roadmap.allSatisfy { $0.id.isEmpty == false })

        let releases = try await client.releases(locale: locale)
        #expect(releases.allSatisfy { $0.id.isEmpty == false && $0.version.isEmpty == false })

        let runID = UUID().uuidString.lowercased()
        let attachmentData = try #require(
            Data(
                base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
            )
        )
        let attachmentIDs = try await uploadAttachmentWhenSupported(
            data: attachmentData,
            runID: runID,
            limits: bootstrap.product.attachmentLimits,
            client: client
        )
        let body = "Opt-in FeedbackKit 2.0 live contract verification. Run \(runID)."
        let created = try await client.submitFeedback(
            type: .bug,
            title: "FeedbackKit 2.0 contract \(runID.prefix(8))",
            body: body,
            locale: locale,
            attachmentIds: attachmentIDs,
            includeDiagnostics: false,
            idempotencyKey: "feedbackkit-v2-feedback-\(runID)"
        )

        #expect(created.id.isEmpty == false)
        #expect(created.status == .open)

        let ownedPage = try await client.ownedFeedback()
        #expect(ownedPage.feedback.contains { $0.id == created.id })

        let detail = try await client.feedback(id: created.id)
        #expect(detail.id == created.id)
        #expect(detail.body == body)
        #expect(detail.status == .open)
        #expect(detail.isOwner)

        if let attachmentID = attachmentIDs.first {
            let attachment = try #require(
                detail.attachments.first { $0.id == attachmentID },
                "Submitted attachment must be present on the owned feedback detail."
            )
            #expect(attachment.sizeBytes == attachmentData.count)
            let signedURL = try await client.signedAttachmentURL(id: attachment.id)
            #expect(signedURL.url.absoluteString.isEmpty == false)
        }

        let messageBody = "Visitor follow-up from contract run \(runID)."
        let message = try await client.addVisitorMessage(
            feedbackID: created.id,
            body: messageBody,
            idempotencyKey: "feedbackkit-v2-message-\(runID)"
        )
        #expect(message.actor == "visitor")
        #expect(message.body == messageBody)

        let updatedDetail = try await client.feedback(id: created.id)
        #expect(updatedDetail.status == .open)
        #expect(
            updatedDetail.messages.contains {
                $0.id == message.id && $0.actor == "visitor" && $0.body == messageBody
            }
        )

        let inbox = try #require(try await client.existingVisitorInbox())
        #expect(inbox.acknowledgedCursor <= inbox.nextCursor)
    }

    private func uploadAttachmentWhenSupported(
        data: Data,
        runID: String,
        limits: FeedbackAttachmentLimits,
        client: FeedbackClient
    ) async throws -> [String] {
        guard limits.count > 0, limits.imageBytes >= data.count else {
            #expect(try await client.uploadAttachments([]).isEmpty)
            return []
        }

        return try await client.uploadAttachments([
            FeedbackAttachmentSource(
                filename: "feedbackkit-v2-contract-\(runID).png",
                contentType: "image/png",
                data: data,
                width: 1,
                height: 1
            ),
        ])
    }
}

private struct LiveFeedbackServerEnvironment {
    let baseURL: URL
    let productKey: String

    static var isConfigured: Bool {
        nonEmptyValue(named: "FEEDBACKKIT_TEST_BASE_URL") != nil
            && nonEmptyValue(named: "FEEDBACKKIT_TEST_PRODUCT_KEY") != nil
    }

    static func load() throws -> Self {
        guard let baseURLValue = nonEmptyValue(named: "FEEDBACKKIT_TEST_BASE_URL"),
              let productKey = nonEmptyValue(named: "FEEDBACKKIT_TEST_PRODUCT_KEY"),
              let baseURL = URL(string: baseURLValue),
              baseURL.query == nil,
              baseURL.fragment == nil
        else {
            throw LiveFeedbackServerEnvironmentError.invalidConfiguration
        }

        let normalizedPath = baseURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard normalizedPath.hasSuffix("v1/api") else {
            throw LiveFeedbackServerEnvironmentError.baseURLMustIncludeAPIPath
        }
        return Self(baseURL: baseURL, productKey: productKey)
    }

    private static func nonEmptyValue(named name: String) -> String? {
        guard let value = ProcessInfo.processInfo.environment[name]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              value.isEmpty == false
        else { return nil }
        return value
    }
}

private enum LiveFeedbackServerEnvironmentError: Error {
    case invalidConfiguration
    case baseURLMustIncludeAPIPath
}

private actor LiveFeedbackServerCredentialStore: FeedbackVisitorCredentialProviding {
    private var value: String?

    init() {
        value = Self.makeCredential()
    }

    func credential(for productKey: String) throws -> String {
        guard let value else { throw LiveFeedbackServerCredentialError.deleted }
        return value
    }

    func existingCredential(for productKey: String) throws -> String? {
        value
    }

    func deleteCredential(for productKey: String) {
        value = nil
    }

    private static func makeCredential() -> String {
        Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private enum LiveFeedbackServerCredentialError: Error {
    case deleted
}
