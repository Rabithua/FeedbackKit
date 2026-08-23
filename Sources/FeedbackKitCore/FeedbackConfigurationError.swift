import Foundation

/// A local configuration failure detected before FeedbackKit uses the network or Keychain.
public enum FeedbackConfigurationError: Error, Equatable, Sendable {
    case missingInfoDictionaryValue(key: String)
    case emptyProductKey
    case missingBundleIdentifier
    case emptyKeychainService
}

extension FeedbackConfigurationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .missingInfoDictionaryValue(key):
            "Add a non-empty \(key) value to the app's Info.plist."
        case .emptyProductKey:
            "FeedbackProductKey must not be empty."
        case .missingBundleIdentifier:
            "Set an app bundle identifier or provide an explicit FeedbackKeychainService."
        case .emptyKeychainService:
            "FeedbackKeychainService must not be empty."
        }
    }
}
