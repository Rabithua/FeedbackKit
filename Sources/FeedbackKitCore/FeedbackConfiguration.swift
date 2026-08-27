import Foundation

/// Validated host configuration for the fixed FeedbackKit production API.
public struct FeedbackConfiguration: Sendable {
    /// The Info.plist key that contains the publishable Product Key.
    public static let productKeyInfoDictionaryKey = "FeedbackProductKey"
    /// The optional Info.plist key that preserves a host-owned Keychain service.
    public static let keychainServiceInfoDictionaryKey = "FeedbackKeychainService"

    /// The publishable key that binds requests to a FeedbackServer Product.
    public let productKey: String
    /// The stable Keychain service used for the anonymous visitor credential.
    public let keychainService: String

    internal let apiBaseURL: URL

    /// Creates configuration with an explicit, stable Keychain service.
    public init(productKey: String, keychainService: String) throws {
        try self.init(
            productKey: productKey,
            keychainService: keychainService,
            apiBaseURL: Self.productionAPIBaseURL
        )
    }

    /// Creates configuration and derives the Keychain service from the bundle identifier.
    public init(productKey: String, bundle: Bundle = .main) throws {
        guard let bundleIdentifier = bundle.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              bundleIdentifier.isEmpty == false
        else {
            throw FeedbackConfigurationError.missingBundleIdentifier
        }
        try self.init(
            productKey: productKey,
            keychainService: "\(bundleIdentifier).feedbackkit.visitor"
        )
    }

    /// Loads the Product Key and optional Keychain service from a bundle's Info.plist.
    public init(bundle: Bundle = .main) throws {
        guard let productKey = bundle.object(
            forInfoDictionaryKey: Self.productKeyInfoDictionaryKey
        ) as? String else {
            throw FeedbackConfigurationError.missingInfoDictionaryValue(
                key: Self.productKeyInfoDictionaryKey
            )
        }

        if let keychainService = bundle.object(
            forInfoDictionaryKey: Self.keychainServiceInfoDictionaryKey
        ) as? String {
            try self.init(productKey: productKey, keychainService: keychainService)
        } else {
            try self.init(productKey: productKey, bundle: bundle)
        }
    }

    internal init(
        productKey: String,
        keychainService: String,
        apiBaseURL: URL
    ) throws {
        let productKey = productKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard productKey.isEmpty == false else {
            throw FeedbackConfigurationError.emptyProductKey
        }

        let keychainService = keychainService.trimmingCharacters(in: .whitespacesAndNewlines)
        guard keychainService.isEmpty == false else {
            throw FeedbackConfigurationError.emptyKeychainService
        }
        guard apiBaseURL.isFeedbackSecureTransportURL else {
            throw FeedbackClientError(kind: .invalidURL)
        }

        self.productKey = productKey
        self.keychainService = keychainService
        self.apiBaseURL = apiBaseURL
    }

    internal static let productionAPIBaseURL = URL(
        string: "https://api.feedkit.cn/v1/api"
    )!
}

public protocol FeedbackAppMetadataProvider: Sendable {
    func clientContext(locale: Locale) async -> FeedbackClientContext
}

public struct DefaultFeedbackAppMetadataProvider: FeedbackAppMetadataProvider {
    private let bundle: Bundle

    public init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    public func clientContext(locale: Locale) async -> FeedbackClientContext {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        #if os(iOS)
        let osVersion = await MainActor.run { UIDevice.current.systemVersion }
        let category = await MainActor.run { UIDevice.current.userInterfaceIdiom == .pad ? "tablet" : "phone" }
        #else
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let category = "desktop"
        #endif
        return FeedbackClientContext(
            appVersion: version,
            buildNumber: build,
            osVersion: osVersion,
            deviceCategory: category,
            locale: locale.feedbackContentIdentifier
        )
    }
}

#if os(iOS)
import UIKit
#endif
