import FeedbackKitCore
import FeedbackKitDiagnostics
import Foundation

enum DemoClientFactory {
    static func fixture(scenario: DemoScenario) -> FeedbackClient {
        FeedbackClient(
            configuration: try! FeedbackConfiguration(
                productKey: "pk_feedbackkit_demo",
                keychainService: "cn.feedkit.demo.fixture.visitor"
            ),
            diagnostics: FeedbackDiagnostics(),
            observer: .osLog(subsystem: "cn.feedkit.demo", category: "Fixture"),
            transport: DemoFixtureTransport(scenario: scenario),
            credentialStore: DemoFixtureCredentialStore()
        )
    }

    static func live(bundle: Bundle = .main) throws -> FeedbackClient {
        guard let productKey = bundle.object(
            forInfoDictionaryKey: FeedbackConfiguration.productKeyInfoDictionaryKey
        ) as? String else {
            throw FeedbackConfigurationError.missingInfoDictionaryValue(
                key: FeedbackConfiguration.productKeyInfoDictionaryKey
            )
        }
        let configuredService = (
            bundle.object(
                forInfoDictionaryKey: FeedbackConfiguration.keychainServiceInfoDictionaryKey
            ) as? String
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
        let configuration: FeedbackConfiguration
        if let configuredService, configuredService.isEmpty == false {
            configuration = try FeedbackConfiguration(
                productKey: productKey,
                keychainService: configuredService
            )
        } else {
            configuration = try FeedbackConfiguration(
                productKey: productKey,
                bundle: bundle
            )
        }
        return FeedbackClient(
            configuration: configuration,
            diagnostics: FeedbackDiagnostics(),
            observer: .osLog(
                subsystem: bundle.bundleIdentifier ?? "FeedbackKitDemo",
                category: "Live"
            )
        )
    }
}
