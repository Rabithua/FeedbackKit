@testable import FeedbackKitCore
import FeedbackKitTestSupport
import Foundation
import Synchronization
import Testing

struct FeedbackDeveloperExperienceTests {
    @Test func explicitConfigurationTrimsValuesAndUsesTheProductionEndpoint() throws {
        let configuration = try FeedbackConfiguration(
            productKey: "  pk_test  ",
            keychainService: "  com.example.feedback  "
        )

        #expect(configuration.productKey == "pk_test")
        #expect(configuration.keychainService == "com.example.feedback")
        #expect(configuration.apiBaseURL.absoluteString == "https://api.feedkit.cn/v1/api")
    }

    @Test func configurationRejectsEmptyValues() {
        #expect(throws: FeedbackConfigurationError.emptyProductKey) {
            _ = try FeedbackConfiguration(
                productKey: "  ",
                keychainService: "com.example.feedback"
            )
        }
        #expect(throws: FeedbackConfigurationError.emptyKeychainService) {
            _ = try FeedbackConfiguration(
                productKey: "pk_test",
                keychainService: "  "
            )
        }
    }

    @Test func bundleConfigurationDerivesAStableKeychainService() throws {
        let bundle = try makeBundle(info: [
            "CFBundleIdentifier": "com.example.HostApp",
            FeedbackConfiguration.productKeyInfoDictionaryKey: "pk_bundle",
        ])

        let configuration = try FeedbackConfiguration(bundle: bundle)

        #expect(configuration.productKey == "pk_bundle")
        #expect(configuration.keychainService == "com.example.HostApp.feedbackkit.visitor")
    }

    @Test func bundleConfigurationUsesAnExplicitKeychainService() throws {
        let bundle = try makeBundle(info: [
            "CFBundleIdentifier": "com.example.HostApp",
            FeedbackConfiguration.productKeyInfoDictionaryKey: "pk_bundle",
            FeedbackConfiguration.keychainServiceInfoDictionaryKey: "legacy.feedback.visitor",
        ])

        let configuration = try FeedbackConfiguration(bundle: bundle)

        #expect(configuration.keychainService == "legacy.feedback.visitor")
    }

    @Test func bundleConfigurationReportsMissingProductKey() throws {
        let bundle = try makeBundle(info: [
            "CFBundleIdentifier": "com.example.HostApp",
        ])

        #expect(
            throws: FeedbackConfigurationError.missingInfoDictionaryValue(
                key: FeedbackConfiguration.productKeyInfoDictionaryKey
            )
        ) {
            _ = try FeedbackConfiguration(bundle: bundle)
        }
    }

    @Test func productKeyConfigurationRequiresABundleIdentifier() throws {
        let bundle = try makeBundle(info: [:])

        #expect(throws: FeedbackConfigurationError.missingBundleIdentifier) {
            _ = try FeedbackConfiguration(productKey: "pk_test", bundle: bundle)
        }
    }

    @Test func requestsAlwaysUseTheFixedProductionEndpoint() async throws {
        let transport = FeedbackFixtureTransport { request in
            #expect(request.url?.scheme == "https")
            #expect(request.url?.host == "api.feedkit.cn")
            #expect(request.url?.path == "/v1/api/client/feedback")
            return (
                200,
                [:],
                Data(#"{"code":"ok","message":"OK","data":{"feedback":[],"nextCursor":null}}"#.utf8)
            )
        }
        let client = makeClient(transport: transport)

        _ = try await client.ownedFeedback()
    }

    @Test func constructingAClientDoesNotRunPreflight() async {
        let transport = FeedbackFixtureTransport { _ in
            Issue.record("Client construction must not perform a request")
            throw URLError(.badServerResponse)
        }

        _ = makeClient(transport: transport)

        #expect(await transport.requests.isEmpty)
    }

    @Test func verifyIntegrationReportsReadyDiagnostics() async throws {
        let transport = FeedbackFixtureTransport { _ in
            (200, [:], bootstrapEnvelope(diagnostics: #"{"enabled":true,"maxBytes":4096,"schemaVersions":[1]}"#))
        }
        let client = makeClient(
            diagnostics: DeveloperExperienceDiagnostics(),
            transport: transport
        )

        let summary = try await client.verifyIntegration(
            locale: Locale(identifier: "en")
        )

        #expect(summary.product.slug == "demo")
        #expect(summary.diagnostics == .ready(maxBytes: 4096))
    }

    @Test func verifyIntegrationReportsProviderAndSchemaProblems() async throws {
        let providerMissingTransport = FeedbackFixtureTransport { _ in
            (200, [:], bootstrapEnvelope(diagnostics: #"{"enabled":true,"maxBytes":4096,"schemaVersions":[1]}"#))
        }
        let providerMissing = makeClient(transport: providerMissingTransport)
        let providerMissingSummary = try await providerMissing.verifyIntegration()
        #expect(providerMissingSummary.diagnostics == .providerMissing(maxBytes: 4096))

        let unsupportedTransport = FeedbackFixtureTransport { _ in
            (200, [:], bootstrapEnvelope(diagnostics: #"{"enabled":true,"maxBytes":4096,"schemaVersions":[2]}"#))
        }
        let unsupported = makeClient(
            diagnostics: DeveloperExperienceDiagnostics(),
            transport: unsupportedTransport
        )
        let unsupportedSummary = try await unsupported.verifyIntegration()
        #expect(unsupportedSummary.diagnostics == .unsupportedSchema([2]))

        let disabledTransport = FeedbackFixtureTransport { _ in
            (200, [:], bootstrapEnvelope(diagnostics: "null"))
        }
        let disabled = makeClient(transport: disabledTransport)
        let disabledSummary = try await disabled.verifyIntegration()
        #expect(disabledSummary.diagnostics == .disabled)
    }

    @Test func verifyIntegrationPreservesAuthenticationAndNetworkFailures() async {
        let unauthorizedTransport = FeedbackFixtureTransport { _ in
            (
                401,
                ["X-Request-ID": "verify-unauthorized"],
                try FeedbackFixtureTransport.error(
                    code: "invalid_product_key",
                    message: "Invalid Product Key"
                )
            )
        }

        do {
            _ = try await makeClient(
                transport: unauthorizedTransport
            ).verifyIntegration()
            Issue.record("Expected an authentication failure")
        } catch let error as FeedbackClientError {
            #expect(error.kind == .unauthorized)
            #expect(error.context.operation == .verifyIntegration)
            #expect(error.context.statusCode == 401)
            #expect(error.context.requestID == "verify-unauthorized")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        let offlineTransport = FeedbackFixtureTransport { _ in
            throw URLError(.notConnectedToInternet)
        }
        do {
            _ = try await makeClient(
                transport: offlineTransport
            ).verifyIntegration()
            Issue.record("Expected an offline failure")
        } catch let error as FeedbackClientError {
            #expect(error.kind == .offline)
            #expect(error.context.operation == .verifyIntegration)
            #expect(error.context.debugDescription == "URLError(code: -1009)")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func observerReceivesSanitizedFailureContext() async {
        let events = Mutex<[FeedbackClientEvent]>([])
        let observer = FeedbackClientObserver { event in
            events.withLock { $0.append(event) }
        }
        let transport = FeedbackFixtureTransport { request in
            #expect(request.value(forHTTPHeaderField: "X-Product-Key") == "pk_test")
            return (
                429,
                ["Retry-After": "12", "X-Request-ID": "request-123"],
                try FeedbackFixtureTransport.error(
                    code: "rate_limited",
                    message: "Try later"
                )
            )
        }
        let client = makeClient(observer: observer, transport: transport)

        do {
            _ = try await client.ownedFeedback()
            Issue.record("Expected a rate-limited error")
        } catch let error as FeedbackClientError {
            #expect(error.kind == .rateLimited)
            #expect(error.context.operation == .ownedFeedback)
            #expect(error.context.statusCode == 429)
            #expect(error.context.serverCode == "rate_limited")
            #expect(error.context.requestID == "request-123")
            #expect(error.context.retryAfter == 12)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        let capturedEvents = events.withLock { $0 }
        #expect(capturedEvents.count == 1)
        let event = capturedEvents.first
        #expect(event?.operation == .ownedFeedback)
        #expect(event?.outcome == .failed)
        #expect(event?.statusCode == 429)
        #expect(event?.serverCode == "rate_limited")
        #expect(event?.requestID == "request-123")
        #expect(event?.failureKind == .rateLimited)
    }

    @Test func observerRecordsCancellationWithoutChangingTheThrownError() async {
        let events = Mutex<[FeedbackClientEvent]>([])
        let observer = FeedbackClientObserver { event in
            events.withLock { $0.append(event) }
        }
        let transport = FeedbackFixtureTransport { _ in
            throw CancellationError()
        }
        let client = makeClient(observer: observer, transport: transport)

        await #expect(throws: CancellationError.self) {
            _ = try await client.ownedFeedback()
        }

        let event = events.withLock { $0.first }
        #expect(event?.operation == .ownedFeedback)
        #expect(event?.outcome == .cancelled)
        #expect(event?.failureKind == nil)
    }

    @Test func decodingContextContainsOnlyTypeAndCodingPath() async {
        let transport = FeedbackFixtureTransport { _ in
            (
                200,
                [:],
                Data(
                    #"{"code":"ok","message":"OK","data":{"feedback":"private-body","nextCursor":null}}"#.utf8
                )
            )
        }
        let client = makeClient(transport: transport)

        do {
            _ = try await client.ownedFeedback()
            Issue.record("Expected a decoding error")
        } catch let error as FeedbackClientError {
            #expect(error.kind == .decoding)
            #expect(error.context.operation == .ownedFeedback)
            #expect(error.context.debugDescription?.contains("OwnedFeedbackPage") == true)
            #expect(error.context.debugDescription?.contains("data.feedback") == true)
            #expect(error.context.debugDescription?.contains("private-body") == false)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private func makeClient(
        diagnostics: (any FeedbackDiagnosticsProviding)? = nil,
        observer: FeedbackClientObserver? = nil,
        transport: FeedbackFixtureTransport
    ) -> FeedbackClient {
        FeedbackClient(
            configuration: try! FeedbackConfiguration(
                productKey: "pk_test",
                keychainService: "test.feedback.visitor"
            ),
            diagnostics: diagnostics,
            observer: observer,
            transport: transport,
            credentialStore: DeveloperExperienceCredential()
        )
    }

    private func makeBundle(info: [String: Any]) throws -> Bundle {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "FeedbackDeveloperExperienceTests-\(UUID().uuidString).bundle"
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        var bundleInfo: [String: Any] = ["CFBundlePackageType": "BNDL"]
        bundleInfo.merge(info) { _, supplied in supplied }
        let data = try PropertyListSerialization.data(
            fromPropertyList: bundleInfo,
            format: .xml,
            options: 0
        )
        try data.write(to: directory.appending(path: "Info.plist"))
        return try #require(Bundle(url: directory))
    }
}

private actor DeveloperExperienceCredential: FeedbackVisitorCredentialProviding {
    func credential(for productKey: String) async throws -> String {
        "visitor-credential"
    }

    func deleteCredential(for productKey: String) async throws {}
}

private struct DeveloperExperienceDiagnostics: FeedbackDiagnosticsProviding {
    func makeDiagnosticSnapshot() async throws -> FeedbackDiagnosticSnapshot {
        FeedbackDiagnosticSnapshot(data: Data(), schemaVersion: 1, sha256: "")
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

private func bootstrapEnvelope(diagnostics: String) -> Data {
    Data(
        """
        {"code":"ok","message":"OK","data":{"product":{"slug":"demo","name":"Demo","defaultLocale":"en","defaultFeedbackVisibility":"private","iconUrl":null,"attachmentLimits":{"count":5,"imageBytes":100,"videoBytes":200},"diagnostics":\(diagnostics)},"activity":{"entries":[],"nextCursor":null},"roadmap":[],"changelog":[],"visitor":{"displayCode":"ABC-123","lastReadCursor":0},"inbox":{"events":[],"nextCursor":0,"acknowledgedCursor":0,"unreadCount":0,"hasMore":false}}}
        """.utf8
    )
}
