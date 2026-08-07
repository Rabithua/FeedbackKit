import Foundation

public enum FeedbackLanguagePolicy: Sendable, Equatable {
    case followHost
    case fixed(Locale)

    func resolve(hostLocale: Locale) -> Locale {
        switch self {
        case .followHost:
            hostLocale
        case let .fixed(locale):
            locale
        }
    }
}
