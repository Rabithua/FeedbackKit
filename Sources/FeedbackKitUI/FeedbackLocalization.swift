import FeedbackKitCore
import Foundation
import SwiftUI

struct FeedbackLocalization: EnvironmentKey, Sendable {
    static let defaultValue = FeedbackLocalization(locale: .current)

    let locale: Locale
    private let localizedBundle: Bundle

    init(locale: Locale) {
        self.locale = locale
        localizedBundle = Self.bundle(for: locale)
    }

    func text(_ key: String) -> String {
        localizedBundle.localizedString(
            forKey: key,
            value: key,
            table: "Localizable"
        )
    }

    func errorMessage(for error: Error) -> String {
        guard let clientError = error as? FeedbackClientError,
              clientError.kind == .server,
              clientError.context.statusCode == 503,
              let code = clientError.context.serverCode,
              Self.temporarilyUnavailableCodes.contains(code)
        else {
            return error.localizedDescription
        }
        return text("feedbackkit.error.service.temporarily.unavailable")
    }

    private static func bundle(for locale: Locale) -> Bundle {
        let available = Bundle.module.localizations.filter { $0 != "Base" }
        let identifier = Bundle.preferredLocalizations(
            from: available,
            forPreferences: [locale.identifier]
        ).first ?? Bundle.module.developmentLocalization

        guard let identifier,
              let path = Bundle.module.path(
                forResource: identifier,
                ofType: "lproj"
              ),
              let bundle = Bundle(path: path) else {
            return .module
        }
        return bundle
    }

    private static let temporarilyUnavailableCodes: Set<String> = [
        "feedback_feature_unavailable",
        "feedback_service_read_only",
        "feedback_storage_unavailable",
    ]

    func kind(_ kind: FeedbackKind) -> String {
        switch kind {
        case .bug: text("feedbackkit.kind.bug")
        case .suggestion: text("feedbackkit.kind.suggestion")
        case .praise: text("feedbackkit.kind.praise")
        case .conversation: text("feedbackkit.kind.conversation")
        case .survey: text("feedbackkit.kind.survey")
        }
    }

    func status(_ status: FeedbackStatus) -> String {
        switch status {
        case .open: text("feedbackkit.status.open")
        case .resolved: text("feedbackkit.status.resolved")
        case .closed: text("feedbackkit.status.closed")
        }
    }

    func stage(_ stage: RoadmapStage) -> String {
        switch stage {
        case .urgent: text("feedbackkit.stage.urgent")
        case .later: text("feedbackkit.stage.later")
        case .undecided: text("feedbackkit.stage.undecided")
        }
    }
}

extension EnvironmentValues {
    var feedbackLocalization: FeedbackLocalization {
        get { self[FeedbackLocalization.self] }
        set { self[FeedbackLocalization.self] = newValue }
    }
}
