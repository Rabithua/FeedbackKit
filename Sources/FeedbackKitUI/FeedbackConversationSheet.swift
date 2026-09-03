import FeedbackKitCore
import SwiftUI

/// FeedbackKit's ready-made conversation sheet for a prepared administrator reply.
public struct FeedbackConversationSheet: View {
    private let presentation: FeedbackReplyPresentation
    private let controller: FeedbackReplyInboxController
    private let style: FeedbackStyle
    private let haptics: FeedbackHaptics
    private let languagePolicy: FeedbackLanguagePolicy

    @Environment(\.locale) private var hostLocale

    public init(
        presentation: FeedbackReplyPresentation,
        controller: FeedbackReplyInboxController,
        style: FeedbackStyle = .default,
        haptics: FeedbackHaptics = .none,
        languagePolicy: FeedbackLanguagePolicy = .followHost
    ) {
        self.presentation = presentation
        self.controller = controller
        self.style = style
        self.haptics = haptics
        self.languagePolicy = languagePolicy
    }

    public var body: some View {
        FeedbackDetailSheet(
            id: presentation.feedbackID,
            initialDetail: presentation.detail,
            client: controller.client,
            style: style,
            voteChanged: { _ in },
            viewed: { await controller.acknowledge(presentation) },
            close: { controller.dismissPresentation(presentation) }
        )
        .environment(\.feedbackHaptics, haptics)
        .environment(\.locale, locale)
        .environment(\.feedbackLocalization, FeedbackLocalization(locale: locale))
        .tint(.accentColor)
    }

    private var locale: Locale {
        languagePolicy.resolve(hostLocale: hostLocale)
    }
}
